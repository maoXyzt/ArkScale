// Adapted from Tailscale Android's multiTUN design.
// Copyright (c) Tailscale Inc & AUTHORS
// SPDX-License-Identifier: BSD-3-Clause

package main

import (
	"os"
	"sync"

	"github.com/tailscale/wireguard-go/tun"
)

// multiTUN keeps wgengine attached to one stable device while Harmony replaces
// the statically configured VPN file descriptor underneath it.
type multiTUN struct {
	mu        sync.Mutex
	device    tun.Device
	changed   chan struct{}
	events    chan tun.Event
	closed    bool
	closeOnce sync.Once
}

func newMultiTUN() *multiTUN {
	return &multiTUN{
		changed: make(chan struct{}),
		events:  make(chan tun.Event, 1),
	}
}

func (t *multiTUN) Add(device tun.Device) {
	t.mu.Lock()
	old := t.device
	t.device = device
	close(t.changed)
	t.changed = make(chan struct{})
	t.mu.Unlock()
	if old != nil {
		_ = old.Close()
	}
	t.signal(tun.EventUp)
}

func (t *multiTUN) current() (tun.Device, <-chan struct{}, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.device, t.changed, t.closed
}

func (t *multiTUN) waitForDevice() (tun.Device, error) {
	for {
		device, changed, closed := t.current()
		if closed {
			return nil, os.ErrClosed
		}
		if device != nil {
			return device, nil
		}
		<-changed
	}
}

func (t *multiTUN) stillCurrent(device tun.Device) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return !t.closed && t.device == device
}

func (t *multiTUN) Read(data [][]byte, sizes []int, offset int) (int, error) {
	for {
		device, err := t.waitForDevice()
		if err != nil {
			return 0, err
		}
		count, err := device.Read(data, sizes, offset)
		if err == nil || t.stillCurrent(device) {
			return count, err
		}
	}
}

func (t *multiTUN) Write(data [][]byte, offset int) (int, error) {
	for {
		device, err := t.waitForDevice()
		if err != nil {
			return 0, err
		}
		count, err := device.Write(data, offset)
		if err == nil || t.stillCurrent(device) {
			return count, err
		}
	}
}

func (t *multiTUN) MTU() (int, error) {
	device, _, closed := t.current()
	if closed {
		return 0, os.ErrClosed
	}
	if device == nil {
		return harmonyTunMTU, nil
	}
	return device.MTU()
}

func (t *multiTUN) Name() (string, error) {
	device, _, closed := t.current()
	if closed {
		return "", os.ErrClosed
	}
	if device == nil {
		return "arkscale-tun", nil
	}
	return device.Name()
}

func (t *multiTUN) Events() <-chan tun.Event { return t.events }

func (t *multiTUN) Shutdown() {
	t.mu.Lock()
	device := t.device
	t.device = nil
	close(t.changed)
	t.changed = make(chan struct{})
	t.mu.Unlock()
	if device != nil {
		_ = device.Close()
	}
	t.signal(tun.EventDown)
}

func (t *multiTUN) Close() error {
	var closeErr error
	t.closeOnce.Do(func() {
		t.mu.Lock()
		device := t.device
		t.device = nil
		t.closed = true
		close(t.changed)
		t.mu.Unlock()
		if device != nil {
			closeErr = device.Close()
		}
		close(t.events)
	})
	return closeErr
}

func (t *multiTUN) signal(event tun.Event) {
	select {
	case t.events <- event:
	default:
	}
}

func (t *multiTUN) File() *os.File { panic("multiTUN has no stable file") }
func (t *multiTUN) BatchSize() int { return 1 }

var _ tun.Device = (*multiTUN)(nil)
