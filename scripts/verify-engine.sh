#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${ARKSCALE_OHOS_NATIVE:?set ARKSCALE_OHOS_NATIVE to the Linux OHOS native SDK directory}"
ARKSCALE_ENGINE="$ARKSCALE_ROOT/build/arm64-v8a/libarkscale_engine.so"
ARKSCALE_READELF="$ARKSCALE_OHOS_NATIVE/llvm/bin/llvm-readelf"
ARKSCALE_STRINGS="$ARKSCALE_OHOS_NATIVE/llvm/bin/llvm-strings"

if [ ! -f "$ARKSCALE_ENGINE" ]; then
  echo "error: engine output not found: $ARKSCALE_ENGINE" >&2
  exit 1
fi

grep -E '^[[:space:]]*sys\.Tun\.Get\(\)\.Start\(\)' \
  "$ARKSCALE_ROOT/engine/cmd/arkscale/backend.go" >/dev/null

ARKSCALE_HEADER=$("$ARKSCALE_READELF" -h "$ARKSCALE_ENGINE")
echo "$ARKSCALE_HEADER"
echo "$ARKSCALE_HEADER" | grep -q 'Class:.*ELF64'
echo "$ARKSCALE_HEADER" | grep -Eq 'Machine:.*AArch64'

ARKSCALE_DYNAMIC=$("$ARKSCALE_READELF" -d "$ARKSCALE_ENGINE")
echo "$ARKSCALE_DYNAMIC"
if echo "$ARKSCALE_DYNAMIC" | grep -Eq 'GLIBC_|RPATH|RUNPATH'; then
  echo "error: forbidden glibc dependency or runtime path found" >&2
  exit 1
fi
if "$ARKSCALE_READELF" --version-info "$ARKSCALE_ENGINE" | grep 'GLIBC_' >/dev/null; then
  echo "error: glibc symbol versions found" >&2
  exit 1
fi
if "$ARKSCALE_STRINGS" "$ARKSCALE_ENGINE" | grep -F "$ARKSCALE_ROOT" >/dev/null; then
  echo "error: build workspace path leaked into engine output" >&2
  exit 1
fi

ARKSCALE_DYNSYMS=$("$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_ENGINE")
for ARKSCALE_SYMBOL in \
  arkscale_start \
  arkscale_next_event \
  arkscale_free \
  arkscale_set_tun \
  arkscale_clear_tun \
  arkscale_network_changed \
  arkscale_probe_peer \
  arkscale_stop
do
  echo "$ARKSCALE_DYNSYMS" | grep "$ARKSCALE_SYMBOL" >/dev/null
done

echo "P0 engine verification passed"
