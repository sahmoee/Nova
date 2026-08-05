#!/bin/bash
# ============================================================================
# nova-rename-bundleids.sh — migrate the old FrameTV app identity to Astra's
# permanent App Store identity while preserving widget-extension nesting.
#
# Your audit showed three DISTINCT-but-consistent ids (2x each = Debug+Release):
#     com.frametv.app.ios          -> com.astra.app.ios
#     com.frametv.app.ios.widgets  -> com.astra.app.ios.widgets
#     com.frametv.app.tvos         -> com.astra.app.tvos
#
# So nothing is "reverting" — the project was cloned from FrameTV and never
# Nova keeps these Astra identifiers intentionally: changing them to com.nova
# would install a separate app and lose automatic access to Astra's iCloud KVS,
# sandbox, App Group, and Keychain data. The visible product name remains Nova.
#
# Read-only until --apply. Makes a timestamped .bak before writing.
#
# Usage:
#   ./nova-rename-bundleids.sh                 # preview the default rename
#   ./nova-rename-bundleids.sh --apply         # write it
#   ./nova-rename-bundleids.sh --prefix com.astra.app --apply
#   ./nova-rename-bundleids.sh --project /path/Nova.xcodeproj
# ============================================================================
set -u

PROJECT=""
APPLY=0
# New prefix; the three ids are derived from it (app, app.widgets, tvos).
NEW_PREFIX="com.astra.app"

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --prefix)  NEW_PREFIX="$2"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$PROJECT" ]; then
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT="$(find "$DIR" "$PWD" -maxdepth 2 -name 'Nova.xcodeproj' -type d 2>/dev/null | head -1)"
  [ -z "$PROJECT" ] && PROJECT="$(find "$DIR" "$PWD" -maxdepth 2 -name '*.xcodeproj' -type d 2>/dev/null | head -1)"
fi
if [ -z "$PROJECT" ] || [ ! -d "$PROJECT" ]; then
  echo "No .xcodeproj found. Pass one with --project /path/Nova.xcodeproj"
  exit 1
fi
PBX="$PROJECT/project.pbxproj"
[ -f "$PBX" ] || { echo "No project.pbxproj inside $PROJECT"; exit 1; }

# Old -> new, exact strings. Order matters: replace the longest (widgets) first
# so it can't be partially caught by the shorter app-id rule.
OLD_IOS="com.frametv.app.ios"
OLD_WID="com.frametv.app.ios.widgets"
OLD_TVOS="com.frametv.app.tvos"

NEW_IOS="$NEW_PREFIX.ios"
NEW_WID="$NEW_PREFIX.ios.widgets"
NEW_TVOS="$NEW_PREFIX.tvos"

echo "Project: $PROJECT"
echo "========================================================"
echo "Current PRODUCT_BUNDLE_IDENTIFIER values:"
grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' "$PBX" \
  | sed 's/PRODUCT_BUNDLE_IDENTIFIER = //; s/;$//' | sort | uniq -c
echo
echo "Planned rename (nesting preserved):"
printf "  %-34s -> %s\n" "$OLD_WID"  "$NEW_WID"
printf "  %-34s -> %s\n" "$OLD_IOS"  "$NEW_IOS"
printf "  %-34s -> %s\n" "$OLD_TVOS" "$NEW_TVOS"
echo

if [ "$APPLY" -eq 0 ]; then
  echo "(PREVIEW ONLY — re-run with --apply to write. A .bak is made first.)"
  echo
  echo "Lines that WOULD change:"
  grep -n 'PRODUCT_BUNDLE_IDENTIFIER' "$PBX" | sed 's/^/  /'
  exit 0
fi

cp "$PBX" "$PBX.bak.$(date +%Y%m%d%H%M%S)"

# Widgets first (longest), then tvos, then ios. Using | as sed delimiter to
# avoid escaping the dots; dots-as-any-char is harmless on these literals.
/usr/bin/sed -i.tmp \
  -e "s|$OLD_WID|$NEW_WID|g" \
  -e "s|$OLD_TVOS|$NEW_TVOS|g" \
  -e "s|$OLD_IOS|$NEW_IOS|g" \
  "$PBX"
rm -f "$PBX.tmp"

echo "Written. New state:"
grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' "$PBX" \
  | sed 's/PRODUCT_BUNDLE_IDENTIFIER = //; s/;$//' | sort | uniq -c
echo
echo "Backup: $(ls -t "$PBX".bak.* | head -1)"
echo
echo "Next:"
echo "  1. Reopen Nova in Xcode; confirm each target's id in General."
echo "  2. Commit so a future checkout can't undo it:"
echo "       git -C \"$(dirname "$PROJECT")\" add \"$PBX\""
echo "       git -C \"$(dirname "$PROJECT")\" commit -F - <<'MSG'"
echo "       Rename bundle identifiers from com.frametv to $NEW_PREFIX"
echo "       MSG"
echo
echo "Done."
