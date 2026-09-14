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

# StikJIT 1.5.0's generated distribution interfaces were emitted from a module
# that also declares a public enum named StikJIT. Xcode 26.3 resolves several
# module-qualified references (for example StikJIT.DDIPaths) against that enum,
# so the otherwise valid binary framework cannot be imported. Patch only the
# pinned release's textual interfaces after checksum verification; the binary
# and ABI remain untouched.
module_dir="$framework/ios-arm64/StikJIT.framework/Modules/StikJIT.swiftmodule"
for interface in "$module_dir"/*.swiftinterface; do
  sed -i '' \
    -e 's/StikJIT\.StikJIT\./StikJIT./g' \
    -e 's/StikJIT\.DDIPaths/DDIPaths/g' \
    -e 's/StikJIT\.DeveloperDiskImageService/DeveloperDiskImageService/g' \
    "$interface"
done
