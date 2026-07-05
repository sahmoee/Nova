#!/usr/bin/env bash
# apply.sh - run this BEFORE commit.sh.
# Deletes DownloadManager.swift, which has been fully removed from the app.
# The delta cannot delete a file on the Mac by itself (BuildBuddy only rsyncs
# files present in the delta), so this step performs the removal. commit.sh
# then stages it via git add -A.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
cd "$REPO_ROOT"

TARGET="FrameTV/Services/DownloadManager.swift"
if [[ -f "$TARGET" ]]; then
  rm -f "$TARGET"
  echo "Deleted $TARGET"
else
  echo "$TARGET already absent - nothing to delete."
fi

echo "apply.sh done. Now run commit.sh to stage and commit the removal."
