package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/netip"
	"os"
	"path/filepath"
	"strings"

	"go4.org/netipx"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnlocal"
	"tailscale.com/ipn/store"
	"tailscale.com/net/dns"
	"tailscale.com/net/netmon"
	"tailscale.com/net/tsdial"
	"tailscale.com/paths"
	"tailscale.com/tsd"
	"tailscale.com/types/logid"
	"tailscale.com/wgengine"
	"tailscale.com/wgengine/router"
)

const eventSchemaVersion = 1

var engineEvents = make(chan []byte, 64)

type startConfig struct {
	SchemaVersion int    `json:"schemaVersion"`
	StateDir      string `json:"stateDir"`
}

type backendRuntime struct {
	backend          *ipnlocal.LocalBackend
	netMon           *netmon.Monitor
	configGeneration uint64
	mtu              int
	ctx              context.Context
	cancel           context.CancelFunc
}

type stateEvent struct {
	SchemaVersion int    `json:"schemaVersion"`
	Type          string `json:"type"`
	State         string `json:"state"`
}

type loginURLEvent struct {
	SchemaVersion int    `json:"schemaVersion"`
	Type          string `json:"type"`
	URL           string `json:"url"`
}

type healthEvent struct {
	SchemaVersion int    `json:"schemaVersion"`
	Type          string `json:"type"`
	Severity      string `json:"severity"`
	Message       string `json:"message"`
}

type prefixEvent struct {
	IP           string `json:"ip"`
	PrefixLength int    `json:"prefixLength"`
	Family       int    `json:"family"`
}

type vpnConfigEvent struct {
	SchemaVersion int           `json:"schemaVersion"`
	Type          string        `json:"type"`
	Generation    uint64        `json:"generation"`
	LocalAddrs    []prefixEvent `json:"localAddrs"`
	Routes        []prefixEvent `json:"routes"`
	LocalRoutes   []prefixEvent `json:"localRoutes"`
	Nameservers   []string      `json:"nameservers"`
	SearchDomains []string      `json:"searchDomains"`
	MTU           int           `json:"mtu"`
}

func parseStartConfig(raw string) (startConfig, error) {
	var config startConfig
	if err := json.Unmarshal([]byte(raw), &config); err != nil {
		return config, err
	}
	if config.SchemaVersion != eventSchemaVersion {
		return config, fmt.Errorf("unsupported schemaVersion %d", config.SchemaVersion)
	}
	config.StateDir = filepath.Clean(config.StateDir)
	if !filepath.IsAbs(config.StateDir) || config.StateDir == string(filepath.Separator) {
		return config, errors.New("stateDir must be an absolute app-private directory")
	}
	return config, nil
}

func newBackendRuntime(config startConfig, tunDevice *multiTUN) (_ *backendRuntime, err error) {
	if err := setDefaultEnv("HOME", config.StateDir); err != nil {
		return nil, err
	}
	if err := setDefaultEnv("XDG_CACHE_HOME", filepath.Join(config.StateDir, "cache")); err != nil {
		return nil, err
	}
	if err := setDefaultEnv("XDG_CONFIG_HOME", filepath.Join(config.StateDir, "config")); err != nil {
		return nil, err
	}
	paths.AppSharedDir.Store(config.StateDir)

	logf := log.Printf
	stateStore, err := store.NewFileStore(logf, filepath.Join(config.StateDir, "tailscaled.state"))
	if err != nil {
		return nil, fmt.Errorf("open state store: %w", err)
	}
	netMon, err := netmon.New(logf)
	if err != nil {
		return nil, fmt.Errorf("create network monitor: %w", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	runtime := &backendRuntime{
		netMon: netMon,
		mtu:    harmonyTunMTU,
		ctx:    ctx,
		cancel: cancel,
	}

	sys := new(tsd.System)
	sys.Set(stateStore)
	dialer := new(tsdial.Dialer)
	callbackRouter := &router.CallbackRouter{
		SetBoth:    runtime.setConfig,
		InitialMTU: harmonyTunMTU,
	}
	engine, err := wgengine.NewUserspaceEngine(logf, wgengine.Config{
		Tun:           tunDevice,
		Router:        callbackRouter,
		DNS:           callbackRouter,
		NetMon:        netMon,
		Dialer:        dialer,
		SetSubsystem:  sys.Set,
		HealthTracker: sys.HealthTracker(),
		Metrics:       sys.UserMetricsRegistry(),
		ControlKnobs:  sys.ControlKnobs(),
	})
	if err != nil {
		cancel()
		_ = netMon.Close()
		return nil, fmt.Errorf("create userspace engine: %w", err)
	}
	sys.Set(engine)

	backend, err := ipnlocal.NewLocalBackend(logf, logid.PublicID{}, sys, 0)
	if err != nil {
		cancel()
		engine.Close()
		_ = netMon.Close()
		return nil, fmt.Errorf("create LocalBackend: %w", err)
	}
	runtime.backend = backend
	backend.SetNotifyCallback(runtime.notify)
	if err := backend.Start(ipn.Options{}); err != nil {
		runtime.Close()
		return nil, fmt.Errorf("start LocalBackend: %w", err)
	}
	_, err = backend.EditPrefs(&ipn.MaskedPrefs{
		Prefs:          ipn.Prefs{WantRunning: true},
		WantRunningSet: true,
	})
	if err != nil {
		runtime.Close()
		return nil, fmt.Errorf("enable LocalBackend: %w", err)
	}
	return runtime, nil
}

func setDefaultEnv(name, value string) error {
	if _, exists := os.LookupEnv(name); exists {
		return nil
	}
	return os.Setenv(name, value)
}

func (r *backendRuntime) notify(notify ipn.Notify) {
	if notify.State != nil {
		_ = r.emit(stateEvent{
			SchemaVersion: eventSchemaVersion,
			Type:          "state",
			State:         eventState(*notify.State),
		})
		if *notify.State == ipn.NeedsLogin {
			go func() {
				if err := r.backend.StartLoginInteractive(r.ctx); err != nil && r.ctx.Err() == nil {
					r.emitHealth("error", "interactive login failed: "+err.Error())
				}
			}()
		} else if *notify.State == ipn.NeedsMachineAuth {
			r.emitHealth("warning", "device approval is required")
		}
	}
	if notify.BrowseToURL != nil {
		_ = r.emit(loginURLEvent{
			SchemaVersion: eventSchemaVersion,
			Type:          "login-url",
			URL:           *notify.BrowseToURL,
		})
	}
	if notify.ErrMessage != nil {
		r.emitHealth("error", *notify.ErrMessage)
	}
}

func eventState(state ipn.State) string {
	switch state {
	case ipn.NeedsLogin:
		return "needs-login"
	case ipn.Starting, ipn.NoState, ipn.NeedsMachineAuth:
		return "starting"
	case ipn.Running:
		return "running"
	case ipn.Stopped:
		return "stopped"
	default:
		return "error"
	}
}

func (r *backendRuntime) setConfig(routeConfig *router.Config, dnsConfig *dns.OSConfig) error {
	if routeConfig == nil || len(routeConfig.LocalAddrs) == 0 {
		return nil
	}
	if routeConfig.NewMTU > 0 {
		r.mtu = routeConfig.NewMTU
	}
	r.configGeneration++
	effectiveRoutes, err := subtractRoutes(routeConfig.Routes, routeConfig.LocalRoutes)
	if err != nil {
		return err
	}
	event := vpnConfigEvent{
		SchemaVersion: eventSchemaVersion,
		Type:          "vpn-config",
		Generation:    r.configGeneration,
		LocalAddrs:    prefixes(routeConfig.LocalAddrs),
		Routes:        prefixes(effectiveRoutes),
		LocalRoutes:   prefixes(routeConfig.LocalRoutes),
		Nameservers:   make([]string, 0),
		SearchDomains: make([]string, 0),
		MTU:           r.mtu,
	}
	if dnsConfig != nil {
		for _, address := range dnsConfig.Nameservers {
			event.Nameservers = append(event.Nameservers, address.String())
		}
		for _, domain := range dnsConfig.SearchDomains {
			event.SearchDomains = append(event.SearchDomains, strings.TrimSuffix(string(domain), "."))
		}
	}
	return r.emit(event)
}

func subtractRoutes(routes, localRoutes []netip.Prefix) ([]netip.Prefix, error) {
	var builder netipx.IPSetBuilder
	for _, route := range routes {
		builder.AddPrefix(route)
	}
	for _, route := range localRoutes {
		builder.RemovePrefix(route)
	}
	set, err := builder.IPSet()
	if err != nil {
		return nil, err
	}
	return set.Prefixes(), nil
}

func prefixes(values []netip.Prefix) []prefixEvent {
	result := make([]prefixEvent, 0, len(values))
	for _, prefix := range values {
		family := 2
		if prefix.Addr().Is4() {
			family = 1
		}
		result = append(result, prefixEvent{
			IP:           prefix.Addr().String(),
			PrefixLength: prefix.Bits(),
			Family:       family,
		})
	}
	return result
}

func (r *backendRuntime) emit(value any) error {
	return emitEngineEvent(value)
}

func (r *backendRuntime) emitHealth(severity, message string) {
	_ = r.emit(healthEvent{
		SchemaVersion: eventSchemaVersion,
		Type:          "health",
		Severity:      severity,
		Message:       message,
	})
}

func (r *backendRuntime) Close() {
	r.cancel()
	if r.backend != nil {
		r.backend.Shutdown()
	}
	_ = r.netMon.Close()
}

func emitEngineEvent(value any) error {
	event, err := json.Marshal(value)
	if err != nil {
		return err
	}
	engineEvents <- event
	return nil
}
