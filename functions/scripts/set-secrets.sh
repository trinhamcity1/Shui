#!/usr/bin/env bash
# Pushes app secrets (R2 credentials, the AI tutor's model API key) to
# Firebase Functions secrets (Google Secret Manager) from a local, gitignored
# env file — so you don't copy-paste values into the CLI by hand every time
# they rotate. See ../.secrets.local.env.example.
#
# Usage:
#   cp functions/.secrets.local.env.example functions/.secrets.local.env
#   # fill in real values in that new file
#   cd functions && npm run secrets:push
#
# Only pushes the fixed set of names below, even if the env file has other
# lines in it — a typo'd extra line in that file should never silently
# become a new secret.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$FUNCTIONS_DIR/.secrets.local.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE." >&2
  echo "Run: cp functions/.secrets.local.env.example functions/.secrets.local.env" >&2
  echo "Then fill in real values before running this again." >&2
  exit 1
fi

SECRET_NAMES=(R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_BASE_URL AI_API_KEY)

for name in "${SECRET_NAMES[@]}"; do
  value="$(grep -E "^${name}=" "$ENV_FILE" | head -n1 | cut -d '=' -f2- | tr -d '\r')"
  if [ -z "$value" ]; then
    echo "Skipping ${name} - empty or missing in $ENV_FILE." >&2
    continue
  fi
  echo "Setting ${name}..."
  printf '%s' "$value" | firebase functions:secrets:set "$name" --data-file=- --force
done

echo ""
echo "Done. Functions already deployed need a redeploy to pick up new values:"
echo "  firebase deploy --only functions"
