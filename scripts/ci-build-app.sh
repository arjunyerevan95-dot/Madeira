#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p ci-output
git submodule update --init --depth 1 FEX research/dxmt
git -C FEX submodule update --init --depth 1 --jobs 3 \
  External/fmt External/xxhash External/range-v3 External/unordered_dense
git -C research/dxmt submodule update --init --depth 1 --recursive --jobs 3
for component in fex llvm wine; do
  MADEIRA_INPUT_ARCHIVE="$(find "build-inputs/$component" -name "$component-ios.tar.gz" -type f)"
  MADEIRA_INPUT_HASH="$(find "build-inputs/$component" -name "$component-sha256.txt" -type f)"
  test -f "$MADEIRA_INPUT_ARCHIVE"
  test -f "$MADEIRA_INPUT_HASH"
  cp "$MADEIRA_INPUT_ARCHIVE" ci-output/
  shasum -a 256 -c "$MADEIRA_INPUT_HASH"
  tar -xzf "ci-output/$component-ios.tar.gz"
  rm "ci-output/$component-ios.tar.gz"
done

# Compile the three shader support modules omitted from source control.
if ! xcrun -sdk iphoneos metal --version; then
  xcodebuild -downloadComponent MetalToolchain
fi
mkdir -p build/dxmt-ios/shader-headers
for shader in air_msad air_samplepos air_tessellation; do
  xcrun -sdk iphoneos metal -std=metal3.1 --target=air64-apple-ios18.0 \
    -c "research/dxmt/src/airconv/shaders/$shader.metal" \
    -o "build/dxmt-ios/shader-headers/$shader.air"
  xxd -n "$shader" -i "build/dxmt-ios/shader-headers/$shader.air" \
    "build/dxmt-ios/shader-headers/$shader.h"
done
bash build/dxmt-ios/build.sh
xcrun -sdk iphoneos libtool -static -o app/Madeira/libdxmt_combined.a \
  build/dxmt-ios/obj/*.o toolchains/llvm-ios-build/lib/*.a

# The upstream project declares this folder as a resource but excludes the
# separately licensed Microsoft DLLs. Keep the resource folder present.
mkdir -p app/Madeira/x86_64-vcruntime
cp tools/fetch-vcruntime.md app/Madeira/x86_64-vcruntime/README.md
xcodebuild -project app/Madeira.xcodeproj -scheme Madeira \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/xcode-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  PRODUCT_BUNDLE_IDENTIFIER=com.madeira.emulator IPHONEOS_DEPLOYMENT_TARGET=18.0

MADEIRA_APP=build/xcode-derived/Build/Products/Release-iphoneos/Madeira.app
test -s "$MADEIRA_APP/Madeira"
test -s "$MADEIRA_APP/arm64ec-windows/xtajit64.dll"
test -s "$MADEIRA_APP/arm64ec-windows/d3d11.dll"
plutil -lint "$MADEIRA_APP/Info.plist"
lipo -verify_arch arm64 "$MADEIRA_APP/Madeira"
otool -L "$MADEIRA_APP/Madeira" | tee ci-output/linked-libraries.txt
if grep -E '/Users/|/opt/homebrew/' ci-output/linked-libraries.txt; then
  echo 'Unexpected non-system dynamic library dependency' >&2
  exit 1
fi
mkdir -p build/ipa/Payload
ditto "$MADEIRA_APP" build/ipa/Payload/Madeira.app
(cd build/ipa && zip -qry ../../ci-output/Madeira-unsigned.ipa Payload)
unzip -t ci-output/Madeira-unsigned.ipa | tail -1
shasum -a 256 ci-output/Madeira-unsigned.ipa > ci-output/SHA256SUMS
git rev-parse HEAD > ci-output/source-commit.txt
cp app/Madeira/Madeira.entitlements ci-output/
cp tools/fetch-vcruntime.md ci-output/
cat > ci-output/BUILD-NOTES.txt <<'EOF'
Madeira iPhone build

This IPA is unsigned. Sign it with your own Apple ID using a sideloading tool.
The target is a physical ARM64 iPhone/iPad on iOS 18 or later.
JIT must be enabled through the project's StikDebug workflow before game use.
The package contains the upstream Wine PE modules and source-built iOS libraries.
Microsoft's optional Visual C++ redistributable DLLs are not bundled; see
fetch-vcruntime.md for the upstream instructions.
Compilation and archive validation do not establish on-device compatibility.
EOF
