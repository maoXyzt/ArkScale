#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/arkscale.hap" >&2
  exit 2
fi
ARKSCALE_HAP=$1
[ -f "$ARKSCALE_HAP" ] || { echo "error: HAP not found: $ARKSCALE_HAP" >&2; exit 1; }
if ! command -v unzip >/dev/null 2>&1; then
  echo "error: unzip is required to validate HAP files" >&2
  exit 1
fi
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
ARKSCALE_PACK=$(unzip -p "$ARKSCALE_HAP" pack.info)
if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required to validate HAP metadata" >&2
  exit 1
fi
ARKSCALE_MODULE="$ARKSCALE_MODULE" ARKSCALE_PACK="$ARKSCALE_PACK" node <<'NODE'
const fail = (message) => { console.error(`error: ${message}`); process.exit(1); };
let moduleInfo, packInfo;
try {
  moduleInfo = JSON.parse(process.env.ARKSCALE_MODULE);
  packInfo = JSON.parse(process.env.ARKSCALE_PACK);
} catch {
  fail('HAP metadata is not valid JSON');
}
if (moduleInfo?.app?.bundleName !== 'com.arkscale.client') fail('HAP bundleName is not com.arkscale.client');
const permissions = moduleInfo?.module?.requestPermissions;
const names = Array.isArray(permissions) ? permissions.map((item) => item?.name).sort() : [];
if (names.includes('ohos.permission.MANAGE_VPN')) fail('HAP requests system-only MANAGE_VPN permission');
if (names.join('\n') !== ['ohos.permission.GET_NETWORK_INFO', 'ohos.permission.INTERNET'].join('\n')) {
  fail('HAP requestPermissions must contain exactly INTERNET and GET_NETWORK_INFO');
}
const extension = moduleInfo?.module?.extensionAbilities?.find((item) => item?.name === 'ArkScaleVpnExtension');
if (!extension) fail('HAP is missing ArkScaleVpnExtension');
if (extension.type !== 'vpn') fail('HAP ArkScaleVpnExtension type is not vpn');
const api = packInfo?.summary?.modules?.[0]?.apiVersion;
if (!Number.isInteger(api?.compatible) || api.compatible !== 22) fail('HAP compatible API level is not 22');
if (!Number.isInteger(api?.target) || api.target !== 24) fail('HAP target API level is not 24');
NODE
echo "HAP validation passed: $ARKSCALE_HAP"
