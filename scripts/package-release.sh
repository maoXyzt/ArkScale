#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_HAP=${1:-$ARKSCALE_ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap}
ARKSCALE_OUT=${2:-$ARKSCALE_ROOT/dist/arkscale-release}
case "$ARKSCALE_OUT" in
  "$ARKSCALE_ROOT"/*) ;;
  *) echo "error: output directory must be under the repository root" >&2; exit 1 ;;
esac

if [ ! -f "$ARKSCALE_HAP" ]; then
  echo "error: HAP not found: $ARKSCALE_HAP" >&2
  echo "hint: run pnpm run build:p1 first" >&2
  exit 1
fi
case "$ARKSCALE_HAP" in *.hap) ;; *) echo "error: expected a .hap file" >&2; exit 1 ;; esac
"$ARKSCALE_ROOT/scripts/validate-hap.sh" "$ARKSCALE_HAP"
ARKSCALE_HAP=$(CDPATH='' cd -- "$(dirname -- "$ARKSCALE_HAP")" && pwd)/$(basename -- "$ARKSCALE_HAP")
ARKSCALE_DEFAULT_HAP="$ARKSCALE_ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"
if [ "$ARKSCALE_HAP" != "$ARKSCALE_DEFAULT_HAP" ]; then
  echo "error: HAP must be the current checkout's standard unsigned build output" >&2
  exit 1
fi

ARKSCALE_VERSION=$(sed -n "s/.*[\"']*versionName[\"']*[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$ARKSCALE_ROOT/AppScope/app.json5" | head -1)
ARKSCALE_CODE=$(sed -n "s/.*[\"']*versionCode[\"']*[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$ARKSCALE_ROOT/AppScope/app.json5" | head -1)
ARKSCALE_PACK=$(unzip -p "$ARKSCALE_HAP" pack.info)
ARKSCALE_PACK_VERSION=$(printf '%s' "$ARKSCALE_PACK" | node -e 'process.stdin.setEncoding("utf8"); let s=""; process.stdin.on("data", d => s += d); process.stdin.on("end", () => { const p=JSON.parse(s); process.stdout.write(String(p.summary.app.version.name)); });')
ARKSCALE_PACK_CODE=$(printf '%s' "$ARKSCALE_PACK" | node -e 'process.stdin.setEncoding("utf8"); let s=""; process.stdin.on("data", d => s += d); process.stdin.on("end", () => { const p=JSON.parse(s); process.stdout.write(String(p.summary.app.version.code)); });')
if [ "${ARKSCALE_VERSION:-}" != "$ARKSCALE_PACK_VERSION" ] || [ "${ARKSCALE_CODE:-}" != "$ARKSCALE_PACK_CODE" ]; then
  echo "error: HAP version metadata does not match AppScope/app.json5; rebuild the HAP" >&2
  exit 1
fi
ARKSCALE_PARENT=$(dirname -- "$ARKSCALE_OUT")
mkdir -p "$ARKSCALE_PARENT"
ARKSCALE_STAGE=$(mktemp -d "$ARKSCALE_PARENT/.arkscale-release.XXXXXX")
trap 'rm -rf "$ARKSCALE_STAGE"' EXIT HUP INT TERM
ARKSCALE_NAME="arkscale-${ARKSCALE_VERSION:-unknown}-unsigned.hap"
cp "$ARKSCALE_HAP" "$ARKSCALE_STAGE/$ARKSCALE_NAME"
cp "$ARKSCALE_ROOT/scripts/install-hap.sh" "$ARKSCALE_STAGE/install-hap.sh"
if command -v shasum >/dev/null 2>&1; then
  (cd "$ARKSCALE_STAGE" && shasum -a 256 "$ARKSCALE_NAME") > "$ARKSCALE_STAGE/SHA256SUMS"
else
  (cd "$ARKSCALE_STAGE" && sha256sum "$ARKSCALE_NAME") > "$ARKSCALE_STAGE/SHA256SUMS"
fi

ARKSCALE_COMMIT=$(git -C "$ARKSCALE_ROOT" rev-parse HEAD)
cat > "$ARKSCALE_STAGE/manifest.txt" <<EOF
ArkScale version: ${ARKSCALE_VERSION:-unknown} (${ARKSCALE_CODE:-unknown})
Commit: $ARKSCALE_COMMIT
Package: com.arkscale.client
Minimum compatible API: 22
Target API: 24
ABI: arm64-v8a
Artifact: $ARKSCALE_NAME
EOF

if [ -d "$ARKSCALE_ROOT/build/compliance" ]; then
  cp -R "$ARKSCALE_ROOT/build/compliance" "$ARKSCALE_STAGE/compliance"
fi
if [ -e "$ARKSCALE_OUT" ]; then rm -rf "$ARKSCALE_OUT"; fi
mv "$ARKSCALE_STAGE" "$ARKSCALE_OUT"
trap - EXIT HUP INT TERM
echo "Release bundle written to $ARKSCALE_OUT"
