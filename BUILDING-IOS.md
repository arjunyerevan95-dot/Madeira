# Rebuilding this iPhone package

This fork adds a GitHub Actions build on the standard `macos-15` ARM64 runner
with Xcode 26.3. A local Mac and Apple signing credentials are not needed to
compile the unsigned package.

## Build sequence

1. Run **Build iOS dependencies** (`ios-dependencies.yml`). Select `all` to
   build FEX, LLVM, and Wine, or select one component to repeat only that build.
2. Wait for each component to finish successfully. Record the run ID containing
   each component's archive. Individual successful components can be used even
   when another job in their original matrix run failed.
3. Run **Build Madeira iPhone package** (`ios-app.yml`) and provide the three
   run IDs as `fex_run`, `llvm_run`, and `wine_run`.
4. Download the `Madeira-iPhone` artifact. A successful build contains
   `Madeira-unsigned.ipa`, its SHA-256 checksum, source commit, and build notes.

Example using GitHub CLI in this fork:

```sh
gh workflow run ios-dependencies.yml -f component=all
gh run list --workflow ios-dependencies.yml
gh workflow run ios-app.yml \
  -f fex_run=FEX_RUN_ID -f llvm_run=LLVM_RUN_ID -f wine_run=WINE_RUN_ID
```

## What is compiled

- The FEX native iOS libraries, including generated interface headers.
- LLVM 15.0.7 libraries for iOS, plus a native host table generator.
- Wine's iOS server, ntdll, and win32u libraries, FreeType 2.13.3, and the
  pinned GMP/Nettle/GnuTLS source archives already included in the repository.
- DXMT's native iOS and shader conversion libraries, shader support modules,
  and the Swift/Objective-C host app.

The Wine ARM64EC and ARM64 Windows DLLs and the `xtajit64.dll` emulator module
are the binaries tracked by the original Madeira source revision. This build
does not rebuild those PE modules.

The starting Madeira commit is `97e2ce26e6dc9e4a38976f3b5deb9272d64558eb`.
Submodule revisions remain pinned by that commit. The native FEX build applies
`patches/fex-native-diagnostics.patch` to guard Windows-specific diagnostic
references. The Wine server script can bootstrap its archive from source.
These changes are carried for this Madeira build; no upstream contribution is
made by running the workflows.

## Installation and verification boundary

The IPA targets physical ARM64 iPhones/iPads on iOS 18 or later. It must be
signed using the installer's own Apple ID and sideloaded. JIT must then be
enabled using the project's StikDebug integration. Microsoft VC++ runtime
DLLs are not bundled; follow `tools/fetch-vcruntime.md` if a game needs them.

The packaging job checks architecture, required bundled modules, property-list
validity, dynamic library paths, and ZIP integrity. A successful build does not
establish game compatibility or on-device runtime stability.
