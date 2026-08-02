#!/bin/sh
set -eu

ARKSCALE_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
ARKSCALE_DEVECO_HOME=${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app}
ARKSCALE_HVIGOR_ROOT="$ARKSCALE_DEVECO_HOME/Contents/tools/hvigor"

ARKSCALE_NODE_BIN=$(command -v node)
ARKSCALE_PNPM_BIN=$(command -v pnpm)
if [ "$(dirname -- "$ARKSCALE_NODE_BIN")" != "$(dirname -- "$ARKSCALE_PNPM_BIN")" ]; then
  echo "error: node and pnpm must come from the same active fnm environment" >&2
  exit 1
fi

mkdir -p "$ARKSCALE_ROOT/node_modules/@ohos"
if [ ! -e "$ARKSCALE_ROOT/node_modules/@ohos/hvigor" ]; then
  ln -s "$ARKSCALE_HVIGOR_ROOT/hvigor" "$ARKSCALE_ROOT/node_modules/@ohos/hvigor"
fi
if [ ! -e "$ARKSCALE_ROOT/node_modules/@ohos/hvigor-ohos-plugin" ]; then
  ln -s "$ARKSCALE_HVIGOR_ROOT/hvigor-ohos-plugin" "$ARKSCALE_ROOT/node_modules/@ohos/hvigor-ohos-plugin"
fi

export NODE_PATH="$ARKSCALE_ROOT/node_modules${NODE_PATH:+:$NODE_PATH}"
export HVIGOR_USER_HOME="$ARKSCALE_ROOT/.cache/hvigor"
export DEVECO_SDK_HOME="$ARKSCALE_DEVECO_HOME/Contents/sdk"
export JAVA_HOME="$ARKSCALE_DEVECO_HOME/Contents/jbr/Contents/Home"

exec "$ARKSCALE_NODE_BIN" "$ARKSCALE_HVIGOR_ROOT/hvigor/bin/hvigor.js" \
  assembleHap \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  --no-daemon \
  "$@"
