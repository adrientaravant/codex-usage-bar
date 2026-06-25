#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CocoUsageBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
"$ROOT_DIR/script/package_tester.sh"
