#!/usr/bin/env bash
# Read-only Nova release preflight. Xcode and device validation are separate.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
worker_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --worker)
      [ "$#" -ge 2 ] || { echo "--worker requires a checkout path" >&2; exit 2; }
      worker_dir="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./release_check.sh [--worker /path/to/UnifiedWorker]"
      echo "Runs Nova configuration, target membership, and tracked-file hygiene checks."
      echo "With --worker, also runs that checkout's npm verify script. Never deploys."
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT" || exit 1
FAIL=0
run() { "$@" || { echo "FAILED: $*"; FAIL=1; }; }
run bash validate_nova_config.sh
run bash bundleid-guard.sh
run bash verify_registration.sh
run plutil -lint Nova.xcodeproj/project.pbxproj
run python3 - <<'HYGIENE'
import pathlib, subprocess, sys
tracked = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
bad = [name for name in tracked if name and (
    pathlib.Path(name).name == ".DS_Store" or pathlib.Path(name).name.startswith("._")
    or ".bak." in pathlib.Path(name).name)]
for name in bad: print("Unexpected tracked build/recovery file:", name)
print("Tracked-file hygiene:", "FAILED" if bad else "OK")
sys.exit(bool(bad))
HYGIENE
if [ -n "$worker_dir" ]; then
  if [ ! -f "$worker_dir/package.json" ]; then
    echo "Worker checkout has no package.json" >&2; FAIL=1
  else
    run npm --prefix "$worker_dir" run verify
  fi
else
  echo "Backend verification was not requested; validate UnifiedWorker separately when its contract changes."
fi
if [ "$FAIL" -ne 0 ]; then
  echo "Nova preflight failed. Resolve these checks before release." >&2
  exit 1
fi
echo "Nova repository preflight passed. Native builds and device checks remain required."
