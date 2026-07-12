#!/usr/bin/env bash
# apply.sh - runs BEFORE commit.sh to handle relocations/deletions.
# BuildBuddy rsyncs only files present in the delta and cannot delete files,
# so removals must be performed explicitly here and recorded via git add -A.
set -euo pipefail

# ViewingProfileStore.swift is relocated from Services/ to App/ to match the
# location the Xcode project (App group) already expects. Remove the stale copy.
if [ -f "Astra/Services/ViewingProfileStore.swift" ]; then
  git rm -f --quiet "Astra/Services/ViewingProfileStore.swift" || rm -f "Astra/Services/ViewingProfileStore.swift"
  echo "Removed stale Astra/Services/ViewingProfileStore.swift"
else
  echo "No stale Astra/Services/ViewingProfileStore.swift to remove"
fi

git add -A
echo "apply.sh complete"
