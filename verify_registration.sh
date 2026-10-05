#!/usr/bin/env bash
# Check actual target membership without modifying the Xcode project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$ROOT/scripts/verify_registration.py" "$@"
