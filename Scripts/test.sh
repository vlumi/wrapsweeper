#!/usr/bin/env bash
# Run the package logic tests (no Xcode project needed). Usage: test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Running DonpaCore tests..."
swift test --package-path Packages/DonpaCore
