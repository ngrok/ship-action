#!/usr/bin/env bash
# Reports the pushed image to ship. Ship creates releases from reported
# images only, so the step fails if ship does not record it.
#
# Inputs (environment):
#   NGROK_APP_ID          the ship app the image is for
#   NGROK_API_URL         ship base URL
#   NGROK_COMMIT_SHA      the commit the image is built from
#   NGROK_IMAGE           the pushed image reference
#   NGROK_ACTION_VERSION  this action's version
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

oidc_token=$(oidc_token)

request=$(jq -cn --arg app_id "$NGROK_APP_ID" --arg version "$NGROK_ACTION_VERSION" \
	--arg sha "$NGROK_COMMIT_SHA" --arg image "$NGROK_IMAGE" \
	'{app_id: $app_id, action_version: $version, commit_sha: $sha, image: $image}')
body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

# The report is idempotent, so a retry after a lost response is safe.
status=$(curl --silent --show-error --retry 3 --retry-connrefused --retry-all-errors \
	-o "$body_file" -w '%{http_code}' \
	-X POST "${NGROK_API_URL%/}/v1/github-actions/image" \
	-H "Authorization: Bearer ${oidc_token}" \
	-H "Content-Type: application/json" \
	--data "$request") ||
	fail "could not reach ngrok ship at ${NGROK_API_URL}"

if [[ "$status" != "204" ]]; then
	message=$(jq -r '.error // empty' "$body_file" 2>/dev/null || true)
	fail "ngrok ship refused the image report (HTTP ${status})${message:+: ${message}}"
fi
echo "reported ${NGROK_IMAGE} to ngrok ship"
