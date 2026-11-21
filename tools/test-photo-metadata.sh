#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Isrc \
  -framework Foundation -framework ImageIO -framework CoreGraphics \
  src/DARPhotoDate.m tests/PhotoMetadataTests.m -o build/PhotoMetadataTests
build/PhotoMetadataTests
