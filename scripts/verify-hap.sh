#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_DEVECO_HOME=${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app}
ARKSCALE_UNSIGNED_HAP="$ARKSCALE_ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"
ARKSCALE_SIGNED_HAP="$ARKSCALE_ROOT/entry/build/default/outputs/default/entry-default-signed.hap"
ARKSCALE_LIB_DIR="$ARKSCALE_ROOT/entry/build/default/intermediates/stripped_native_libs/default/arm64-v8a"
ARKSCALE_BRIDGE="$ARKSCALE_LIB_DIR/libarkscale_bridge.so"
ARKSCALE_SMOKE="$ARKSCALE_LIB_DIR/libarkscale_smoke.so"
ARKSCALE_ENGINE="$ARKSCALE_LIB_DIR/libarkscale_engine.so"
ARKSCALE_READELF="$ARKSCALE_DEVECO_HOME/Contents/sdk/default/openharmony/native/llvm/bin/llvm-readelf"

if [ ! -f "$ARKSCALE_UNSIGNED_HAP" ] || [ ! -f "$ARKSCALE_BRIDGE" ] || [ ! -f "$ARKSCALE_SMOKE" ] || [ ! -f "$ARKSCALE_ENGINE" ]; then
  echo "error: run pnpm run build:p1 first" >&2
  exit 1
fi

file "$ARKSCALE_BRIDGE" | grep -E 'ELF 64-bit.*ARM aarch64' >/dev/null
file "$ARKSCALE_SMOKE" | grep -E 'ELF 64-bit.*ARM aarch64' >/dev/null
file "$ARKSCALE_ENGINE" | grep -E 'ELF 64-bit.*ARM aarch64' >/dev/null

verify_hap() {
  ARKSCALE_HAP=$1
  for ARKSCALE_LIB in libarkscale_bridge.so libarkscale_smoke.so libarkscale_engine.so; do
    if ! unzip -p "$ARKSCALE_HAP" "libs/arm64-v8a/$ARKSCALE_LIB" | cmp - "$ARKSCALE_LIB_DIR/$ARKSCALE_LIB"; then
      echo "error: $ARKSCALE_HAP contains stale $ARKSCALE_LIB" >&2
      exit 1
    fi
  done
  ARKSCALE_MODULE=$(unzip -p "$ARKSCALE_HAP" module.json)
  printf '%s\n' "$ARKSCALE_MODULE" | grep '"bundleName":"com.arkscale.client"' >/dev/null
  printf '%s\n' "$ARKSCALE_MODULE" | grep '"name":"ohos.permission.INTERNET"' >/dev/null
  printf '%s\n' "$ARKSCALE_MODULE" | grep '"name":"ohos.permission.GET_NETWORK_INFO"' >/dev/null
  if printf '%s\n' "$ARKSCALE_MODULE" | grep '"name":"ohos.permission.MANAGE_VPN"' >/dev/null; then
    echo "error: HAP requests system-only MANAGE_VPN permission" >&2
    exit 1
  fi
  printf '%s\n' "$ARKSCALE_MODULE" | grep '"name":"ArkScaleVpnExtension"' >/dev/null
  printf '%s\n' "$ARKSCALE_MODULE" | grep '"type":"vpn"' >/dev/null
  unzip -p "$ARKSCALE_HAP" pack.info | grep '"compatible":22' >/dev/null
  unzip -p "$ARKSCALE_HAP" pack.info | grep '"target":24' >/dev/null
  echo "HAP verification passed: $ARKSCALE_HAP"
}

verify_hap "$ARKSCALE_UNSIGNED_HAP"
if [ -f "$ARKSCALE_SIGNED_HAP" ]; then
  verify_hap "$ARKSCALE_SIGNED_HAP"
fi
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_BRIDGE" | grep 'RegisterArkScaleBridgeModule' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_run' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_start' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_stop' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_SMOKE" | grep 'arkscale_smoke_ticks' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_ENGINE" | grep 'arkscale_set_tun' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_ENGINE" | grep 'arkscale_clear_tun' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_ENGINE" | grep 'arkscale_probe_peer' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_ENGINE" | grep 'arkscale_logout' >/dev/null
"$ARKSCALE_READELF" --dyn-syms "$ARKSCALE_ENGINE" | grep 'arkscale_stop' >/dev/null
ARKSCALE_BRIDGE_DYNAMIC=$("$ARKSCALE_READELF" -d "$ARKSCALE_BRIDGE")
printf '%s\n' "$ARKSCALE_BRIDGE_DYNAMIC" | grep 'Shared library: \[libarkscale_smoke.so\]' >/dev/null
printf '%s\n' "$ARKSCALE_BRIDGE_DYNAMIC" | grep 'Shared library: \[libarkscale_engine.so\]' >/dev/null
if printf '%s\n' "$ARKSCALE_BRIDGE_DYNAMIC" | grep -E '\((RPATH|RUNPATH)\)' >/dev/null; then
  echo "error: bridge contains RPATH/RUNPATH" >&2
  exit 1
fi
