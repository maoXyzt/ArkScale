#!/bin/sh
set -eu

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

echo "Staged secret check passed"
