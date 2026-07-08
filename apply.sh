#!/usr/bin/env bash
# Run BEFORE commit.sh. Removes stale orphan duplicates that rsync cannot delete:
#  - Astra/Services/LiveTVSourcesView.swift (identical registered copy lives in
#    Astra/Views/LiveTV/; the Services copy is unregistered and unused)
#  - Astra/Utilities/Haptics.swift (unregistered; the compiled Haptics enum lives
#    in Astra/Components/Toast.swift)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
rm -f "Astra/Services/LiveTVSourcesView.swift"
rm -f "Astra/Utilities/Haptics.swift"
echo "apply.sh: removed stale orphan duplicates."
