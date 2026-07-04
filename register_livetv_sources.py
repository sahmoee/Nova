#!/usr/bin/env python3
import re, uuid, os
here = os.path.dirname(os.path.abspath(__file__))
pbx = os.path.join(here, "FrameTV.xcodeproj", "project.pbxproj")
s = open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()
ls = re.search(r"([0-9A-F]{24}) /\* LibraryStore\.swift \*/ = \{isa = PBXFileReference", s)
if not ls: raise SystemExit(0)
fileref_ls = ls.group(1)
ltv = re.search(r"([0-9A-F]{24}) /\* LiveTVView\.swift \*/ = \{isa = PBXFileReference", s)
ltv_ref = ltv.group(1) if ltv else fileref_ls
bf_guids = re.findall(r"([0-9A-F]{24}) /\* LibraryStore\.swift in Sources \*/,", s)
files = [("LiveTVSourceStore.swift", fileref_ls, "LibraryStore.swift"),
         ("LiveTVSourcesView.swift", ltv_ref, "LiveTVView.swift")]
changed=False
for fname, sib_ref, sib_name in files:
    if f"{fname} in Sources" in s: continue
    changed=True
    fref = gen()
    anchor = f'\t\t{fileref_ls} /* LibraryStore.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LibraryStore.swift; sourceTree = "<group>"; }};\n'
    s = s.replace(anchor, anchor + f'\t\t{fref} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};\n', 1)
    sib = f'\t\t\t\t{sib_ref} /* {sib_name} */,\n'
    if sib in s: s = s.replace(sib, sib + f'\t\t\t\t{fref} /* {fname} */,\n', 1)
    for bf_old in bf_guids:
        bf_new = gen()
        da = f'\t\t{bf_old} /* LibraryStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref_ls} /* LibraryStore.swift */; }};\n'
        s = s.replace(da, da + f'\t\t{bf_new} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {fname} */; }};\n', 1)
        pa = f'\t\t\t\t{bf_old} /* LibraryStore.swift in Sources */,\n'
        s = s.replace(pa, pa + f'\t\t\t\t{bf_new} /* {fname} in Sources */,\n', 1)
if changed: open(pbx,"w").write(s); print("Registered Live TV files")
else: print("Already registered")
