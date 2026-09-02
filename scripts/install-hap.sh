#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/signed-arkscale.hap" >&2
  exit 2
fi
ARKSCALE_HAP=$1
if [ ! -f "$ARKSCALE_HAP" ]; then echo "error: HAP not found: $ARKSCALE_HAP" >&2; exit 1; fi
case "$ARKSCALE_HAP" in *.hap) ;; *) echo "error: expected a .hap file" >&2; exit 1 ;; esac
if ! command -v hdc >/dev/null 2>&1; then
  echo "error: hdc is required; install the HarmonyOS device command-line tools" >&2
  exit 1
fi
ARKSCALE_TARGETS=$(hdc list targets)
if [ -z "$ARKSCALE_TARGETS" ] || printf '%s\n' "$ARKSCALE_TARGETS" | grep -Eq 'No devices|Connect server failed'; then
  echo "error: no HDC device detected; enable developer mode and USB debugging" >&2
  exit 1
fi
hdc install -r "$ARKSCALE_HAP"
echo "ArkScale installed. Launch it on the device and grant VPN permission."
