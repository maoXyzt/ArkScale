package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	_ "tailscale.com/ipn/ipnlocal"
	_ "tailscale.com/wgengine"
)

const (
	resultInvalidArgument = 1
	resultNotImplemented  = 2
)

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
	return resultNotImplemented
}

//export arkscale_network_changed
func arkscale_network_changed() {}

//export arkscale_stop
func arkscale_stop() C.int {
	return resultNotImplemented
}

func main() {}
