#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MSG_FILE="$SCRIPT_DIR/COMMIT_MSG.txt"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

if [ ! -f "$MSG_FILE" ]; then
  echo "ERROR: COMMIT_MSG.txt not found." >&2
  exit 1
fi

# Remove the Chomp client file (rsync overlay cannot delete files).
git rm -f --ignore-unmatch Stocked/Nutrition/ChompFoodClient.swift >/dev/null 2>&1 || true

git add -A

if git diff --cached --quiet; then
  echo "Nothing to commit; working tree clean."
  exit 0
fi

git commit -F "$MSG_FILE"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin "$BRANCH"
fi

echo "Done."
