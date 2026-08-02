package main

import (
	"io"
	"os"
	"sync"

	"github.com/tailscale/wireguard-go/tun"
)

const harmonyTunMTU = 1280

type fdTUN struct {
	file      *os.File
	events    chan tun.Event
	closeOnce sync.Once
}

func newFDTUN(fd int) *fdTUN {
	t := &fdTUN{
		file:   os.NewFile(uintptr(fd), "arkscale-tun"),
		events: make(chan tun.Event, 1),
	}
	t.events <- tun.EventUp
	return t
}

func (t *fdTUN) File() *os.File { return t.file }

func (t *fdTUN) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	if len(bufs) == 0 || len(sizes) == 0 || offset < 0 || offset > len(bufs[0]) {
		return 0, io.ErrShortBuffer
	}
	n, err := t.file.Read(bufs[0][offset:])
	if err != nil {
		return 0, err
	}
	sizes[0] = n
	return 1, nil
}

func (t *fdTUN) Write(bufs [][]byte, offset int) (int, error) {
	for i, buf := range bufs {
		if offset < 0 || offset > len(buf) {
			return i, io.ErrShortBuffer
		}
		n, err := t.file.Write(buf[offset:])
		if err != nil {
			return i, err
		}
		if n != len(buf)-offset {
			return i, io.ErrShortWrite
		}
	}
	return len(bufs), nil
}

func (t *fdTUN) MTU() (int, error)        { return harmonyTunMTU, nil }
func (t *fdTUN) Name() (string, error)    { return "arkscale-tun", nil }
func (t *fdTUN) Events() <-chan tun.Event { return t.events }
func (t *fdTUN) BatchSize() int           { return 1 }

func (t *fdTUN) Close() error {
	var err error
	t.closeOnce.Do(func() {
		close(t.events)
		err = t.file.Close()
	})
	return err
}
