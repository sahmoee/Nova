#!/usr/bin/env python3
import re, uuid, os
here=os.path.dirname(os.path.abspath(__file__))
pbx=os.path.join(here,"Nova.xcodeproj","project.pbxproj")
s=open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()
def register(s, fname, anchor):
    if f"{fname} in Sources" in s: return s, False
    ar=re.search(rf"([0-9A-F]{{24}}) /\* {re.escape(anchor)} \*/ = \{{isa = PBXFileReference", s)
    if not ar: return s, False
    aref=ar.group(1); bf=re.findall(rf"([0-9A-F]{{24}}) /\* {re.escape(anchor)} in Sources \*/,", s)
    fref=gen()
    a=f'\t\t{aref} /* {anchor} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {anchor}; sourceTree = "<group>"; }};\n'
    s=s.replace(a, a+f'\t\t{fref} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};\n',1)
    g=f'\t\t\t\t{aref} /* {anchor} */,\n'
    s=s.replace(g, g+f'\t\t\t\t{fref} /* {fname} */,\n',1)
    for o in bf:
        n=gen()
        da=f'\t\t{o} /* {anchor} in Sources */ = {{isa = PBXBuildFile; fileRef = {aref} /* {anchor} */; }};\n'
        s=s.replace(da, da+f'\t\t{n} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {fname} */; }};\n',1)
        pa=f'\t\t\t\t{o} /* {anchor} in Sources */,\n'
        s=s.replace(pa, pa+f'\t\t\t\t{n} /* {fname} in Sources */,\n',1)
    return s, True
changed=False
for fname, anchor in [("DownloadManager.swift","LibraryStore.swift"),
                      ("SkeletonGrid.swift","MediaCard.swift"),
                      ("CollectionPickerSheet.swift","LibraryView.swift")]:
    s, ch = register(s, fname, anchor); changed = changed or ch
    print(fname, "registered" if ch else "already present")
if changed: open(pbx,"w").write(s)
