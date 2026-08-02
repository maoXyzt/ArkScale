package main

/*
#include <stdint.h>
*/
import "C"

import (
	"runtime"
	"sync"
	"sync/atomic"
	"time"
)

const (
	smokeOK              = 0
	smokeInvalidArgument = 1
	smokeInternalError   = 2
	smokeInvalidState    = 3
	smokeABIVersion      = 1
)

var worker struct {
	sync.Mutex
	stop  chan struct{}
	done  chan struct{}
	ticks atomic.Uint64
}

//export arkscale_smoke_version
func arkscale_smoke_version() C.uint32_t {
	return smokeABIVersion
}

//export arkscale_smoke_run
func arkscale_smoke_run(rounds C.uint32_t) C.int {
	if rounds == 0 || rounds > 1_000_000 {
		return smokeInvalidArgument
	}

	done := make(chan uint64, 1)
	go func() {
		var sum uint64
		for i := uint64(0); i < uint64(rounds); i++ {
			sum += i
		}
		done <- sum
	}()

	timer := time.NewTimer(5 * time.Second)
	defer timer.Stop()
	select {
	case sum := <-done:
		want := uint64(rounds) * uint64(rounds-1) / 2
		if sum != want {
			return smokeInternalError
		}
	case <-timer.C:
		return smokeInternalError
	}

	memory := make([]byte, int(rounds))
	for i := range memory {
		memory[i] = byte(i)
	}
	runtime.GC()
	runtime.KeepAlive(memory)
	return smokeOK
}

//export arkscale_smoke_start
func arkscale_smoke_start() C.int {
	worker.Lock()
	defer worker.Unlock()
	if worker.stop != nil {
		return smokeInvalidState
	}

	started := make(chan struct{})
	worker.stop = make(chan struct{})
	worker.done = make(chan struct{})
	worker.ticks.Store(0)
	go func(stop <-chan struct{}, done chan<- struct{}) {
		memory := make([]byte, 1024)
		memory[0] = 1
		ticker := time.NewTicker(100 * time.Millisecond)
		defer ticker.Stop()
		close(started)
		for {
			select {
			case <-ticker.C:
				memory[0]++
				worker.ticks.Add(1)
				runtime.Gosched()
			case <-stop:
				runtime.KeepAlive(memory)
				close(done)
				return
			}
		}
	}(worker.stop, worker.done)
	<-started
	return smokeOK
}

//export arkscale_smoke_stop
func arkscale_smoke_stop() C.int {
	worker.Lock()
	defer worker.Unlock()
	if worker.stop == nil {
		return smokeInvalidState
	}

	close(worker.stop)
	<-worker.done
	worker.stop = nil
	worker.done = nil
	return smokeOK
}

//export arkscale_smoke_ticks
func arkscale_smoke_ticks() C.uint64_t {
	return C.uint64_t(worker.ticks.Load())
}

func main() {}
