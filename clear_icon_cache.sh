#!/usr/bin/env bash
# Clears the Xcode caches that make Nova keep showing the old Nova icon.
# Only removes regenerable caches. Safe to run.
set -euo pipefail

echo "==> Quitting Xcode (if running)..."
osascript -e 'tell application "Xcode" to quit' 2>/dev/null || true
sleep 2

DD="$HOME/Library/Developer/Xcode/DerivedData"
echo "==> Removing Nova DerivedData..."
if compgen -G "$DD/Nova-*" > /dev/null; then
  rm -rf "$DD"/Nova-*
  echo "    removed: $DD/Nova-*"
else
  echo "    none found (nothing to remove)"
fi

echo "==> Clearing Xcode asset / thumbnail caches..."
rm -rf "$HOME/Library/Caches/com.apple.dt.Xcode/"* 2>/dev/null || true
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex" 2>/dev/null || true

echo "==> Clearing icon services cache (launcher thumbnails)..."
rm -rf "$HOME/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
sudo find /private/var/folders -name com.apple.dock.iconcache -delete 2>/dev/null || true

echo ""
echo "Done. Now:"
echo "  1. Delete the Nova app from the device/simulator 'Key'."
echo "  2. Reopen Xcode -> Product -> Clean Build Folder (Shift-Cmd-K)."
echo "  3. Build & run. The new Nova icon should appear everywhere."
