#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_GO_ROOT=${ARKSCALE_GO_ROOT:-$ARKSCALE_ROOT/third_party/ohos_golang_go}
: "${ARKSCALE_OHOS_NATIVE:?set ARKSCALE_OHOS_NATIVE to the Linux OHOS native SDK directory}"

ARKSCALE_GO_COMMIT=2d8b23f6923100d8c90d8add9299da2c9d032a20
ARKSCALE_TAILSCALE_COMMIT=e4d64c6faf827a308ec20b39651225178e6743c0
if [ "$(git -C "$ARKSCALE_GO_ROOT" rev-parse HEAD)" != "$ARKSCALE_GO_COMMIT" ]; then
  echo "error: OpenHarmony-SIG Go checkout is not pinned" >&2
  exit 1
fi
if [ "$(git -C "$ARKSCALE_ROOT/third_party/tailscale" rev-parse HEAD)" != "$ARKSCALE_TAILSCALE_COMMIT" ]; then
  echo "error: Tailscale checkout is not pinned" >&2
  exit 1
fi

mkdir -p \
  "$ARKSCALE_ROOT/build/arm64-v8a" \
  "$ARKSCALE_ROOT/entry/libs/arm64-v8a"
cd "$ARKSCALE_ROOT/engine"
env \
  GOTOOLCHAIN=local \
  GOOS=openharmony \
  GOARCH=arm64 \
  CGO_ENABLED=1 \
  CC="$ARKSCALE_ROOT/scripts/ohos-clang" \
  CXX="$ARKSCALE_ROOT/scripts/ohos-clang++" \
  AR="$ARKSCALE_OHOS_NATIVE/llvm/bin/llvm-ar" \
  "$ARKSCALE_GO_ROOT/bin/go" build \
    -buildvcs=false \
    -mod=mod \
    -buildmode=c-shared \
    -trimpath \
    -o "$ARKSCALE_ROOT/build/arm64-v8a/libarkscale_engine.so" \
    ./cmd/arkscale

cp "$ARKSCALE_ROOT/engine/include/arkscale_engine.h" \
  "$ARKSCALE_ROOT/build/arm64-v8a/arkscale_engine.h"
cp "$ARKSCALE_ROOT/build/arm64-v8a/libarkscale_engine.so" \
  "$ARKSCALE_ROOT/entry/libs/arm64-v8a/libarkscale_engine.so"
