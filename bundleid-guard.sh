#!/bin/bash
# ============================================================================
# bundleid-guard.sh — stop PRODUCT_BUNDLE_IDENTIFIER from silently reverting.
#
# Xcode's General tab shows ONE bundle id, but the pbxproj stores it PER
# build configuration (Debug/Release/etc.) and per target. A "revert" almost
# always means one configuration disagrees with the others, or an .xcconfig /
# committed pbxproj keeps restoring an old value. This script:
#
#   1. AUDITS every PRODUCT_BUNDLE_IDENTIFIER in the .xcodeproj and reports
#      mismatches (the real cause of the "it reverted" surprise).
#   2. Scans .xcconfig files for overrides that would win over the General tab.
#   3. Optionally PINS a chosen id across all configs of one target so it can't
#      drift again.
#
# Read-only by default. Nothing is written unless you pass --set.
#
# Usage:
#   ./bundleid-guard.sh                         # audit Nova.xcodeproj here
#   ./bundleid-guard.sh --project /path/App.xcodeproj
#   ./bundleid-guard.sh --set com.nova.app.ios --target Nova-iOS
#   ./bundleid-guard.sh --set com.nova.app.ios --target Nova-iOS --apply
#
# Without --apply, --set only PREVIEWS the change (writes nothing).
# ============================================================================
set -u
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT=""
WANT_ID=""
TARGET=""
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --set)     WANT_ID="$2"; shift 2 ;;
    --target)  TARGET="$2";  shift 2 ;;
    --apply)   APPLY=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Locate the project if not given: first *.xcodeproj next to this script or CWD.
if [ -z "$PROJECT" ]; then
  DIR="$SCRIPT_ROOT"
  PROJECT="$(find "$DIR" "$PWD" -maxdepth 2 -name '*.xcodeproj' -type d 2>/dev/null | head -1)"
fi
if [ -z "$PROJECT" ] || [ ! -d "$PROJECT" ]; then
  echo "No .xcodeproj found. Pass one with --project /path/YourApp.xcodeproj"
  exit 1
fi
PBX="$PROJECT/project.pbxproj"
if [ ! -f "$PBX" ]; then
  echo "No project.pbxproj inside $PROJECT"
  exit 1
fi

echo "Project: $PROJECT"
echo "========================================================"

# ----------------------------------------------------------------------------
# 1. Audit every bundle id occurrence.
# ----------------------------------------------------------------------------
echo
echo "PRODUCT_BUNDLE_IDENTIFIER values found in project.pbxproj:"
echo "--------------------------------------------------------"
# Print each id with a count. Trims trailing semicolons/quotes.
grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' "$PBX" \
  | sed 's/PRODUCT_BUNDLE_IDENTIFIER = //; s/;$//; s/^"//; s/"$//' \
  | sort | uniq -c | sort -rn \
  | while read -r count id; do
      printf "  %3sx  %s\n" "$count" "$id"
    done

DISTINCT=$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' "$PBX" \
  | sed 's/PRODUCT_BUNDLE_IDENTIFIER = //; s/;$//; s/^"//; s/"$//' \
  | sort -u | wc -l | tr -d ' ')

# The intentional per-target identifiers. Having these is correct,
# not a conflict — the old logic wrongly flagged them.
ALLOWED_IDS="com.nova.app.ios com.nova.app.ios.widgets com.nova.app.tvos com.nova.app.ios.tests com.nova.app.ios.watchkitapp"
UNEXPECTED=""
while read -r id; do
  [ -z "$id" ] && continue
  case " $ALLOWED_IDS " in
    *" $id "*) : ;;                 # expected per-target id
    *) UNEXPECTED="$UNEXPECTED $id" ;;
  esac
done < <(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' "$PBX" \
  | sed 's/PRODUCT_BUNDLE_IDENTIFIER = //; s/;$//; s/^"//; s/"$//' | sort -u)

echo
if [ -n "$UNEXPECTED" ]; then
  echo ">> UNEXPECTED bundle id(s):$UNEXPECTED"
  echo "   Expected only: $ALLOWED_IDS"
  GUARD_STATUS=1
else
  echo ">> OK — only the intended per-target ids are present:"
  echo "   $ALLOWED_IDS"
  GUARD_STATUS=0
fi

# ----------------------------------------------------------------------------
# 2. .xcconfig overrides (these WIN over the General tab).
# ----------------------------------------------------------------------------
echo
echo "Checking .xcconfig files for PRODUCT_BUNDLE_IDENTIFIER overrides..."
echo "--------------------------------------------------------"
PROJ_ROOT="$(dirname "$PROJECT")"
FOUND_XCCONFIG=0
while IFS= read -r f; do
  if grep -q 'PRODUCT_BUNDLE_IDENTIFIER' "$f" 2>/dev/null; then
    FOUND_XCCONFIG=1
    echo "  Override in: $f"
    grep -n 'PRODUCT_BUNDLE_IDENTIFIER' "$f" | sed 's/^/      /'
  fi
done < <(find "$PROJ_ROOT" -maxdepth 3 -name '*.xcconfig' 2>/dev/null)
[ "$FOUND_XCCONFIG" -eq 0 ] && echo "  None found. (Good — no xcconfig is fighting the General tab.)"

# ----------------------------------------------------------------------------
# 3. Is a committed pbxproj restoring it? (git heuristic)
# ----------------------------------------------------------------------------
echo
if git -C "$PROJ_ROOT" rev-parse >/dev/null 2>&1; then
  if ! git -C "$PROJ_ROOT" diff --quiet -- "$PBX" 2>/dev/null; then
    echo "NOTE: project.pbxproj has UNCOMMITTED changes. If you edit the id in"
    echo "Xcode but never commit, a later 'git checkout' / branch switch will"
    echo "restore the committed value — looking exactly like a 'revert'."
  else
    echo "git: project.pbxproj is clean (matches last commit)."
  fi
fi

# ----------------------------------------------------------------------------
# 4. Optional pin.
# ----------------------------------------------------------------------------
if [ -n "$WANT_ID" ]; then
  if [ -z "$TARGET" ]; then
    echo "Bundle-ID updates require --target; app and extension identities must stay distinct." >&2
    exit 1
  fi
  pin_args=(--project "$PROJECT" --target "$TARGET" --set "$WANT_ID")
  [ "$APPLY" -eq 1 ] && pin_args+=(--apply)
  python3 "$SCRIPT_ROOT/scripts/pin_bundle_id.py" "${pin_args[@]}" || exit 1
fi

echo
echo "Done."
exit "${GUARD_STATUS:-0}"
