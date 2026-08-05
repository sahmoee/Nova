#!/usr/bin/env python3
# Self-healing registration for SkeletonGrid.swift (Components) and
# CollectionPickerSheet.swift (Views/Library) across iOS + tvOS targets.
import re, sys, uuid

PBX = "Nova.xcodeproj/project.pbxproj"

def mkid():
    return uuid.uuid4().hex[:24].upper()

with open(PBX) as f:
    src = f.read()

# (filename, group_anchor_basename, group_sourcetree)
files = [
    ("SkeletonGrid.swift", "MediaCard.swift"),
    ("CollectionPickerSheet.swift", "CollectionsView.swift"),
]

for fname, group_anchor in files:
    if fname in src:
        print(f"SKIP {fname}: already registered")
        continue

    file_ref = mkid()
    ios_build = mkid()
    tvos_build = mkid()

    # 1) PBXFileReference — anchor on group_anchor's file reference line
    ref_pat = re.compile(
        r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(group_anchor) +
        r' \*/ = \{isa = PBXFileReference;[^\n]*\};\n)')
    m = ref_pat.search(src)
    if not m:
        sys.exit(f"ERROR: file reference anchor {group_anchor} not found")
    new_ref = (f'\t\t{file_ref} /* {fname} */ = '
               f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
               f'path = {fname}; sourceTree = "<group>"; }};\n')
    src = src[:m.end(1)] + new_ref + src[m.end(1):]

    # 2) Two PBXBuildFile entries — anchor on the two group_anchor build-file lines
    bf_pat = re.compile(
        r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(group_anchor) +
        r' in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* ' +
        re.escape(group_anchor) + r' \*/; \};\n)')
    bf_matches = list(bf_pat.finditer(src))
    if len(bf_matches) < 2:
        sys.exit(f"ERROR: expected 2 build-file anchors for {group_anchor}, found {len(bf_matches)}")
    # insert after each of the first two, from last to first to preserve offsets
    build_ids = [ios_build, tvos_build]
    for i, mm in enumerate(bf_matches[:2][::-1]):
        bid = build_ids[::-1][i]
        line = (f'\t\t{bid} /* {fname} in Sources */ = '
                f'{{isa = PBXBuildFile; fileRef = {file_ref} /* {fname} */; }};\n')
        src = src[:mm.end(1)] + line + src[mm.end(1):]

    # 3) Group children — anchor on group_anchor's child line
    child_pat = re.compile(
        r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(group_anchor) + r' \*/,\n)')
    cm = child_pat.search(src)
    if not cm:
        sys.exit(f"ERROR: group child anchor {group_anchor} not found")
    child_line = f'\t\t\t\t{file_ref} /* {fname} */,\n'
    src = src[:cm.end(1)] + child_line + src[cm.end(1):]

    # 4) Two Sources build phases — anchor on the two group_anchor "in Sources" phase lines
    phase_pat = re.compile(
        r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(group_anchor) + r' in Sources \*/,\n)')
    pm = list(phase_pat.finditer(src))
    if len(pm) < 2:
        sys.exit(f"ERROR: expected 2 phase anchors for {group_anchor}, found {len(pm)}")
    phase_ids = [ios_build, tvos_build]
    for i, mm in enumerate(pm[:2][::-1]):
        pid = phase_ids[::-1][i]
        pline = f'\t\t\t\t{pid} /* {fname} in Sources */,\n'
        src = src[:mm.end(1)] + pline + src[mm.end(1):]

    print(f"REGISTERED {fname} (fileRef={file_ref}, iOS={ios_build}, tvOS={tvos_build})")

with open(PBX, "w") as f:
    f.write(src)
print("Done.")
