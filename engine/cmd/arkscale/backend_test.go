package main

import (
	"encoding/json"
	"net/netip"
	"testing"

	"tailscale.com/net/dns"
	"tailscale.com/util/dnsname"
	"tailscale.com/wgengine/router"
)

func TestBackendProtocol(t *testing.T) {
	config, err := parseStartConfig(`{"schemaVersion":1,"stateDir":"/data/storage/el2/base/files"}`)
	if err != nil || config.StateDir != "/data/storage/el2/base/files" {
		t.Fatalf("parseStartConfig() = %+v, %v", config, err)
	}
	for _, invalid := range []string{
		`{"schemaVersion":2,"stateDir":"/data/storage/el2/base/files"}`,
		`{"schemaVersion":1,"stateDir":"relative"}`,
	} {
		if _, err := parseStartConfig(invalid); err == nil {
			t.Fatalf("parseStartConfig(%s) succeeded", invalid)
		}
	}

	runtime := &backendRuntime{mtu: harmonyTunMTU}
	err = runtime.setConfig(&router.Config{
		LocalAddrs: []netip.Prefix{netip.MustParsePrefix("100.64.0.1/32"), netip.MustParsePrefix("fd7a:115c:a1e0::1/128")},
		Routes:     []netip.Prefix{netip.MustParsePrefix("100.64.0.2/32")},
		NewMTU:     1400,
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
		len(event.Nameservers) != 1 || event.SearchDomains[0] != "tailnet.ts.net" {
		t.Fatalf("vpn config event = %+v", event)
	}
}
