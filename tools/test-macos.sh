#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun --sdk macosx clang -fobjc-arc -fblocks -DDAR_TESTING=1 \
  -Wall -Wextra -Werror -Isrc -framework Foundation \
  src/DouyinAntiRecall.m src/DARCache.m src/DAROptions.m tests/MessageHookTests.m \
  -o build/MessageHookTests
build/MessageHookTests
