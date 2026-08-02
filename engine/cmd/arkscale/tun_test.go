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

func TestMultiTUNWaitAndReplace(t *testing.T) {
	dev := newMultiTUN()
	defer dev.Close()

	buf := make([]byte, 64)
	sizes := make([]int, 1)
	readDone := make(chan error, 1)
	go func() {
		_, err := dev.Read([][]byte{buf}, sizes, 0)
		readDone <- err
	}()

	first, firstPeer := socketPairTUN(t)
	defer firstPeer.Close()
	dev.Add(first)
	if event := <-dev.Events(); event != tun.EventUp {
		t.Fatalf("first event = %v, want EventUp", event)
	}
	want := []byte{0x45, 0, 0, 20}
	if _, err := firstPeer.Write(want); err != nil {
		t.Fatal(err)
	}
	if err := <-readDone; err != nil || !bytes.Equal(buf[:sizes[0]], want) {
		t.Fatalf("first Read() = %x, %v", buf[:sizes[0]], err)
	}

	second, secondPeer := socketPairTUN(t)
	defer secondPeer.Close()
	dev.Add(second)
	if event := <-dev.Events(); event != tun.EventUp {
		t.Fatalf("replacement event = %v, want EventUp", event)
	}
	if _, err := secondPeer.Write(want); err != nil {
		t.Fatal(err)
	}
	if count, err := dev.Read([][]byte{buf}, sizes, 0); err != nil || count != 1 || !bytes.Equal(buf[:sizes[0]], want) {
		t.Fatalf("replacement Read() = %d, %x, %v", count, buf[:sizes[0]], err)
	}
	if count, err := dev.Write([][]byte{want}, 0); err != nil || count != 1 {
		t.Fatalf("replacement Write() = %d, %v", count, err)
	}
	if count, err := secondPeer.Read(buf); err != nil || !bytes.Equal(buf[:count], want) {
		t.Fatalf("replacement peer Read() = %x, %v", buf[:count], err)
	}

	dev.Shutdown()
	if event := <-dev.Events(); event != tun.EventDown {
		t.Fatalf("shutdown event = %v, want EventDown", event)
	}
}

func socketPairTUN(t *testing.T) (*fdTUN, *os.File) {
	t.Helper()
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	return newFDTUN(fds[0]), os.NewFile(uintptr(fds[1]), "peer")
}
