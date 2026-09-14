#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="1.5.0"
expected="444b8d439df8455c34afbb51e279fd225265279195475f9b3fdbcf3a71a27e85"
vendor="app/Vendor"
framework="$vendor/StikJIT.xcframework"

if [[ -d "$framework" ]]; then
  exit 0
fi

mkdir -p "$vendor"
archive="$(mktemp -t stikjit).zip"
trap 'rm -f "$archive"' EXIT
curl -fL --retry 3 \
  "https://github.com/StikDebug/StikJIT/releases/download/$version/StikJIT.xcframework.zip" \
  -o "$archive"
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "StikJIT $version checksum mismatch: $actual" >&2
  exit 1
fi
ditto -x -k "$archive" "$vendor"
test -d "$framework"
