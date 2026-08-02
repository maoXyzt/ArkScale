#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${ARKSCALE_LINUX_SDK:?set ARKSCALE_LINUX_SDK to the extracted Linux OHOS SDK directory}"
ARKSCALE_P0_IMAGE=${ARKSCALE_P0_IMAGE:-arkscale-p0:go1.24.5}

docker run \
  --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --env "GOMAXPROCS=${GOMAXPROCS:-1}" \
  --env "GOPROXY=${GOPROXY:-https://goproxy.cn,direct}" \
  --volume "$ARKSCALE_ROOT:/workspace" \
  --volume "$ARKSCALE_LINUX_SDK:/opt/ohos-sdk/linux:ro" \
  "$ARKSCALE_P0_IMAGE" \
  ./scripts/build-smoke.sh

"$ARKSCALE_ROOT/scripts/build-hap.sh"
"$ARKSCALE_ROOT/scripts/verify-hap.sh"
