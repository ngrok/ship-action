# shellcheck shell=bash
# Helpers shared by the action's scripts.

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

# Sets oidc_token to a GitHub OIDC token for ship. A token lives for minutes,
# so each request to ship gets a new one. It sets a variable and prints
# nothing: mask writes a workflow command to stdout, which a command
# substitution would capture into the token.
fetch_oidc_token() {
	if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
		fail "no GitHub OIDC token is available. Give the job the 'id-token: write' permission. Pull requests from forks do not get OIDC tokens."
	fi
	local response
	response=$(curl --silent --show-error --fail --retry 3 \
		-H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
		"${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=ngrok-ship") ||
		fail "could not get a GitHub OIDC token"
	oidc_token=$(jq -r '.value // empty' <<<"$response")
	[[ -n "$oidc_token" ]] || fail "GitHub returned no OIDC token"
	mask "$oidc_token"
}
