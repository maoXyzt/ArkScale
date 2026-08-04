#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_GO=${ARKSCALE_GO:-$ARKSCALE_ROOT/third_party/ohos_golang_go/bin/go}
: "${ARKSCALE_OHOS_NATIVE:?set ARKSCALE_OHOS_NATIVE to the Linux OHOS native SDK directory}"
export GOCACHE="${GOCACHE:-$ARKSCALE_ROOT/.cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-$ARKSCALE_ROOT/.cache/go-mod}"
export GOPATH="${GOPATH:-$ARKSCALE_ROOT/.cache/gopath}"
export GOENV=off
ARKSCALE_OUTPUT="$ARKSCALE_ROOT/build/compliance"
ARKSCALE_LICENSE_REGISTRY="$ARKSCALE_ROOT/compliance/go-modules.tsv"
mkdir -p "$ARKSCALE_ROOT/build"
ARKSCALE_TMP=$(mktemp -d "$ARKSCALE_ROOT/build/compliance.XXXXXX")
trap 'rm -rf "$ARKSCALE_TMP"' EXIT HUP INT TERM

if [ ! -x "$ARKSCALE_GO" ]; then
  echo "error: Go tool not found: $ARKSCALE_GO" >&2
  exit 1
fi

mkdir -p "$ARKSCALE_TMP/licenses"
ARKSCALE_COMMIT=$(git -C "$ARKSCALE_ROOT" rev-parse HEAD)
ARKSCALE_VERSION=$ARKSCALE_COMMIT
if [ -n "$(git -C "$ARKSCALE_ROOT" status --porcelain --untracked-files=normal -- . ':(exclude)build-profile.json5')" ]; then
  ARKSCALE_VERSION="$ARKSCALE_COMMIT-dirty"
fi
ARKSCALE_CREATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
ARKSCALE_SPDX="$ARKSCALE_TMP/arkscale-engine.spdx"
ARKSCALE_MANIFEST="$ARKSCALE_TMP/licenses/manifest.tsv"
ARKSCALE_MISSING="$ARKSCALE_TMP/licenses/missing.tsv"
ARKSCALE_MODULES="$ARKSCALE_TMP/modules.tsv"
ARKSCALE_MODULES_RAW="$ARKSCALE_TMP/modules.raw"

printf '%s\n' \
  'SPDXVersion: SPDX-2.3' \
  'DataLicense: CC0-1.0' \
  'SPDXID: SPDXRef-DOCUMENT' \
  'DocumentName: ArkScale-engine' \
  "DocumentNamespace: https://arkscale.invalid/spdx/$ARKSCALE_VERSION/$ARKSCALE_CREATED" \
  'Creator: Tool: ArkScale generate-compliance.sh' \
  "Created: $ARKSCALE_CREATED" \
  '' \
  'PackageName: ArkScale' \
  'SPDXID: SPDXRef-ArkScale' \
  "PackageVersion: $ARKSCALE_VERSION" \
  'PackageDownloadLocation: NOASSERTION' \
  'FilesAnalyzed: false' \
  'PackageLicenseConcluded: MIT' \
  'PackageLicenseDeclared: MIT' \
  'PackageCopyrightText: Copyright (c) 2026 ArkScale contributors' \
  'Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-ArkScale' \
  '' \
  'PackageName: OpenHarmony-SIG Go' \
  'SPDXID: SPDXRef-OpenHarmony-SIG-Go' \
  'PackageVersion: 2d8b23f6923100d8c90d8add9299da2c9d032a20' \
  'PackageDownloadLocation: https://gitcode.com/openharmony-sig/ohos_golang_go' \
  'FilesAnalyzed: false' \
  'PackageLicenseConcluded: BSD-3-Clause' \
  'PackageLicenseDeclared: BSD-3-Clause' \
  'PackageCopyrightText: NOASSERTION' \
  'Relationship: SPDXRef-OpenHarmony-SIG-Go BUILD_TOOL_OF SPDXRef-ArkScale' \
  '' > "$ARKSCALE_SPDX"

printf '%s\t%s\t%s\t%s\n' \
  'ArkScale' \
  "$ARKSCALE_VERSION" \
  'license' \
  'ArkScale-LICENSE' > "$ARKSCALE_MANIFEST"
cp "$ARKSCALE_ROOT/LICENSE" "$ARKSCALE_TMP/licenses/ArkScale-LICENSE"
cp "$ARKSCALE_ROOT/third_party/ohos_golang_go/LICENSE" \
  "$ARKSCALE_TMP/licenses/OpenHarmony-SIG-Go-LICENSE"
cp "$ARKSCALE_ROOT/third_party/ohos_golang_go/PATENTS" \
  "$ARKSCALE_TMP/licenses/OpenHarmony-SIG-Go-PATENTS"
printf '%s\t%s\t%s\t%s\n' \
  'OpenHarmony-SIG Go' \
  '2d8b23f6923100d8c90d8add9299da2c9d032a20' \
  'license' \
  'OpenHarmony-SIG-Go-LICENSE' >> "$ARKSCALE_MANIFEST"
printf '%s\t%s\t%s\t%s\n' \
  'OpenHarmony-SIG Go' \
  '2d8b23f6923100d8c90d8add9299da2c9d032a20' \
  'patents' \
  'OpenHarmony-SIG-Go-PATENTS' >> "$ARKSCALE_MANIFEST"

(cd "$ARKSCALE_ROOT/engine" && env \
  GOTOOLCHAIN=local \
  GOOS=openharmony \
  GOARCH=arm64 \
  CGO_ENABLED=1 \
  CC="$ARKSCALE_ROOT/scripts/ohos-clang" \
  CXX="$ARKSCALE_ROOT/scripts/ohos-clang++" \
  AR="$ARKSCALE_OHOS_NATIVE/llvm/bin/llvm-ar" \
  "$ARKSCALE_GO" list -mod=readonly -deps \
    -f '{{with .Module}}{{if not .Main}}{{.Path}}|{{.Version}}|{{if .Replace}}{{.Replace.Dir}}{{else}}{{.Dir}}{{end}}{{end}}{{end}}' \
    ./cmd/arkscale) > "$ARKSCALE_MODULES_RAW"
sort -u "$ARKSCALE_MODULES_RAW" > "$ARKSCALE_MODULES"

while IFS='|' read -r ARKSCALE_MODULE ARKSCALE_VERSION ARKSCALE_DIRECTORY; do
  [ -n "$ARKSCALE_MODULE" ] || continue
  ARKSCALE_ID=$(printf '%s' "$ARKSCALE_MODULE" | tr -c 'A-Za-z0-9.-' '-')
  if [ "$ARKSCALE_MODULE" = 'tailscale.com' ]; then
    ARKSCALE_VERSION='e4d64c6faf827a308ec20b39651225178e6743c0'
  fi
  if ! ARKSCALE_LICENSE_ID=$(awk -F '\t' -v module="$ARKSCALE_MODULE" -v version="$ARKSCALE_VERSION" '
    $1 == module && $2 == version { print $3; found++ }
    END { if (found != 1) exit 1 }
  ' "$ARKSCALE_LICENSE_REGISTRY"); then
    printf '%s\t%s\t%s\n' "$ARKSCALE_MODULE" "$ARKSCALE_VERSION" 'registry' >> "$ARKSCALE_MISSING"
    ARKSCALE_LICENSE_ID=NOASSERTION
  fi
  printf '%s\n' \
    "PackageName: $ARKSCALE_MODULE" \
    "SPDXID: SPDXRef-$ARKSCALE_ID" \
    "PackageVersion: ${ARKSCALE_VERSION:-NOASSERTION}" \
    'PackageDownloadLocation: NOASSERTION' \
    'FilesAnalyzed: false' \
    "PackageLicenseConcluded: $ARKSCALE_LICENSE_ID" \
    "PackageLicenseDeclared: $ARKSCALE_LICENSE_ID" \
    'PackageCopyrightText: NOASSERTION' \
    "Relationship: SPDXRef-ArkScale DEPENDS_ON SPDXRef-$ARKSCALE_ID" \
    '' >> "$ARKSCALE_SPDX"

  ARKSCALE_LICENSE_FOUND=false
  for ARKSCALE_LICENSE in \
    "$ARKSCALE_DIRECTORY"/LICENSE* \
    "$ARKSCALE_DIRECTORY"/COPYING*
  do
    [ -f "$ARKSCALE_LICENSE" ] || continue
    ARKSCALE_LICENSE_FOUND=true
    ARKSCALE_LICENSE_NAME="$ARKSCALE_ID-$(basename -- "$ARKSCALE_LICENSE")"
    cp "$ARKSCALE_LICENSE" "$ARKSCALE_TMP/licenses/$ARKSCALE_LICENSE_NAME"
    printf '%s\t%s\t%s\t%s\n' \
      "$ARKSCALE_MODULE" \
      "${ARKSCALE_VERSION:-NOASSERTION}" \
      'license' \
      "$ARKSCALE_LICENSE_NAME" >> "$ARKSCALE_MANIFEST"
  done
  for ARKSCALE_NOTICE in \
    "$ARKSCALE_DIRECTORY"/NOTICE* \
    "$ARKSCALE_DIRECTORY"/PATENTS*
  do
    [ -f "$ARKSCALE_NOTICE" ] || continue
    ARKSCALE_NOTICE_NAME="$ARKSCALE_ID-$(basename -- "$ARKSCALE_NOTICE")"
    ARKSCALE_NOTICE_KIND=notice
    case "$(basename -- "$ARKSCALE_NOTICE")" in
      PATENTS*) ARKSCALE_NOTICE_KIND=patents ;;
    esac
    cp "$ARKSCALE_NOTICE" "$ARKSCALE_TMP/licenses/$ARKSCALE_NOTICE_NAME"
    printf '%s\t%s\t%s\t%s\n' \
      "$ARKSCALE_MODULE" \
      "${ARKSCALE_VERSION:-NOASSERTION}" \
      "$ARKSCALE_NOTICE_KIND" \
      "$ARKSCALE_NOTICE_NAME" >> "$ARKSCALE_MANIFEST"
  done
  if [ "$ARKSCALE_LICENSE_FOUND" = false ]; then
    printf '%s\t%s\n' "$ARKSCALE_MODULE" "${ARKSCALE_VERSION:-NOASSERTION}" >> "$ARKSCALE_MISSING"
  fi
done < "$ARKSCALE_MODULES"

ARKSCALE_REGISTRY_COUNT=$(sed '/^#/d; /^[[:space:]]*$/d' "$ARKSCALE_LICENSE_REGISTRY" | wc -l | tr -d ' ')
ARKSCALE_MODULE_COUNT=$(grep -c '^[^|]' "$ARKSCALE_MODULES")
if [ "$ARKSCALE_REGISTRY_COUNT" != "$ARKSCALE_MODULE_COUNT" ]; then
  printf '%s\t%s\t%s\n' "$ARKSCALE_REGISTRY_COUNT" "$ARKSCALE_MODULE_COUNT" 'registry-count' >> "$ARKSCALE_MISSING"
fi

if [ -s "$ARKSCALE_MISSING" ]; then
  echo "error: module license files missing:" >&2
  cat "$ARKSCALE_MISSING" >&2
  exit 1
fi
rm -f "$ARKSCALE_MISSING"
rm -rf "$ARKSCALE_OUTPUT"
mv "$ARKSCALE_TMP" "$ARKSCALE_OUTPUT"
trap - EXIT HUP INT TERM
echo "Compliance bundle generated: $ARKSCALE_OUTPUT"
