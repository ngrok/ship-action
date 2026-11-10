#!/usr/bin/env bash
# Fetches the app's build config from ship and writes it as step outputs.
#
# Inputs (environment):
#   NGROK_APP_ID          the ship app to build
#   NGROK_API_URL         ship base URL
#   NGROK_CONTEXT         optional build root override
#   NGROK_COMMIT_SHA      the commit the image is built from
#   NGROK_ACTION_VERSION  this action's version
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ -n "${NGROK_APP_ID:-}" ]] || fail "the app-id input is required"

fetch_oidc_token

# Ship reads the commit from the token, and starts its release.
request=$(jq -cn --arg app_id "$NGROK_APP_ID" --arg version "$NGROK_ACTION_VERSION" \
	'{app_id: $app_id, action_version: $version}')
body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

status=$(curl --silent --show-error --retry 3 --retry-connrefused \
	-o "$body_file" -w '%{http_code}' \
	-X POST "${NGROK_API_URL%/}/v1/github-actions/build-config" \
	-H "Authorization: Bearer ${oidc_token}" \
	-H "Content-Type: application/json" \
	--data "$request") ||
	fail "could not reach ngrok ship at ${NGROK_API_URL}"

if [[ "$status" != "200" ]]; then
	message=$(jq -r '.error // empty' "$body_file" 2>/dev/null || true)
	fail "ngrok ship refused the build config request (HTTP ${status})${message:+: ${message}}"
fi

# Mask the credential before anything else can print it.
username=$(jq -r '.login.username // empty' "$body_file")
password=$(jq -r '.login.password // empty' "$body_file")
mask "$username"
mask "$password"

image_reference=$(jq -r '.image_reference' "$body_file")
[[ -n "$image_reference" && "$image_reference" != "null" ]] || fail "ngrok ship returned no image reference"

root=$(jq -r '.build.root // "."' "$body_file")
if [[ -n "${NGROK_CONTEXT:-}" ]]; then
	root=$NGROK_CONTEXT
fi

if jq -e '.login == null' "$body_file" >/dev/null; then
	output login_kind github-token
else
	output login_kind credential
	output registry "$(jq -r '.login.registry' "$body_file")"
	output username "$username"
	output password "$password"
fi

head=$(git rev-parse HEAD 2>/dev/null || true)
if [[ -n "$head" && "$head" != "$NGROK_COMMIT_SHA" ]]; then
	echo "::warning title=ngrok ship::$(escape_data "the checkout is at ${head}, but the image is tagged as ${NGROK_COMMIT_SHA}. Check out the default ref: actions/checkout with no ref input.")"
fi

output sha "$NGROK_COMMIT_SHA"
output image "${image_reference}:${NGROK_COMMIT_SHA}"
output image_reference "$image_reference"
output provider "$(jq -r '.build.provider' "$body_file")"
output root "$root"
output dockerfile "$(jq -r '.build.dockerfile // empty' "$body_file")"
output build_command "$(jq -r '.build.build_command // empty' "$body_file")"
output run_command "$(jq -r '.build.run_command // empty' "$body_file")"
