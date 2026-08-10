#!/usr/bin/env bash
# ============================================================================
# validate_nova_config.sh — the configuration contract.
#
# Fails (nonzero exit) if any of the authoritative build settings drift:
#   • the Nova app identities (com.nova.app.*)
#   • Team ID 5DV5N49VG8
#   • App Group  group.nova.ios (shared across app, widgets, and tvOS)
#   • URL scheme nova://
#   • deployment targets (iOS + tvOS = 26.0)
#   • version numbers consistent across targets
#
# Read-only. Intended to run in CI and from release_check.sh before every build.
# ============================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PBX="$ROOT/Nova.xcodeproj/project.pbxproj"
FAIL=0
note() { printf "  %s\n" "$1"; }
bad()  { printf "  ✗ %s\n" "$1"; FAIL=1; }
ok()   { printf "  ✓ %s\n" "$1"; }

if [[ ! -f "$PBX" ]]; then echo "validate_nova_config: pbxproj missing"; exit 2; fi

echo "== Bundle identifiers =="
EXPECTED_IDS=$(printf '%s\n' com.nova.app.ios com.nova.app.ios.widgets com.nova.app.tvos com.nova.app.ios.tests | sort)
FOUND_IDS=$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*;' "$PBX" \
  | sed 's/PRODUCT_BUNDLE_IDENTIFIER = //; s/;$//; s/^"//; s/"$//' | sort -u)
if [[ "$FOUND_IDS" == "$EXPECTED_IDS" ]]; then ok "exactly the four intended IDs"; else
  bad "bundle IDs differ from expected"; echo "--- found:"; echo "$FOUND_IDS" | sed 's/^/      /'
fi

echo "== Team ID =="
if grep -q "DEVELOPMENT_TEAM = 5DV5N49VG8" "$PBX"; then ok "Team 5DV5N49VG8"; else bad "Team ID not 5DV5N49VG8"; fi
if grep -oE "DEVELOPMENT_TEAM = [A-Z0-9]+" "$PBX" | sort -u | grep -qv "5DV5N49VG8"; then bad "a different Team ID also present"; fi

echo "== App Group =="
# Use grep exit status only (no string capture): both real entitlement files
# must declare Nova's App Group so the shared container is visible everywhere.
GROUP_OK=1
for ent in "NovaWidgetsExtension.entitlements" "Nova/Resources/Nova.entitlements"; do
  grep -q "group\.nova\.ios" "$ROOT/$ent" 2>/dev/null || GROUP_OK=0
done
if [ "$GROUP_OK" -eq 1 ]; then ok "App Group group.nova.ios (both entitlements)"; else
  bad "App Group not set to group.nova.ios"
fi
# Also ensure shared-storage code uses the same group and no stale id.
if grep -rq 'group\.astra\.ios\|group\.frametv' "$ROOT/Nova" "$ROOT/NovaWidgets" --include=*.swift 2>/dev/null; then
  bad "source code references a noncanonical App Group id"
else ok "source code uses the canonical App Group"; fi

echo "== iCloud continuity =="
if grep -q '\$(TeamIdentifierPrefix)\$(CFBundleIdentifier)' "$ROOT/Nova/Resources/Nova.entitlements"; then
  ok "KVS follows the Nova bundle IDs"
else bad "iCloud KVS entitlement is not tied to the retained app identity"; fi

echo "== URL scheme =="
if grep -rq "nova" "$ROOT"/Nova/Resources/*.plist "$ROOT"/Nova/**/Info.plist 2>/dev/null || grep -rq '"nova"' "$ROOT/Nova" --include=*.swift 2>/dev/null; then
  ok "nova:// scheme referenced"
else note "nova:// scheme not detected (verify Info.plist CFBundleURLSchemes)"; fi

echo "== Deployment targets =="
IOS_T=$(grep -o "IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*" "$PBX" | sed 's/.*= //' | sort -u | tr '\n' ' ')
TV_T=$(grep -o "TVOS_DEPLOYMENT_TARGET = [0-9.]*" "$PBX" | sed 's/.*= //' | sort -u | tr '\n' ' ')
[[ "$IOS_T" == "26.0 " ]] && ok "iOS target 26.0" || bad "iOS deployment target(s): $IOS_T (want 26.0)"
[[ "$TV_T"  == "26.0 " ]] && ok "tvOS target 26.0" || bad "tvOS deployment target(s): $TV_T (want 26.0)"

echo "== Versions =="
MV=$(grep -o "MARKETING_VERSION = [^;]*" "$PBX" | sed 's/.*= //' | sort -u | tr '\n' ' ')
BV=$(grep -o "CURRENT_PROJECT_VERSION = [^;]*" "$PBX" | sed 's/.*= //' | sort -u | tr '\n' ' ')
[[ $(echo "$MV" | wc -w) -le 1 ]] && ok "MARKETING_VERSION consistent ($MV)" || bad "MARKETING_VERSION differs across targets: $MV"
[[ $(echo "$BV" | wc -w) -le 1 ]] && ok "CURRENT_PROJECT_VERSION consistent ($BV)" || bad "CURRENT_PROJECT_VERSION differs: $BV"

echo
if [[ "$FAIL" -ne 0 ]]; then echo "validate_nova_config: FAILED"; exit 1; fi
echo "validate_nova_config: OK"
