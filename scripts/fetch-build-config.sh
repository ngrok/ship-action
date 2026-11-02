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

# Escapes workflow command data the way @actions/core does, so a value with
# a newline cannot end the command and start another one.
escape_data() {
	local s=$1
	s=${s//'%'/'%25'}
	s=${s//$'\r'/'%0D'}
	s=${s//$'\n'/'%0A'}
	printf '%s' "$s"
}

fail() {
	echo "::error title=ngrok ship::$(escape_data "$*")"
	exit 1
}

mask() {
	[[ -z "$1" ]] || echo "::add-mask::$(escape_data "$1")"
}

# Writes one step output. A random delimiter keeps a value with newlines
# from ending the output early.
output() {
	local name=$1 value=$2 delim
	delim="ngrok_$(openssl rand -hex 16)"
	printf '%s<<%s\n%s\n%s\n' "$name" "$delim" "$value" "$delim" >>"$GITHUB_OUTPUT"
}

[[ -n "${NGROK_APP_ID:-}" ]] || fail "the app-id input is required"

if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
	fail "no GitHub OIDC token is available. Give the job the 'id-token: write' permission. Pull requests from forks do not get OIDC tokens."
fi

oidc_response=$(curl --silent --show-error --fail --retry 3 \
	-H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
	"${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=ngrok-ship") ||
	fail "could not get a GitHub OIDC token"
oidc_token=$(jq -r '.value // empty' <<<"$oidc_response")
[[ -n "$oidc_token" ]] || fail "GitHub returned no OIDC token"
mask "$oidc_token"

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
	echo "::warning title=ngrok ship::$(escape_data "the checkout is at ${head}, but the image is tagged as ${NGROK_COMMIT_SHA}. For pull_request runs, check out the PR head: actions/checkout with ref: \${{ github.event.pull_request.head.sha }}")"
fi

output sha "$NGROK_COMMIT_SHA"
output image "${image_reference}:${NGROK_COMMIT_SHA}"
output image_reference "$image_reference"
output provider "$(jq -r '.build.provider' "$body_file")"
output root "$root"
output dockerfile "$(jq -r '.build.dockerfile // empty' "$body_file")"
output build_command "$(jq -r '.build.build_command // empty' "$body_file")"
output run_command "$(jq -r '.build.run_command // empty' "$body_file")"
