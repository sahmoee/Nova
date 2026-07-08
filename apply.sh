#!/usr/bin/env bash
# Run BEFORE commit.sh.
#  - Components/Polish.swift: contents merged into App/Theme.swift (register_batch4.py
#    removes its project references; this removes the file).
#  - Astra/Astra/App/AppEnvironment.swift: stale unregistered duplicate of
#    Astra/App/AppEnvironment.swift left in a nested folder.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
rm -f "Astra/Components/Polish.swift"
rm -f "Astra/Astra/App/AppEnvironment.swift"
rmdir "Astra/Astra/App" 2>/dev/null || true
rmdir "Astra/Astra" 2>/dev/null || true
python3 register_batch4.py
echo "apply.sh: removed merged/stale files and updated project references."
