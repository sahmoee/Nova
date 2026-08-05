#!/usr/bin/env bash
# ============================================================================
# release_check.sh — one command that runs every automated release gate.
#
# Gates:
#   1. Configuration contract        (validate_nova_config.sh)
#   2. Bundle-ID guard               (bundleid-guard.sh)
#   3. Target registration           (verify_registration.sh)
#   4. Worker typecheck + tests       (single canonical worker package)
#   5. Worker deployment dry run     (validates Wrangler config/bindings)
#   6. Repository hygiene            (no AppleDouble / .DS_Store / backups tracked)
#
# Exits nonzero if any gate fails. Requires: bash, node (for the worker checks).
# Does NOT run Xcode — Apple SDK compilation must happen on a Mac.
# ============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
FAIL=0
step() { printf "\n=== %s ===\n" "$1"; }
run()  { "$@"; if [[ $? -ne 0 ]]; then echo ">> FAILED: $*"; FAIL=1; fi; }

step "1/6 Configuration contract"
run bash validate_nova_config.sh

step "2/6 Bundle-ID guard"
run bash bundleid-guard.sh

step "3/6 Target registration"
run bash verify_registration.sh

step "4/6 Worker typecheck + tests"
if command -v npm >/dev/null 2>&1 && [[ -d worker/node_modules ]]; then
  run npm --prefix worker run types:check
  run npm --prefix worker run typecheck
  run npm --prefix worker test
else
  echo ">> worker dependencies missing — run 'npm --prefix worker ci'."
  FAIL=1
fi

step "5/6 Worker deployment dry run"
if command -v npm >/dev/null 2>&1 && [[ -d worker/node_modules ]]; then
  run npm --prefix worker run deploy:dry
else
  echo ">> worker dependencies missing — dry run unavailable."
  FAIL=1
fi

step "6/6 Repository hygiene"
AD=$(find . -name '._*' -not -path './.git/*' | wc -l | tr -d ' ')
DS=$(find . -name '.DS_Store' -not -path './.git/*' | wc -l | tr -d ' ')
BB=$(find . -type d -name '.buildbuddy-backups' -not -path './.git/*' | wc -l | tr -d ' ')
if [[ "$AD" -eq 0 && "$DS" -eq 0 && "$BB" -eq 0 ]]; then
  echo "  ✓ clean"
else
  echo ">> Pollution present (AppleDouble=$AD .DS_Store=$DS backups=$BB). Run ./cleanup_repo.sh"
  FAIL=1
fi

echo
if [[ "$FAIL" -ne 0 ]]; then echo "release_check: FAILED — fix the above before releasing."; exit 1; fi
echo "release_check: ALL GATES PASSED (note: Xcode build/sign must still run on a Mac)."
