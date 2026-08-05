#!/usr/bin/env python3
"""Registers Batch 1's new Swift files in Nova.xcodeproj (idempotent, self-healing).

New files:
  Nova/Utilities/AppCore.swift
  Nova/Utilities/CloudBackedStore.swift
  Nova/Utilities/DiskJSONCache.swift
  Nova/Views/Player/PlayerCore.swift

For each file: 1 PBXFileReference, 1 group-children entry (anchored to a sibling),
2 PBXBuildFile defs, 2 Sources-phase entries (iOS + tvOS app targets).
Run from the repo root: python3 register_batch1.py
"""
import hashlib, pathlib, re, sys

PBX = pathlib.Path("Nova.xcodeproj/project.pbxproj")
FILES = [
    # (filename, group-sibling anchor, sources-phase sibling anchor)
    ("AppCore.swift",          "DateFormatting.swift", "DateFormatting.swift"),
    ("CloudBackedStore.swift", "DateFormatting.swift", "DateFormatting.swift"),
    ("DiskJSONCache.swift",    "DateFormatting.swift", "DateFormatting.swift"),
    ("PlayerCore.swift",       "PlayerModel.swift",    "PlayerModel.swift"),
]

def hid(seed):
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()

def main():
    s = PBX.read_text()
    changed = False
    for name, group_anchor, src_anchor in FILES:
        ref = hid(name + ":ref")
        bf1 = hid(name + ":build1")
        bf2 = hid(name + ":build2")

        if f"/* {name} */ = {{isa = PBXFileReference" not in s:
            anchor_ref = re.search(
                r"\n(\t\t[0-9A-F]{24} /\* " + re.escape(group_anchor) +
                r" \*/ = \{isa = PBXFileReference[^\n]*\n)", s)
            if not anchor_ref:
                sys.exit(f"anchor fileref not found for {name}")
            line = (f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; "
                    f"lastKnownFileType = sourcecode.swift; path = {name}; "
                    f"sourceTree = \"<group>\"; }};\n")
            s = s.replace(anchor_ref.group(1), anchor_ref.group(1) + line, 1)
            changed = True

        childline = f"\t\t\t\t{ref} /* {name} */,\n"
        if childline not in s:
            m = re.search(r"(\t\t\t\t[0-9A-F]{24} /\* " + re.escape(group_anchor) + r" \*/,\n)", s)
            if not m:
                sys.exit(f"group anchor not found for {name}")
            s = s.replace(m.group(1), m.group(1) + childline, 1)
            changed = True

        for bf in (bf1, bf2):
            if f"{bf} /* {name} in Sources */ = {{isa = PBXBuildFile" not in s:
                first = re.search(
                    r"(\t\t[0-9A-F]{24} /\* " + re.escape(name) +
                    r" in Sources \*/ = \{isa = PBXBuildFile[^\n]*\n)|(\t\t[0-9A-F]{24} /\* NovaApp.swift in Sources \*/ = \{isa = PBXBuildFile[^\n]*\n)", s)
                line = (f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; "
                        f"fileRef = {ref} /* {name} */; }};\n")
                anchor = first.group(0)
                s = s.replace(anchor, anchor + line, 1)
                changed = True

        # Sources phase entries: add next to each of the two anchor entries.
        phase_anchors = re.findall(
            r"(\t\t\t\t[0-9A-F]{24} /\* " + re.escape(src_anchor) + r" in Sources \*/,\n)", s)
        if len(phase_anchors) < 2:
            sys.exit(f"sources anchors not found for {name}")
        for i, bf in enumerate((bf1, bf2)):
            entry = f"\t\t\t\t{bf} /* {name} in Sources */,\n"
            if entry not in s:
                s = s.replace(phase_anchors[i], phase_anchors[i] + entry, 1)
                changed = True

    if changed:
        PBX.write_text(s)
        print("pbxproj updated")
    else:
        print("pbxproj already up to date")

if __name__ == "__main__":
    main()
