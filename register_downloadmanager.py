#!/usr/bin/env python3
import re, uuid, os
here = os.path.dirname(os.path.abspath(__file__))
pbx = os.path.join(here, "FrameTV.xcodeproj", "project.pbxproj")
s = open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()
# Remove any stray Haptics.swift project references (the duplicate file is deleted).
for m in re.findall(r"([0-9A-F]{24}) /\* Haptics\.swift \*/ = \{isa = PBXFileReference", s):
    s = re.sub(rf"\t\t{m} /\* Haptics\.swift \*/ = \{{isa = PBXFileReference;[^\n]*\n", "", s)
    s = re.sub(rf"\t\t\t\t{m} /\* Haptics\.swift \*/,\n", "", s)
for m in re.findall(r"([0-9A-F]{24}) /\* Haptics\.swift in Sources \*/ = \{isa = PBXBuildFile", s):
    s = re.sub(rf"\t\t{m} /\* Haptics\.swift in Sources \*/ = \{{isa = PBXBuildFile;[^\n]*\n", "", s)
    s = re.sub(rf"\t\t\t\t{m} /\* Haptics\.swift in Sources \*/,\n", "", s)
# Register DownloadManager in the Services group (anchor LibraryStore).
ls = re.search(r"([0-9A-F]{24}) /\* LibraryStore\.swift \*/ = \{isa = PBXFileReference", s)
if ls and "DownloadManager.swift in Sources" not in s:
    ls = ls.group(1)
    bf = re.findall(r"([0-9A-F]{24}) /\* LibraryStore\.swift in Sources \*/,", s)
    fref = gen()
    a = f'\t\t{ls} /* LibraryStore.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LibraryStore.swift; sourceTree = "<group>"; }};\n'
    s = s.replace(a, a + f'\t\t{fref} /* DownloadManager.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DownloadManager.swift; sourceTree = "<group>"; }};\n', 1)
    g = f'\t\t\t\t{ls} /* LibraryStore.swift */,\n'
    s = s.replace(g, g + f'\t\t\t\t{fref} /* DownloadManager.swift */,\n', 1)
    for o in bf:
        n = gen()
        da = f'\t\t{o} /* LibraryStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ls} /* LibraryStore.swift */; }};\n'
        s = s.replace(da, da + f'\t\t{n} /* DownloadManager.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* DownloadManager.swift */; }};\n', 1)
        pa = f'\t\t\t\t{o} /* LibraryStore.swift in Sources */,\n'
        s = s.replace(pa, pa + f'\t\t\t\t{n} /* DownloadManager.swift in Sources */,\n', 1)
open(pbx,"w").write(s); print("Done")
