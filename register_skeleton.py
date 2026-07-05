#!/usr/bin/env python3
import re, uuid, os
here=os.path.dirname(os.path.abspath(__file__))
pbx=os.path.join(here,"FrameTV.xcodeproj","project.pbxproj")
s=open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()
mc=re.search(r"([0-9A-F]{24}) /\* MediaCard\.swift \*/ = \{isa = PBXFileReference", s)
if mc and "SkeletonGrid.swift in Sources" not in s:
    mc=mc.group(1)
    bf=re.findall(r"([0-9A-F]{24}) /\* MediaCard\.swift in Sources \*/,", s)
    fref=gen()
    a=f'\t\t{mc} /* MediaCard.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MediaCard.swift; sourceTree = "<group>"; }};\n'
    s=s.replace(a, a+f'\t\t{fref} /* SkeletonGrid.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SkeletonGrid.swift; sourceTree = "<group>"; }};\n',1)
    g=f'\t\t\t\t{mc} /* MediaCard.swift */,\n'
    s=s.replace(g, g+f'\t\t\t\t{fref} /* SkeletonGrid.swift */,\n',1)
    for o in bf:
        n=gen()
        da=f'\t\t{o} /* MediaCard.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {mc} /* MediaCard.swift */; }};\n'
        s=s.replace(da, da+f'\t\t{n} /* SkeletonGrid.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* SkeletonGrid.swift */; }};\n',1)
        pa=f'\t\t\t\t{o} /* MediaCard.swift in Sources */,\n'
        s=s.replace(pa, pa+f'\t\t\t\t{n} /* SkeletonGrid.swift in Sources */,\n',1)
    open(pbx,"w").write(s); print("Registered SkeletonGrid")
else: print("Already registered")
