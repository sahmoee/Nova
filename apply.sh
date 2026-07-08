#!/usr/bin/env bash
# Combined delta (all four batches + hotfix). Run BEFORE commit.sh.
# Removes files whose contents moved elsewhere or that were stale orphans, then
# self-heals the Xcode project registration for all new source files.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
rm -f "Astra/Services/LiveTVSourcesView.swift"   # orphan duplicate (registered copy: Views/LiveTV)
rm -f "Astra/Utilities/Haptics.swift"            # orphan duplicate (compiled enum lives in Toast.swift)
rm -f "Astra/Components/Polish.swift"            # merged into App/Theme.swift
rm -f "Astra/Astra/App/AppEnvironment.swift"     # stale nested duplicate
rmdir "Astra/Astra/App" 2>/dev/null || true
rmdir "Astra/Astra" 2>/dev/null || true
python3 register_batch1.py
python3 register_batch3.py
python3 register_batch4.py
echo "apply.sh: cleanup and project registration complete."
