#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_GO_COMMIT=2d8b23f6923100d8c90d8add9299da2c9d032a20
ARKSCALE_TAILSCALE_COMMIT=e4d64c6faf827a308ec20b39651225178e6743c0

fetch_pinned() {
  ARKSCALE_DEP_NAME=$1
  ARKSCALE_DEP_URL=$2
  ARKSCALE_DEP_COMMIT=$3
  ARKSCALE_DEP_DIR=$4
  ARKSCALE_DEP_REF=${5:-}

  if [ -e "$ARKSCALE_DEP_DIR" ] && [ ! -d "$ARKSCALE_DEP_DIR/.git" ]; then
    echo "error: $ARKSCALE_DEP_DIR exists but is not a Git checkout" >&2
    exit 1
  fi

  if [ ! -d "$ARKSCALE_DEP_DIR/.git" ]; then
    if [ -n "$ARKSCALE_DEP_REF" ]; then
      git clone --depth 1 --single-branch --branch "$ARKSCALE_DEP_REF" \
        "$ARKSCALE_DEP_URL" "$ARKSCALE_DEP_DIR"
    else
      git clone "$ARKSCALE_DEP_URL" "$ARKSCALE_DEP_DIR"
    fi
  fi

  ARKSCALE_ACTUAL_COMMIT=$(git -C "$ARKSCALE_DEP_DIR" rev-parse HEAD)
  if [ "$ARKSCALE_ACTUAL_COMMIT" != "$ARKSCALE_DEP_COMMIT" ]; then
    if [ -n "$(git -C "$ARKSCALE_DEP_DIR" status --porcelain)" ]; then
      echo "error: $ARKSCALE_DEP_NAME checkout has local changes; refusing to switch commits" >&2
      exit 1
    fi
    git -C "$ARKSCALE_DEP_DIR" fetch origin "$ARKSCALE_DEP_COMMIT"
    git -C "$ARKSCALE_DEP_DIR" checkout --detach "$ARKSCALE_DEP_COMMIT"
  fi

  ARKSCALE_ACTUAL_COMMIT=$(git -C "$ARKSCALE_DEP_DIR" rev-parse HEAD)
  if [ "$ARKSCALE_ACTUAL_COMMIT" != "$ARKSCALE_DEP_COMMIT" ]; then
    echo "error: $ARKSCALE_DEP_NAME expected $ARKSCALE_DEP_COMMIT, got $ARKSCALE_ACTUAL_COMMIT" >&2
    exit 1
  fi
  echo "$ARKSCALE_DEP_NAME: $ARKSCALE_ACTUAL_COMMIT"
}

mkdir -p "$ARKSCALE_ROOT/third_party"
fetch_pinned \
  "OpenHarmony-SIG Go" \
  "https://gitcode.com/openharmony-sig/ohos_golang_go.git" \
  "$ARKSCALE_GO_COMMIT" \
  "$ARKSCALE_ROOT/third_party/ohos_golang_go"
fetch_pinned \
  "Tailscale" \
  "https://github.com/tailscale/tailscale.git" \
  "$ARKSCALE_TAILSCALE_COMMIT" \
  "$ARKSCALE_ROOT/third_party/tailscale" \
  "v1.82.5"
