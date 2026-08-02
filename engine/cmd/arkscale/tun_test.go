package main

import (
	"bytes"
	"os"
	"syscall"
	"testing"

	"github.com/tailscale/wireguard-go/tun"
)

func TestFDTUNReadWrite(t *testing.T) {
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	peer := os.NewFile(uintptr(fds[1]), "peer")
	defer peer.Close()

	dev := newFDTUN(fds[0])
	defer dev.Close()
	if event := <-dev.Events(); event != tun.EventUp {
		t.Fatalf("event = %v, want EventUp", event)
	}

	want := []byte{0x45, 0, 0, 20}
	if _, err := peer.Write(want); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 64)
	sizes := make([]int, 1)
	if n, err := dev.Read([][]byte{buf}, sizes, 4); err != nil || n != 1 || !bytes.Equal(buf[4:4+sizes[0]], want) {
		t.Fatalf("Read() = %d, %v, %x", n, err, buf[4:4+sizes[0]])
	}

	packet := append(make([]byte, 4), want...)
	if n, err := dev.Write([][]byte{packet}, 4); err != nil || n != 1 {
		t.Fatalf("Write() = %d, %v", n, err)
	}
	got := make([]byte, 64)
	n, err := peer.Read(got)
	if err != nil || !bytes.Equal(got[:n], want) {
		t.Fatalf("peer.Read() = %x, %v", got[:n], err)
	}
}
