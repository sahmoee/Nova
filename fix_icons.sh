#!/usr/bin/env bash
# One-time fix: remove every stray tvOS App Store icon image stack so only the single
# valid App Store icon remains. Run this from anywhere inside the repo, then commit.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
cd "$REPO_ROOT"

BRAND="FrameTV/Resources/Assets-tvOS.xcassets/App Icon & Top Shelf Image.brandassets"
if [[ ! -d "$BRAND" ]]; then
  echo "error: brand assets folder not found at $BRAND" >&2
  exit 1
fi

echo "Scanning for stray App Store icon image stacks in:"
echo "  $BRAND"

# Any image stack whose name starts with App Icon - App Store is a leftover duplicate.
# The single correct App Store icon lives in App Store.imagestack and is never matched.
FOUND=0
while IFS= read -r dir; do
  echo "  removing: $(basename "$dir")"
  rm -rf "$dir"
  FOUND=$((FOUND+1))
done < <(find "$BRAND" -maxdepth 1 -type d -name "App Icon - App Store*" 2>/dev/null)

if [[ "$FOUND" -eq 0 ]]; then
  echo "No stray icons found. Catalog is already clean."
else
  echo "Removed $FOUND stray image stack(s)."
fi

echo
echo "Remaining icon image stacks:"
find "$BRAND" -maxdepth 1 -type d -name "*.imagestack" -exec basename {} \;
echo
echo "Done. Now run: git add -A && git commit -m \"Remove stray tvOS App Store icons\""
