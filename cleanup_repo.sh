#!/usr/bin/env bash
# ============================================================================
# cleanup_repo.sh — purge repository pollution.
#
# Run this on your Mac. (The Cowork sandbox mount is unlink-restricted, so these
# files can only be REMOVED here, not from inside the assistant environment.)
#
# Removes: AppleDouble ._* files, .DS_Store, and stray temp/bak
# files. Safe: touches nothing tracked as real source.
# ============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

echo "Cleaning repository pollution under: $ROOT"
c_ad=$(find . -name '._*' -not -path './.git/*' | wc -l | tr -d ' ')
c_ds=$(find . -name '.DS_Store' -not -path './.git/*' | wc -l | tr -d ' ')

find . -name '._*'        -not -path './.git/*' -delete 2>/dev/null
find . -name '.DS_Store'  -not -path './.git/*' -delete 2>/dev/null
find . -name '*.bak.*'    -not -path './.git/*' -delete 2>/dev/null
find . -name '_deltest.tmp' -not -path './.git/*' -delete 2>/dev/null

echo "Removed: $c_ad AppleDouble and $c_ds .DS_Store file(s)."
echo "Remaining AppleDouble: $(find . -name '._*' -not -path './.git/*' | wc -l | tr -d ' ')"
echo "Done. Consider committing the cleanup."
