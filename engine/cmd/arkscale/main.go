package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"sync"
	"unsafe"

	_ "tailscale.com/ipn/ipnlocal"
	_ "tailscale.com/wgengine"
)

const (
	resultOK              = 0
	resultInvalidArgument = 1
	resultNotImplemented  = 2
)

var engineState struct {
	sync.Mutex
	tun        *multiTUN
	generation uint64
}

//export arkscale_start
func arkscale_start(configJSON *C.char) C.int {
	if configJSON == nil {
		return resultInvalidArgument
	}
	return resultNotImplemented
}

//export arkscale_next_event
func arkscale_next_event(eventJSON **C.char, length *C.size_t, timeoutMS C.uint32_t) C.int {
	if eventJSON == nil || length == nil {
		return resultInvalidArgument
	}
	*eventJSON = nil
	*length = 0
	_ = timeoutMS
	return resultNotImplemented
}

//export arkscale_free
func arkscale_free(pointer unsafe.Pointer) {
	C.free(pointer)
}

//export arkscale_set_tun
func arkscale_set_tun(dupFD C.int, generation C.uint64_t) C.int {
	if dupFD < 0 || generation == 0 {
		return resultInvalidArgument
	}

	engineState.Lock()
	if uint64(generation) <= engineState.generation {
		engineState.Unlock()
		return resultInvalidArgument
	}
	if engineState.tun == nil {
		engineState.tun = newMultiTUN()
	}
	tun := engineState.tun
	engineState.generation = uint64(generation)
	tun.Add(newFDTUN(int(dupFD)))
	engineState.Unlock()
	return resultOK
}

//export arkscale_network_changed
func arkscale_network_changed() {}

//export arkscale_stop
func arkscale_stop() C.int {
	engineState.Lock()
	defer engineState.Unlock()
	tun := engineState.tun
	if tun != nil {
		tun.Shutdown()
	}
	return resultOK
}

func main() {}
