package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/netip"
	"testing"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/dns"
	"tailscale.com/util/dnsname"
	"tailscale.com/wgengine/router"
)

func TestBackendProtocol(t *testing.T) {
	config, err := parseStartConfig(`{"schemaVersion":1,"stateDir":"/data/storage/el2/base/files","baseNameservers":["192.0.2.53"],"baseSearchDomains":["lan"]}`)
	if err != nil || config.StateDir != "/data/storage/el2/base/files" {
		t.Fatalf("parseStartConfig() = %+v, %v", config, err)
	}
	baseDNS, err := config.baseDNSConfig()
	if err != nil || len(baseDNS.Nameservers) != 1 || baseDNS.Nameservers[0].String() != "192.0.2.53" ||
		len(baseDNS.SearchDomains) != 1 || baseDNS.SearchDomains[0] != "lan." {
		t.Fatalf("baseDNSConfig() = %+v, %v", baseDNS, err)
	}
	for _, invalid := range []string{
		`{"schemaVersion":2,"stateDir":"/data/storage/el2/base/files"}`,
		`{"schemaVersion":1,"stateDir":"relative"}`,
		`{"schemaVersion":1,"stateDir":"/data/storage/el2/base/files","baseNameservers":["not-an-ip"]}`,
	} {
		if _, err := parseStartConfig(invalid); err == nil {
			t.Fatalf("parseStartConfig(%s) succeeded", invalid)
		}
	}

	runtime := &backendRuntime{mtu: harmonyTunMTU}
	err = runtime.setConfig(&router.Config{
		LocalAddrs: []netip.Prefix{netip.MustParsePrefix("100.64.0.1/32"), netip.MustParsePrefix("fd7a:115c:a1e0::1/128")},
		Routes:     []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8")},
		LocalRoutes: []netip.Prefix{
			netip.MustParsePrefix("10.0.0.0/9"),
		},
		NewMTU: 1400,
	}, &dns.OSConfig{
		Nameservers:   []netip.Addr{netip.MustParseAddr("100.100.100.100")},
		SearchDomains: []dnsname.FQDN{"tailnet.ts.net."},
	})
	if err != nil {
		t.Fatal(err)
	}
	var event vpnConfigEvent
	if err := json.Unmarshal(<-engineEvents, &event); err != nil {
		t.Fatal(err)
	}
	if event.Generation != 1 || event.MTU != 1400 || len(event.LocalAddrs) != 2 ||
		event.LocalAddrs[0].Family != 1 || event.LocalAddrs[1].Family != 2 ||
		len(event.Routes) != 1 || event.Routes[0].IP != "10.128.0.0" || event.Routes[0].PrefixLength != 9 ||
		len(event.Nameservers) != 1 || event.SearchDomains[0] != "tailnet.ts.net" {
		t.Fatalf("vpn config event = %+v", event)
	}
}

func TestPeerPath(t *testing.T) {
	if got := peerPath(&ipnstate.PingResult{Endpoint: "192.0.2.1:41641"}); got != "direct 192.0.2.1:41641" {
		t.Fatalf("direct path = %q", got)
	}
	if got := peerPath(&ipnstate.PingResult{DERPRegionCode: "hkg"}); got != "derp hkg" {
		t.Fatalf("DERP path = %q", got)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := awaitPing(ctx, make(chan pingOutcome)); !errors.Is(err, context.Canceled) {
		t.Fatalf("awaitPing() error = %v", err)
	}
}

func TestParseProcessStats(t *testing.T) {
	rssKB, err := parseResidentKB("100 25 10 5 0 20 0\n", 4096)
	if err != nil || rssKB != 100 {
		t.Fatalf("parseResidentKB() = %d, %v", rssKB, err)
	}
	threads, err := parseThreads("Name:\tarkscale\nThreads:\t17\n")
	if err != nil || threads != 17 {
		t.Fatalf("parseThreads() = %d, %v", threads, err)
	}
}
