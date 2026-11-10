#!/usr/bin/env bash
# Installs a pinned Railpack release and checks its sha256 before it runs.
# Writes the matching BuildKit frontend image as the step output "frontend".
#
# Inputs (environment):
#   RUNNER_TEMP  the directory that gets the binary
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Change the version, the two archive checksums, and the frontend digest
# together. The checksums are in the release's checksums.txt.
version="0.30.0"
frontend="ghcr.io/railwayapp/railpack-frontend:v${version}@sha256:8120546d9e67be53c7edebec900ed69ef724fbde890d43cb24455dfca4aebcc0"

case "$(uname -s)-$(uname -m)" in
Linux-x86_64)
	target="x86_64-unknown-linux-musl"
	sha256="3bbceddaa12bdafa8a30076a7e2425a72f3ad1a934027508bb19493e44da1657"
	;;
Linux-aarch64 | Linux-arm64)
	target="arm64-unknown-linux-musl"
	sha256="1ea719b2dc39e65652fd8b68ae1832373c0bca5733a2ef4c57ccd43b5bea574f"
	;;
*)
	fail "an app with the automatic build provider needs a Linux x86_64 or arm64 runner"
	;;
esac

bin_dir="${RUNNER_TEMP}/railpack-bin"
archive="$(mktemp "${RUNNER_TEMP}/railpack-XXXXXX.tar.gz")"
trap 'rm -f "$archive"' EXIT

curl --silent --show-error --fail --location --retry 3 -o "$archive" \
	"https://github.com/railwayapp/railpack/releases/download/v${version}/railpack-v${version}-${target}.tar.gz" ||
	fail "could not download Railpack ${version}"
echo "${sha256}  ${archive}" | sha256sum --check --quiet ||
	fail "the Railpack ${version} archive does not match its checksum"

mkdir -p "$bin_dir"
tar -xzf "$archive" -C "$bin_dir" railpack
echo "$bin_dir" >>"$GITHUB_PATH"
output frontend "$frontend"
