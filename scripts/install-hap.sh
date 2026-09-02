#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 /path/to/signed-arkscale.hap [connect-key]" >&2
  exit 2
fi
ARKSCALE_HAP=$1
ARKSCALE_TARGET=${2:-}
if [ ! -f "$ARKSCALE_HAP" ]; then echo "error: HAP not found: $ARKSCALE_HAP" >&2; exit 1; fi
case "$ARKSCALE_HAP" in *.hap) ;; *) echo "error: expected a .hap file" >&2; exit 1 ;; esac
if ! command -v hdc >/dev/null 2>&1; then
  echo "error: hdc is required; install the HarmonyOS device command-line tools" >&2
  exit 1
fi
ARKSCALE_TARGETS=$(hdc list targets)
if [ -z "$ARKSCALE_TARGETS" ] || printf '%s\n' "$ARKSCALE_TARGETS" | grep -Eq '^\[Empty\]$|No devices|Connect server failed'; then
  echo "error: no HDC device detected; enable developer mode and USB debugging" >&2
  exit 1
fi
if [ -n "$ARKSCALE_TARGET" ]; then
  hdc -t "$ARKSCALE_TARGET" install -r "$ARKSCALE_HAP"
else
  hdc install -r "$ARKSCALE_HAP"
fi
echo "ArkScale installed. Launch it on the device and grant VPN permission."
