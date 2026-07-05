#!/usr/bin/env bash
# verify_registration.sh
# Fails (nonzero exit) if any .swift source under the main FrameTV target
# is missing its required pbxproj entries. REPORT ONLY - never mutates.
#
# Required per source file (2 real targets: iOS/iPadOS + tvOS):
#   1x PBXFileReference def
#   1x PBXGroup children entry
#   2x PBXBuildFile def        (one per target)
#   2x Sources build-phase entry (one per target)
#
# Rationale: "Cannot find 'X' in scope" at compile time is almost always a
# file present on disk but absent from one/both targets. This catches it
# BEFORE the build instead of after.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PBXPROJ="$ROOT/FrameTV/FrameTV.xcodeproj/project.pbxproj"
SRC_DIR="$ROOT/FrameTV/FrameTV"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "verify_registration: pbxproj not found at $PBXPROJ" >&2
  exit 2
fi

# Files intentionally excluded from the build (known orphans).
# Add a filename here ONLY if it is deliberately unregistered.
EXCLUDE=(
  "MockData.swift"
)

is_excluded() {
  local base="$1"
  for e in "${EXCLUDE[@]}"; do
    [[ "$base" == "$e" ]] && return 0
  done
  return 1
}

FAIL=0

# Iterate every Swift file under the app sources (not widgets/topshelf, which
# use PBXFileSystemSynchronizedRootGroup and register automatically).
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  is_excluded "$base" && continue

  fileref=$(grep -c "/\* $base \*/ = {isa = PBXFileReference" "$PBXPROJ" || true)
  buildfile=$(grep -c "/\* $base in Sources \*/ = {isa = PBXBuildFile" "$PBXPROJ" || true)
  # children + sources phase both render as "/* base in Sources */," or
  # "/* base */," lines; count the "in Sources" phase membership refs:
  phase=$(grep -c "/\* $base in Sources \*/," "$PBXPROJ" || true)

  problems=()
  [[ "$fileref"   -lt 1 ]] && problems+=("missing PBXFileReference")
  [[ "$buildfile" -ne 2 ]] && problems+=("PBXBuildFile defs = $buildfile (need 2)")
  [[ "$phase"     -ne 2 ]] && problems+=("Sources-phase entries = $phase (need 2)")

  if [[ ${#problems[@]} -gt 0 ]]; then
    FAIL=1
    echo "UNREGISTERED: $base" >&2
    for p in "${problems[@]}"; do echo "    - $p" >&2; done
  fi
done < <(find "$SRC_DIR" -name '*.swift' -type f -print0)

if [[ "$FAIL" -ne 0 ]]; then
  echo "" >&2
  echo "verify_registration: FAILED - fix pbxproj before committing." >&2
  echo "  (If a file is deliberately excluded, add it to EXCLUDE[] in this script.)" >&2
  exit 1
fi

echo "verify_registration: OK - all Swift sources registered in both targets."
