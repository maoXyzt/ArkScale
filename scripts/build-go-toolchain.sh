#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_GO_ROOT=${ARKSCALE_GO_ROOT:-$ARKSCALE_ROOT/third_party/ohos_golang_go}
ARKSCALE_GO_BOOTSTRAP=${ARKSCALE_GO_BOOTSTRAP:-/usr/local/go}
ARKSCALE_GO_COMMIT=2d8b23f6923100d8c90d8add9299da2c9d032a20

if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
  echo "error: the pinned SIG Go toolchain must be built on linux/amd64" >&2
  exit 1
fi
if [ "$(git -C "$ARKSCALE_GO_ROOT" rev-parse HEAD)" != "$ARKSCALE_GO_COMMIT" ]; then
  echo "error: OpenHarmony-SIG Go checkout is not at $ARKSCALE_GO_COMMIT" >&2
  exit 1
fi
if [ ! -x "$ARKSCALE_GO_BOOTSTRAP/bin/go" ]; then
  echo "error: Go bootstrap not found at $ARKSCALE_GO_BOOTSTRAP/bin/go" >&2
  exit 1
fi

if [ ! -x "$ARKSCALE_GO_ROOT/bin/go" ]; then
  cd "$ARKSCALE_GO_ROOT/src"
  GOROOT_BOOTSTRAP="$ARKSCALE_GO_BOOTSTRAP" ./make.bash
fi

"$ARKSCALE_GO_ROOT/bin/go" version
