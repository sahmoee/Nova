#!/usr/bin/env python3
"""Registers Batch 3's new Swift file (EPGService.swift) in Astra.xcodeproj.
Idempotent; run from the repo root: python3 register_batch3.py"""
import hashlib, pathlib, re, sys

PBX = pathlib.Path("Astra.xcodeproj/project.pbxproj")
FILES = [("EPGService.swift", "LiveTVSourceStore.swift", "LiveTVSourceStore.swift")]

def hid(seed):
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()

def main():
    s = PBX.read_text()
    changed = False
    for name, group_anchor, src_anchor in FILES:
        ref = hid(name + ":ref"); bf1 = hid(name + ":build1"); bf2 = hid(name + ":build2")
        if f"/* {name} */ = {{isa = PBXFileReference" not in s:
            m = re.search(r"\n(\t\t[0-9A-F]{24} /\* " + re.escape(group_anchor) +
                          r" \*/ = \{isa = PBXFileReference[^\n]*\n)", s)
            if not m: sys.exit("anchor fileref not found")
            line = (f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; "
                    f"lastKnownFileType = sourcecode.swift; path = {name}; "
                    f"sourceTree = \"<group>\"; }};\n")
            s = s.replace(m.group(1), m.group(1) + line, 1); changed = True
        child = f"\t\t\t\t{ref} /* {name} */,\n"
        if child not in s:
            m = re.search(r"(\t\t\t\t[0-9A-F]{24} /\* " + re.escape(group_anchor) + r" \*/,\n)", s)
            if not m: sys.exit("group anchor not found")
            s = s.replace(m.group(1), m.group(1) + child, 1); changed = True
        for bf in (bf1, bf2):
            if f"{bf} /* {name} in Sources */ = {{isa = PBXBuildFile" not in s:
                m = re.search(r"(\t\t[0-9A-F]{24} /\* AstraApp.swift in Sources \*/ = \{isa = PBXBuildFile[^\n]*\n)", s)
                line = (f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; "
                        f"fileRef = {ref} /* {name} */; }};\n")
                s = s.replace(m.group(1), m.group(1) + line, 1); changed = True
        anchors = re.findall(r"(\t\t\t\t[0-9A-F]{24} /\* " + re.escape(src_anchor) + r" in Sources \*/,\n)", s)
        if len(anchors) < 2: sys.exit("sources anchors not found")
        for i, bf in enumerate((bf1, bf2)):
            entry = f"\t\t\t\t{bf} /* {name} in Sources */,\n"
            if entry not in s:
                s = s.replace(anchors[i], anchors[i] + entry, 1); changed = True
    if changed:
        PBX.write_text(s); print("pbxproj updated")
    else:
        print("pbxproj already up to date")

if __name__ == "__main__":
    main()
