#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_DEVECO_HOME=${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app}
ARKSCALE_HAP="$ARKSCALE_ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"
ARKSCALE_BRIDGE="$ARKSCALE_ROOT/entry/build/default/intermediates/stripped_native_libs/default/arm64-v8a/libarkscale_bridge.so"
ARKSCALE_SMOKE="$ARKSCALE_ROOT/entry/libs/arm64-v8a/libarkscale_smoke.so"
ARKSCALE_READELF="$ARKSCALE_DEVECO_HOME/Contents/sdk/default/openharmony/native/llvm/bin/llvm-readelf"

if [ ! -f "$ARKSCALE_HAP" ] || [ ! -f "$ARKSCALE_BRIDGE" ] || [ ! -f "$ARKSCALE_SMOKE" ]; then
  echo "error: run pnpm run build:p1 first" >&2
  exit 1
fi

file "$ARKSCALE_BRIDGE" | grep -E 'ELF 64-bit.*ARM aarch64' >/dev/null
file "$ARKSCALE_SMOKE" | grep -E 'ELF 64-bit.*ARM aarch64' >/dev/null
unzip -l "$ARKSCALE_HAP" | grep 'libs/arm64-v8a/libarkscale_bridge.so' >/dev/null
unzip -l "$ARKSCALE_HAP" | grep 'libs/arm64-v8a/libarkscale_smoke.so' >/dev/null
unzip -p "$ARKSCALE_HAP" module.json | grep '"bundleName":"com.arkscale.client"' >/dev/null
unzip -p "$ARKSCALE_HAP" pack.info | grep '"compatible":22' >/dev/null
unzip -p "$ARKSCALE_HAP" pack.info | grep '"target":24' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_BRIDGE" | grep 'RegisterArkScaleBridgeModule' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_run' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_start' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_stop' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_ticks' >/dev/null
ARKSCALE_BRIDGE_DYNAMIC=$("$ARKSCALE_READELF" -d "$ARKSCALE_BRIDGE")
printf '%s\n' "$ARKSCALE_BRIDGE_DYNAMIC" | grep 'Shared library: \[libarkscale_smoke.so\]' >/dev/null
if printf '%s\n' "$ARKSCALE_BRIDGE_DYNAMIC" | grep -E '\((RPATH|RUNPATH)\)' >/dev/null; then
  echo "error: bridge contains RPATH/RUNPATH" >&2
  exit 1
fi

echo "HAP verification passed: $ARKSCALE_HAP"
