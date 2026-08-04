#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
: "${ARKSCALE_LINUX_SDK:?set ARKSCALE_LINUX_SDK to the extracted Linux OHOS SDK directory}"
ARKSCALE_P0_IMAGE=${ARKSCALE_P0_IMAGE:-arkscale-p0:go1.24.5}

if [ ! -x "$ARKSCALE_LINUX_SDK/native/llvm/bin/clang" ]; then
  echo "error: expected $ARKSCALE_LINUX_SDK/native/llvm/bin/clang" >&2
  exit 1
fi
ARKSCALE_CLANG_TYPE=$(file "$ARKSCALE_LINUX_SDK/native/llvm/bin/clang")
if ! echo "$ARKSCALE_CLANG_TYPE" | grep -Eq 'ELF 64-bit.*x86-64'; then
  echo "error: P0 requires the Linux x86_64 OHOS SDK; got: $ARKSCALE_CLANG_TYPE" >&2
  exit 1
fi

if ! docker image inspect "$ARKSCALE_P0_IMAGE" >/dev/null 2>&1; then
  docker build \
    --platform linux/amd64 \
    --file "$ARKSCALE_ROOT/docker/p0.Dockerfile" \
    --tag "$ARKSCALE_P0_IMAGE" \
    "$ARKSCALE_ROOT/docker"
fi

docker run \
  --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --env "GOPROXY=${GOPROXY:-https://goproxy.cn,direct}" \
  --volume "$ARKSCALE_ROOT:/workspace" \
  --volume "$ARKSCALE_LINUX_SDK:/opt/ohos-sdk/linux:ro" \
  "$ARKSCALE_P0_IMAGE"
