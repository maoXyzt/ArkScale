#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_GO_ROOT=${ARKSCALE_GO_ROOT:-$ARKSCALE_ROOT/third_party/ohos_golang_go}

list_files() {
  cd "$ARKSCALE_ROOT/engine"
  env \
    GOTOOLCHAIN=local \
    GOOS=openharmony \
    GOARCH=arm64 \
    CGO_ENABLED=0 \
    "$ARKSCALE_GO_ROOT/bin/go" list \
      -buildvcs=false \
      -mod=mod \
      -f '{{join .GoFiles " "}}' \
      "$1"
}

require_file() {
  case " $2 " in
    *" $3 "*) ;;
    *)
      echo "error: $1 did not select $3: $2" >&2
      exit 1
      ;;
  esac
}

reject_file() {
  case " $2 " in
    *" $3 "*)
      echo "error: $1 selected Linux-only $3: $2" >&2
      exit 1
      ;;
  esac
}

NETNS_FILES=$(list_files tailscale.com/net/netns)
require_file netns "$NETNS_FILES" netns_default.go
reject_file netns "$NETNS_FILES" netns_linux.go

NETMON_FILES=$(list_files tailscale.com/net/netmon)
require_file netmon "$NETMON_FILES" netmon_polling.go
require_file netmon "$NETMON_FILES" interfaces_defaultrouteif_todo.go
reject_file netmon "$NETMON_FILES" netmon_linux.go
reject_file netmon "$NETMON_FILES" interfaces_linux.go

ROUTER_FILES=$(list_files tailscale.com/wgengine/router)
require_file router "$ROUTER_FILES" router_default.go
reject_file router "$ROUTER_FILES" router_linux.go
reject_file router "$ROUTER_FILES" runner.go

MAGICSOCK_FILES=$(list_files tailscale.com/wgengine/magicsock)
require_file magicsock "$MAGICSOCK_FILES" magicsock_default.go
require_file magicsock "$MAGICSOCK_FILES" batching_conn_default.go
require_file magicsock "$MAGICSOCK_FILES" peermtu_stubs.go
reject_file magicsock "$MAGICSOCK_FILES" magicsock_linux.go
reject_file magicsock "$MAGICSOCK_FILES" batching_conn_linux.go
reject_file magicsock "$MAGICSOCK_FILES" peermtu.go
reject_file magicsock "$MAGICSOCK_FILES" peermtu_linux.go
reject_file magicsock "$MAGICSOCK_FILES" peermtu_unix.go

TSTUN_FILES=$(list_files tailscale.com/net/tstun)
require_file tstun "$TSTUN_FILES" linkattrs_notlinux.go
require_file tstun "$TSTUN_FILES" wrap_noop.go
reject_file tstun "$TSTUN_FILES" linkattrs_linux.go
reject_file tstun "$TSTUN_FILES" wrap_linux.go
reject_file tstun "$TSTUN_FILES" tun_linux.go

echo "OpenHarmony platform selection audit passed"
