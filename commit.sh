#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSG_FILE="$SCRIPT_DIR/COMMIT_MSG.txt"
if [[ ! -f "$MSG_FILE" ]]; then echo "error: COMMIT_MSG.txt not found." >&2; exit 1; fi
if ! REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "error: not inside a git repository." >&2; exit 1; fi
cd "$REPO_ROOT"; git add -A
if git diff --cached --quiet; then echo "Nothing staged to commit. Done."; exit 0; fi
git commit -F "$MSG_FILE"; echo "Committed."
if [[ "${1:-}" == "--push" ]]; then shift
  if [[ $# -ge 2 ]]; then git push "$1" "$2"
  else BRANCH="$(git rev-parse --abbrev-ref HEAD)"; git push 2>/dev/null || git push -u origin "$BRANCH"; fi
  echo "Push complete."; fi
