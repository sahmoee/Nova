#!/usr/bin/env bash
# ============================================================================
# release_check.sh — one command that runs every automated release gate.
#
# Gates:
#   1. Configuration contract        (validate_astra_config.sh)
#   2. Bundle-ID guard               (bundleid-guard.sh)
#   3. Target registration           (verify_registration.sh)
#   4. Worker JavaScript syntax      (node --check on both worker files)
#   5. Worker mirror integrity       (worker.js == worker/worker.js)
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
run bash validate_astra_config.sh

step "2/6 Bundle-ID guard"
run bash bundleid-guard.sh

step "3/6 Target registration"
run bash verify_registration.sh

step "4/6 Worker JavaScript syntax"
if command -v node >/dev/null 2>&1; then
  run node --check worker.js
  [[ -f worker/worker.js ]] && run node --check worker/worker.js
else
  echo ">> node not found — skipping JS syntax check (install Node to enable)."
fi

step "5/6 Worker mirror integrity"
if [[ -f worker/worker.js ]]; then
  if diff -q worker.js worker/worker.js >/dev/null; then echo "  ✓ worker files identical"; else
    echo ">> FAILED: worker.js and worker/worker.js differ"; FAIL=1; fi
else
  echo "  (no nested worker/worker.js — skipping)"
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
