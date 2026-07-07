#!/bin/bash
# Deletes stale duplicate files that are not compiled by the project. BuildBuddy
# rsyncs only files present in the delta, so deletions must happen here.
set -e
cd "$(dirname "$0")"

# Deep-nested stale AppEnvironment copy from an old restructure (the compiled copy
# lives at Astra/App/AppEnvironment.swift and is untouched).
rm -f "Astra/Astra/App/AppEnvironment.swift"
rmdir "Astra/Astra/App" 2>/dev/null || true
rmdir "Astra/Astra" 2>/dev/null || true

# Orphan duplicate of the Live TV sources view (the compiled copy lives at
# Astra/Views/LiveTV/LiveTVSourcesView.swift).
rm -f "Astra/Services/LiveTVSourcesView.swift"

echo "apply.sh: removed stale duplicate files."
