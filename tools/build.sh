#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK_PATH" \
  -miphoneos-version-min=15.0 -fobjc-arc -fblocks -O2 \
  -Wall -Wextra -Werror -dynamiclib -framework Foundation \
  -install_name @rpath/DouyinAntiRecall.dylib \
  -Wl,-dead_strip -Wl,-headerpad_max_install_names \
  src/DouyinAntiRecall.m src/DARCache.m -o build/DouyinAntiRecall.dylib
codesign --force --sign - --timestamp=none build/DouyinAntiRecall.dylib
codesign --verify --strict build/DouyinAntiRecall.dylib
xcrun lipo -info build/DouyinAntiRecall.dylib
xcrun otool -L build/DouyinAntiRecall.dylib
shasum -a 256 build/DouyinAntiRecall.dylib > build/SHA256SUMS
