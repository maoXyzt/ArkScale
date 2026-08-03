package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"sync"
	"time"
	"unsafe"
)

const (
	resultOK              = 0
	resultInvalidArgument = 1
	resultNotImplemented  = 2
	resultInternalError   = 3
)

var engineState struct {
	sync.Mutex
	backend    *backendRuntime
	tun        *multiTUN
	generation uint64
}

//export arkscale_start
func arkscale_start(configJSON *C.char) C.int {
	if configJSON == nil {
		return resultInvalidArgument
	}
	config, err := parseStartConfig(C.GoString(configJSON))
	if err != nil {
		_ = emitEngineEvent(healthEvent{
			SchemaVersion: eventSchemaVersion,
			Type:          "health",
			Severity:      "error",
			Message:       "invalid start configuration",
		})
		return resultInvalidArgument
	}

	engineState.Lock()
	defer engineState.Unlock()
	if engineState.backend != nil {
		return resultOK
	}
	if engineState.tun == nil {
		engineState.tun = newMultiTUN()
	}
	backend, err := newBackendRuntime(config, engineState.tun)
	if err != nil {
		_ = engineState.tun.Close()
		engineState.tun = nil
		_ = emitEngineEvent(healthEvent{
			SchemaVersion: eventSchemaVersion,
			Type:          "health",
			Severity:      "error",
			Message:       err.Error(),
		})
		return resultInternalError
	}
	engineState.backend = backend
	return resultOK
}

//export arkscale_next_event
func arkscale_next_event(eventJSON **C.char, length *C.size_t, timeoutMS C.uint32_t) C.int {
	if eventJSON == nil || length == nil {
		return resultInvalidArgument
	}
	*eventJSON = nil
	*length = 0
	var event []byte
	if timeoutMS == 0 {
		select {
		case event = <-engineEvents:
		default:
			return resultOK
		}
	} else {
		timer := time.NewTimer(time.Duration(timeoutMS) * time.Millisecond)
		defer timer.Stop()
		select {
		case event = <-engineEvents:
		case <-timer.C:
			return resultOK
		}
	}
	*eventJSON = (*C.char)(C.CBytes(event))
	*length = C.size_t(len(event))
	return resultOK
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

//export arkscale_clear_tun
func arkscale_clear_tun() C.int {
	engineState.Lock()
	defer engineState.Unlock()
	if engineState.tun != nil {
		engineState.tun.Shutdown()
	}
	return resultOK
}

//export arkscale_network_changed
func arkscale_network_changed() {
	engineState.Lock()
	backend := engineState.backend
	engineState.Unlock()
	if backend != nil {
		backend.netMon.InjectEvent()
	}
}

//export arkscale_probe_peer
func arkscale_probe_peer(target *C.char, eventJSON **C.char, length *C.size_t) C.int {
	if target == nil || eventJSON == nil || length == nil {
		return resultInvalidArgument
	}
	*eventJSON = nil
	*length = 0
	engineState.Lock()
	defer engineState.Unlock()
	if engineState.backend == nil {
		return resultNotImplemented
	}
	event, err := engineState.backend.probePeer(C.GoString(target))
	if err != nil {
		return resultInvalidArgument
	}
	*eventJSON = (*C.char)(C.CBytes(event))
	*length = C.size_t(len(event))
	return resultOK
}

//export arkscale_stop
func arkscale_stop() C.int {
	engineState.Lock()
	defer engineState.Unlock()
	backend := engineState.backend
	engineState.backend = nil
	tun := engineState.tun
	if backend != nil {
		engineState.tun = nil
		backend.Close()
		_ = emitEngineEvent(stateEvent{
			SchemaVersion: eventSchemaVersion,
			Type:          "state",
			State:         "stopped",
		})
		return resultOK
	}
	if tun != nil {
		tun.Shutdown()
	}
	return resultOK
}

func main() {}
