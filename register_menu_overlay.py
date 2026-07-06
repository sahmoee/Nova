#!/usr/bin/env python3
# Self-healing registration for MenuOverlay.swift (Views group) across iOS + tvOS.
# Anchors on RootView.swift, which lives in the same Views group and both targets.
import re, sys, uuid

PBX = "Astra.xcodeproj/project.pbxproj"
FNAME = "MenuOverlay.swift"
ANCHOR = "RootView.swift"

def mkid():
    return uuid.uuid4().hex[:24].upper()

src = open(PBX).read()

# Whole-file guard: treat only exact "/* MenuOverlay.swift" tokens (not TVMenuOverlay).
already = re.search(r'/\* ' + re.escape(FNAME) + r'(?: in Sources)? \*/', src)
if already:
    print(f"SKIP {FNAME}: already registered")
    sys.exit(0)

file_ref = mkid(); ios_build = mkid(); tvos_build = mkid()

# 1) PBXFileReference after the anchor's file-reference line.
ref_pat = re.compile(
    r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(ANCHOR) +
    r' \*/ = \{isa = PBXFileReference;[^\n]*\};\n)')
m = ref_pat.search(src)
if not m: sys.exit("ERROR: file-ref anchor not found")
src = src[:m.end(1)] + (
    f'\t\t{file_ref} /* {FNAME} */ = {{isa = PBXFileReference; '
    f'lastKnownFileType = sourcecode.swift; path = {FNAME}; sourceTree = "<group>"; }};\n'
) + src[m.end(1):]

# 2) Two PBXBuildFile entries after the anchor's two build-file lines.
bf_pat = re.compile(
    r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(ANCHOR) +
    r' in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* ' +
    re.escape(ANCHOR) + r' \*/; \};\n)')
bfs = list(bf_pat.finditer(src))
if len(bfs) < 2: sys.exit(f"ERROR: expected 2 build-file anchors, found {len(bfs)}")
ids = [ios_build, tvos_build]
for i, mm in enumerate(bfs[:2][::-1]):
    bid = ids[::-1][i]
    line = (f'\t\t{bid} /* {FNAME} in Sources */ = '
            f'{{isa = PBXBuildFile; fileRef = {file_ref} /* {FNAME} */; }};\n')
    src = src[:mm.end(1)] + line + src[mm.end(1):]

# 3) Group children entry after the anchor's child line.
child_pat = re.compile(r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(ANCHOR) + r' \*/,\n)')
cm = child_pat.search(src)
if not cm: sys.exit("ERROR: group child anchor not found")
src = src[:cm.end(1)] + f'\t\t\t\t{file_ref} /* {FNAME} */,\n' + src[cm.end(1):]

# 4) Two Sources build-phase entries after the anchor's two phase lines.
phase_pat = re.compile(r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(ANCHOR) + r' in Sources \*/,\n)')
pms = list(phase_pat.finditer(src))
if len(pms) < 2: sys.exit(f"ERROR: expected 2 phase anchors, found {len(pms)}")
for i, mm in enumerate(pms[:2][::-1]):
    pid = ids[::-1][i]
    src = src[:mm.end(1)] + f'\t\t\t\t{pid} /* {FNAME} in Sources */,\n' + src[mm.end(1):]

open(PBX, "w").write(src)
print(f"REGISTERED {FNAME} (fileRef={file_ref}, iOS={ios_build}, tvOS={tvos_build})")
