#!/usr/bin/env python3
import re, uuid, os
here=os.path.dirname(os.path.abspath(__file__))
pbx=os.path.join(here,"Nova.xcodeproj","project.pbxproj")
s=open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()
ls=re.search(r"([0-9A-F]{24}) /\* LibraryStore\.swift \*/ = \{isa = PBXFileReference", s)
if ls and "DownloadManager.swift in Sources" not in s:
    ls=ls.group(1)
    bf=re.findall(r"([0-9A-F]{24}) /\* LibraryStore\.swift in Sources \*/,", s)
    fref=gen()
    a=f'\t\t{ls} /* LibraryStore.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LibraryStore.swift; sourceTree = "<group>"; }};\n'
    s=s.replace(a, a+f'\t\t{fref} /* DownloadManager.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DownloadManager.swift; sourceTree = "<group>"; }};\n',1)
    g=f'\t\t\t\t{ls} /* LibraryStore.swift */,\n'
    s=s.replace(g, g+f'\t\t\t\t{fref} /* DownloadManager.swift */,\n',1)
    for o in bf:
        n=gen()
        da=f'\t\t{o} /* LibraryStore.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ls} /* LibraryStore.swift */; }};\n'
        s=s.replace(da, da+f'\t\t{n} /* DownloadManager.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* DownloadManager.swift */; }};\n',1)
        pa=f'\t\t\t\t{o} /* LibraryStore.swift in Sources */,\n'
        s=s.replace(pa, pa+f'\t\t\t\t{n} /* DownloadManager.swift in Sources */,\n',1)
    open(pbx,"w").write(s); print("Registered DownloadManager")
else: print("Already registered")
