#!/bin/sh
set -eu

contains_secret() {
  grep -Eq 'tskey-(auth|client|api)-[[:alnum:]_-]{10,}|https://login\.tailscale\.com/a/[[:alnum:]_-]{8,}|-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----'
}

if [ "${1:-}" = "--self-test" ]; then
  for ARKSCALE_SECRET in 'tskey-auth-''k1234567890' 'https://login.tailscale.com/a/''12345678' '-----BEGIN ''PRIVATE KEY-----'; do
    printf '%s\n' "$ARKSCALE_SECRET" | contains_secret
  done
  if printf '%s\n' 'tskey-auth-...' | contains_secret; then
    exit 1
  fi
  echo "Staged secret pattern self-test passed"
  exit 0
fi

if ! git diff --cached --quiet --diff-filter=ACMR -- \
  ':(glob)**/.env' \
  ':(glob)**/.env.*' \
  ':(glob)**/*.p12' \
  ':(glob)**/*.p7b' \
  ':(glob)**/*.cer' \
  ':(glob)**/*.profile' \
  ':(exclude,glob)**/.env.example'
then
  echo "error: staged environment or signing material" >&2
  exit 1
fi

ARKSCALE_SIGNING_ADDITIONS=$(git diff --cached --unified=0 -- build-profile.json5 | sed -n '/^+[^+]/p')
if printf '%s\n' "$ARKSCALE_SIGNING_ADDITIONS" | grep -Eq '"(keyPassword|storePassword)"'; then
  echo "error: staged signing credentials in build-profile.json5" >&2
  exit 1
fi

ARKSCALE_ADDITIONS=$(git diff --cached --unified=0 -- . | sed -n '/^+[^+]/p')
if printf '%s\n' "$ARKSCALE_ADDITIONS" | contains_secret; then
  echo "error: staged Tailscale credential, reusable login URL, or private key" >&2
  exit 1
fi

echo "Staged secret check passed"
