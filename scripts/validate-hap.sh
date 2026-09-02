#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/arkscale.hap" >&2
  exit 2
fi
ARKSCALE_HAP=$1
[ -f "$ARKSCALE_HAP" ] || { echo "error: HAP not found: $ARKSCALE_HAP" >&2; exit 1; }
if ! unzip -t "$ARKSCALE_HAP" >/dev/null; then
  echo "error: invalid or truncated HAP: $ARKSCALE_HAP" >&2
  exit 1
fi
for ARKSCALE_LIB in libarkscale_bridge.so libarkscale_smoke.so libarkscale_engine.so; do
  unzip -l "$ARKSCALE_HAP" "libs/arm64-v8a/$ARKSCALE_LIB" 2>/dev/null | grep -F "$ARKSCALE_LIB" >/dev/null || {
    echo "error: HAP is missing libs/arm64-v8a/$ARKSCALE_LIB" >&2; exit 1;
  }
done
ARKSCALE_MODULE=$(unzip -p "$ARKSCALE_HAP" module.json)
printf '%s\n' "$ARKSCALE_MODULE" | grep -Eq '"bundleName"[[:space:]]*:[[:space:]]*"com\.arkscale\.client"' || exit 1
printf '%s\n' "$ARKSCALE_MODULE" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ohos\.permission\.INTERNET"' || exit 1
printf '%s\n' "$ARKSCALE_MODULE" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ohos\.permission\.GET_NETWORK_INFO"' || exit 1
if printf '%s\n' "$ARKSCALE_MODULE" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ohos\.permission\.MANAGE_VPN"'; then
  echo "error: HAP requests system-only MANAGE_VPN permission" >&2; exit 1
fi
printf '%s\n' "$ARKSCALE_MODULE" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ArkScaleVpnExtension"' || exit 1
printf '%s\n' "$ARKSCALE_MODULE" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"vpn"' || exit 1
ARKSCALE_PACK=$(unzip -p "$ARKSCALE_HAP" pack.info)
printf '%s\n' "$ARKSCALE_PACK" | grep -Eq '"compatible"[[:space:]]*:[[:space:]]*22' || exit 1
printf '%s\n' "$ARKSCALE_PACK" | grep -Eq '"target"[[:space:]]*:[[:space:]]*24' || exit 1
echo "HAP validation passed: $ARKSCALE_HAP"
