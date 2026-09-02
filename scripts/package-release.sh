#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_HAP=${1:-$ARKSCALE_ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap}
ARKSCALE_OUT=${2:-$ARKSCALE_ROOT/dist/arkscale-release}

if [ ! -f "$ARKSCALE_HAP" ]; then
  echo "error: HAP not found: $ARKSCALE_HAP" >&2
  echo "hint: run pnpm run build:p1 first" >&2
  exit 1
fi
case "$ARKSCALE_HAP" in *.hap) ;; *) echo "error: expected a .hap file" >&2; exit 1 ;; esac

mkdir -p "$ARKSCALE_OUT"
ARKSCALE_VERSION=$(sed -n 's/.*"versionName": "\([^"]*\)".*/\1/p' "$ARKSCALE_ROOT/AppScope/app.json5" | head -1)
ARKSCALE_NAME="arkscale-${ARKSCALE_VERSION:-unknown}-unsigned.hap"
cp "$ARKSCALE_HAP" "$ARKSCALE_OUT/$ARKSCALE_NAME"
cp "$ARKSCALE_ROOT/scripts/install-hap.sh" "$ARKSCALE_OUT/install-hap.sh"
if command -v shasum >/dev/null 2>&1; then
  (cd "$ARKSCALE_OUT" && shasum -a 256 "$ARKSCALE_NAME") > "$ARKSCALE_OUT/SHA256SUMS"
else
  (cd "$ARKSCALE_OUT" && sha256sum "$ARKSCALE_NAME") > "$ARKSCALE_OUT/SHA256SUMS"
fi

ARKSCALE_COMMIT=$(git -C "$ARKSCALE_ROOT" rev-parse HEAD)
ARKSCALE_CODE=$(sed -n 's/.*"versionCode": \([0-9][0-9]*\).*/\1/p' "$ARKSCALE_ROOT/AppScope/app.json5" | head -1)
cat > "$ARKSCALE_OUT/manifest.txt" <<EOF
ArkScale version: ${ARKSCALE_VERSION:-unknown} (${ARKSCALE_CODE:-unknown})
Commit: $ARKSCALE_COMMIT
Package: com.arkscale.client
Minimum compatible API: 22
Target API: 24
ABI: arm64-v8a
Artifact: $ARKSCALE_NAME
EOF

if [ -d "$ARKSCALE_ROOT/build/compliance" ]; then
  cp -R "$ARKSCALE_ROOT/build/compliance" "$ARKSCALE_OUT/compliance"
fi
echo "Release bundle written to $ARKSCALE_OUT"
