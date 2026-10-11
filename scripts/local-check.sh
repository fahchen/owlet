#!/usr/bin/env bash
# Runs the repository's own verification commands but keeps every build artifact inside this
# checkout, so nothing is written to ~/Library/Developer/Xcode/DerivedData. `mise run check`
# stays as it is: it is the shared, canonical gate for CI and the git hook.
#
# Usage: scripts/local-check.sh [test|lint|all]   (default: all)
set -euo pipefail

mode="${1:-all}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

derived="$root/.build/derived"

if [[ "$mode" == "lint" || "$mode" == "all" ]]; then
  git diff --check HEAD
  xcrun swift-format lint --strict --recursive Owlet OwletTests
fi

if [[ "$mode" == "test" || "$mode" == "all" ]]; then
  xcodegen generate --quiet
  xcodebuild -project Owlet.xcodeproj -scheme Owlet \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived" test
fi
