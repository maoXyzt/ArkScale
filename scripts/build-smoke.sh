#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_GO_ROOT=${ARKSCALE_GO_ROOT:-$ARKSCALE_ROOT/third_party/ohos_golang_go}
: "${ARKSCALE_OHOS_NATIVE:?set ARKSCALE_OHOS_NATIVE to the Linux OHOS native SDK directory}"

ARKSCALE_GO_COMMIT=2d8b23f6923100d8c90d8add9299da2c9d032a20
if [ "$(git -C "$ARKSCALE_GO_ROOT" rev-parse HEAD)" != "$ARKSCALE_GO_COMMIT" ]; then
  echo "error: OpenHarmony-SIG Go checkout is not pinned" >&2
  exit 1
fi
if [ ! -x "$ARKSCALE_GO_ROOT/bin/go" ]; then
  echo "error: run pnpm run build:p0 first" >&2
  exit 1
fi

ARKSCALE_GOCACHE=${GOCACHE:-$ARKSCALE_ROOT/.cache/go-build}
ARKSCALE_GOMODCACHE=${GOMODCACHE:-$ARKSCALE_ROOT/.cache/go-mod}
ARKSCALE_GOPATH=${GOPATH:-$ARKSCALE_ROOT/.cache/gopath}
mkdir -p \
  "$ARKSCALE_ROOT/build/arm64-v8a" \
  "$ARKSCALE_ROOT/entry/libs/arm64-v8a" \
  "$ARKSCALE_GOCACHE" \
  "$ARKSCALE_GOMODCACHE" \
  "$ARKSCALE_GOPATH"
cd "$ARKSCALE_ROOT/smoke"
env \
  GOENV=off \
  GOCACHE="$ARKSCALE_GOCACHE" \
  GOMODCACHE="$ARKSCALE_GOMODCACHE" \
  GOPATH="$ARKSCALE_GOPATH" \
  GOTOOLCHAIN=local \
  GOOS=openharmony \
  GOARCH=arm64 \
  CGO_ENABLED=1 \
  CC="$ARKSCALE_ROOT/scripts/ohos-clang" \
  CXX="$ARKSCALE_ROOT/scripts/ohos-clang++" \
  AR="$ARKSCALE_OHOS_NATIVE/llvm/bin/llvm-ar" \
  "$ARKSCALE_GO_ROOT/bin/go" build \
    -buildvcs=false \
    -buildmode=c-shared \
    -trimpath \
    -o "$ARKSCALE_ROOT/build/arm64-v8a/libarkscale_smoke.so" \
    ./cmd/arkscale_smoke

cp "$ARKSCALE_ROOT/build/arm64-v8a/libarkscale_smoke.so" \
  "$ARKSCALE_ROOT/entry/libs/arm64-v8a/libarkscale_smoke.so"
