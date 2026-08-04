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

apply_dependency_patch() {
  ARKSCALE_DEP_NAME=$1
  ARKSCALE_DEP_DIR=$2
  ARKSCALE_PATCH=$3

  if git -C "$ARKSCALE_DEP_DIR" apply --unidiff-zero --reverse --check "$ARKSCALE_PATCH" >/dev/null 2>&1; then
    echo "$ARKSCALE_DEP_NAME patch already applied: $(basename "$ARKSCALE_PATCH")"
  elif git -C "$ARKSCALE_DEP_DIR" apply --unidiff-zero --check "$ARKSCALE_PATCH"; then
    git -C "$ARKSCALE_DEP_DIR" apply --unidiff-zero "$ARKSCALE_PATCH"
    echo "$ARKSCALE_DEP_NAME patch applied: $(basename "$ARKSCALE_PATCH")"
  else
    echo "error: cannot apply $ARKSCALE_PATCH cleanly" >&2
    exit 1
  fi
}

verify_patched_checkout() {
  ARKSCALE_DEP_NAME=$1
  ARKSCALE_DEP_DIR=$2
  ARKSCALE_EXPECTED_DIFF_HASH=$3

  if [ -n "$(git -C "$ARKSCALE_DEP_DIR" ls-files --others --exclude-standard)" ]; then
    echo "error: $ARKSCALE_DEP_NAME checkout contains untracked source files" >&2
    exit 1
  fi
  ARKSCALE_ACTUAL_DIFF_HASH=$(git -C "$ARKSCALE_DEP_DIR" diff --no-ext-diff --binary | \
    git -C "$ARKSCALE_DEP_DIR" hash-object --stdin)
  if [ "$ARKSCALE_ACTUAL_DIFF_HASH" != "$ARKSCALE_EXPECTED_DIFF_HASH" ]; then
    echo "error: $ARKSCALE_DEP_NAME checkout differs from its registered patch" >&2
    exit 1
  fi
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
apply_dependency_patch \
  "OpenHarmony-SIG Go" \
  "$ARKSCALE_ROOT/third_party/ohos_golang_go" \
  "$ARKSCALE_ROOT/patches/ohos-go/0001-net-close-interface-resources.patch"
apply_dependency_patch \
  "Tailscale" \
  "$ARKSCALE_ROOT/third_party/tailscale" \
  "$ARKSCALE_ROOT/patches/tailscale/0001-openharmony-platform-seams.patch"
verify_patched_checkout \
  "OpenHarmony-SIG Go" \
  "$ARKSCALE_ROOT/third_party/ohos_golang_go" \
  "3948531a9f1e01e6b4682ce4dc75feacb4c0ac61"
verify_patched_checkout \
  "Tailscale" \
  "$ARKSCALE_ROOT/third_party/tailscale" \
  "aac4b322dce98b7018ceb62a1a5fc6fe9b2040b5"
