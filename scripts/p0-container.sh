#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export ARKSCALE_OHOS_NATIVE="${ARKSCALE_OHOS_NATIVE:-/opt/ohos-sdk/linux/native}"
export ARKSCALE_GO_BOOTSTRAP="${ARKSCALE_GO_BOOTSTRAP:-/usr/local/go}"
export GOCACHE="${GOCACHE:-$ARKSCALE_ROOT/.cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-$ARKSCALE_ROOT/.cache/go-mod}"
export GOPATH="${GOPATH:-$ARKSCALE_ROOT/.cache/gopath}"
export GOENV=off
# ponytail: serial builds avoid amd64-emulation SIGSEGV; override on native x86_64.
export GOMAXPROCS="${GOMAXPROCS:-1}"

"$ARKSCALE_ROOT/scripts/fetch-deps.sh"
"$ARKSCALE_ROOT/scripts/build-go-toolchain.sh"
"$ARKSCALE_ROOT/scripts/audit-openharmony-platform.sh"
"$ARKSCALE_ROOT/scripts/build-engine.sh"
"$ARKSCALE_ROOT/scripts/verify-engine.sh"
