#!/usr/bin/env python3
import re, sys, uuid

PBX = "Astra.xcodeproj/project.pbxproj"
FILES = [
    ("MenuOverlay.swift", "RootView.swift"),
    ("SkeletonGrid.swift", "MediaCard.swift"),
    ("CollectionPickerSheet.swift", "CollectionsView.swift"),
]

def mkid():
    return uuid.uuid4().hex[:24].upper()

src = open(PBX).read()

def already_registered(name):
    return re.search(r'/\* ' + re.escape(name) + r'(?: in Sources)? \*/', src) is not None

for fname, anchor in FILES:
    if already_registered(fname):
        print(f"SKIP {fname}: already registered"); continue
    file_ref = mkid(); ios_build = mkid(); tvos_build = mkid(); ids = [ios_build, tvos_build]

    ref_pat = re.compile(r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) +
        r' \*/ = \{isa = PBXFileReference;[^\n]*\};\n)')
    m = ref_pat.search(src)
    if not m: sys.exit(f"ERROR: file-ref anchor {anchor} not found for {fname}")
    src = src[:m.end(1)] + (f'\t\t{file_ref} /* {fname} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};\n') + src[m.end(1):]

    bf_pat = re.compile(r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) +
        r' in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* ' +
        re.escape(anchor) + r' \*/; \};\n)')
    bfs = list(bf_pat.finditer(src))
    if len(bfs) < 2: sys.exit(f"ERROR: expected 2 build-file anchors for {anchor}, found {len(bfs)}")
    for i, mm in enumerate(bfs[:2][::-1]):
        bid = ids[::-1][i]
        src = src[:mm.end(1)] + (f'\t\t{bid} /* {fname} in Sources */ = '
            f'{{isa = PBXBuildFile; fileRef = {file_ref} /* {fname} */; }};\n') + src[mm.end(1):]

    child_pat = re.compile(r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) + r' \*/,\n)')
    cm = child_pat.search(src)
    if not cm: sys.exit(f"ERROR: group child anchor {anchor} not found for {fname}")
    src = src[:cm.end(1)] + f'\t\t\t\t{file_ref} /* {fname} */,\n' + src[cm.end(1):]

    phase_pat = re.compile(r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) + r' in Sources \*/,\n)')
    pms = list(phase_pat.finditer(src))
    if len(pms) < 2: sys.exit(f"ERROR: expected 2 phase anchors for {anchor}, found {len(pms)}")
    for i, mm in enumerate(pms[:2][::-1]):
        pid = ids[::-1][i]
        src = src[:mm.end(1)] + f'\t\t\t\t{pid} /* {fname} in Sources */,\n' + src[mm.end(1):]

    print(f"REGISTERED {fname}")

open(PBX, "w").write(src)
print("Done.")
