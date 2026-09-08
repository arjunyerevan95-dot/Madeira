#!/bin/bash
# Build source-pinned native dependencies without signing or device access.
set -euo pipefail
cd "$(dirname "$0")/.."
MADEIRA_ROOT="$PWD"
MADEIRA_JOBS=3
mkdir -p ci-output toolchains
xcodebuild -version
MADEIRA_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
case "${1:?Expected fex or llvm}" in
  fex)
    git submodule update --init --depth 1 FEX
    git -C FEX submodule update --init --depth 1 --jobs 3 \
      External/fmt External/xxhash External/range-v3 External/unordered_dense
    cmake -S FEX -B FEX/build-ios -G Ninja \
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
      -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$MADEIRA_SDK" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      -DBUILD_TESTING=OFF -DBUILD_FEXCONFIG=OFF -DBUILD_THUNKS=OFF \
      -DENABLE_LTO=OFF -DENABLE_WERROR=OFF -DENABLE_OFFLINE_TELEMETRY=OFF
    cmake --build FEX/build-ios --parallel "$MADEIRA_JOBS" \
      --target FEXCore FEXCore_Base JemallocLibs softfloat_3e
    tar -czf ci-output/fex-ios.tar.gz FEX/build-ios
    ;;
  llvm)
    git clone --depth 1 --branch llvmorg-15.0.7 \
      https://github.com/llvm/llvm-project.git toolchains/llvm-project
    python3 - <<'PY'
from pathlib import Path
p = Path('toolchains/llvm-project/llvm/cmake/modules/AddLLVM.cmake')
s = p.read_text()
old = 'MATCHES "Darwin"'
assert old in s, 'LLVM linker platform condition was not found'
p.write_text(s.replace(old, 'MATCHES "Darwin|iOS"'))
PY
    cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-host-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DLLVM_TARGETS_TO_BUILD= -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
      -DLLVM_ENABLE_TERMINFO=OFF
    cmake --build toolchains/llvm-host-build --parallel "$MADEIRA_JOBS" --target llvm-tblgen
    cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-ios-build -G Ninja \
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
      -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$MADEIRA_SDK" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      -DLLVM_TABLEGEN="$MADEIRA_ROOT/toolchains/llvm-host-build/bin/llvm-tblgen" \
      -DLLVM_TARGETS_TO_BUILD= -DLLVM_BUILD_UTILS=OFF -DLLVM_BUILD_TOOLS=OFF \
      -DLLVM_INCLUDE_TOOLS=OFF -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
      -DLLVM_ENABLE_TERMINFO=OFF
    cmake --build toolchains/llvm-ios-build --parallel "$MADEIRA_JOBS" \
      --target LLVMPasses LLVMBitWriter
    tar -czf ci-output/llvm-ios.tar.gz toolchains/llvm-ios-build/lib \
      toolchains/llvm-ios-build/include toolchains/llvm-project/llvm/include
    ;;
  *) echo 'Unknown dependency' >&2; exit 2 ;;
esac
shasum -a 256 ci-output/*.tar.gz > "ci-output/${1}-sha256.txt"
git rev-parse HEAD > "ci-output/${1}-source-commit.txt"
