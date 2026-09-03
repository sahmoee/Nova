#!/usr/bin/env bash
# Legacy explicit build-reservation command. Public version changes are manual.
# Normal Xcode builds/archive already reserve a number through shared schemes.
set -euo pipefail
QA_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 "$QA_REPO_ROOT/scripts/qa_build_number.py" --project "$QA_REPO_ROOT/Nova.xcodeproj"
