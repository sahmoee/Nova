#!/usr/bin/env bash
# Bumps the app version and build number together by 1, across all targets.
#
# Single source of truth: the Xcode project (MARKETING_VERSION and
# CURRENT_PROJECT_VERSION). Both the iOS and tvOS targets read these, and the app
# reads them at runtime, so the What's New screen, both Xcode targets, and the
# version shown in the app all stay in lockstep automatically.
#
# Run this once per build or fix (commit.sh calls it for you). It increments both
# numbers by 1 and writes them back to every target configuration.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PBX="FrameTV.xcodeproj/project.pbxproj"
if [[ ! -f "$PBX" ]]; then
  echo "error: project file not found at $PBX" >&2
  exit 1
fi

# Read the current values (first occurrence; all occurrences are kept identical).
CUR_VERSION="$(grep -o 'MARKETING_VERSION = [0-9][0-9]*' "$PBX" | head -1 | grep -o '[0-9][0-9]*')"
CUR_BUILD="$(grep -o 'CURRENT_PROJECT_VERSION = [0-9][0-9]*' "$PBX" | head -1 | grep -o '[0-9][0-9]*')"

if [[ -z "$CUR_VERSION" || -z "$CUR_BUILD" ]]; then
  echo "error: could not read current version or build from the project" >&2
  exit 1
fi

NEW_VERSION=$((CUR_VERSION + 1))
NEW_BUILD=$((CUR_BUILD + 1))

# Replace every occurrence in every target configuration.
sed -i.bak \
  -e "s/MARKETING_VERSION = [0-9][0-9]*/MARKETING_VERSION = ${NEW_VERSION}/g" \
  -e "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*/CURRENT_PROJECT_VERSION = ${NEW_BUILD}/g" \
  "$PBX"
rm -f "${PBX}.bak"

echo "Version ${CUR_VERSION} to ${NEW_VERSION}"
echo "Build ${CUR_BUILD} to ${NEW_BUILD}"
echo "VERSION=${NEW_VERSION}"
echo "BUILD=${NEW_BUILD}"
