#!/usr/bin/env python3
import re, uuid, os
here = os.path.dirname(os.path.abspath(__file__))
pbx = os.path.join(here, "Astra.xcodeproj", "project.pbxproj")
s = open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()

def register(s, fname, anchor_name):
    if f"{fname} in Sources" in s:
        return s, False
    ar = re.search(rf"([0-9A-F]{{24}}) /\* {re.escape(anchor_name)} \*/ = \{{isa = PBXFileReference", s)
    if not ar:
        return s, False
    aref = ar.group(1)
    bf = re.findall(rf"([0-9A-F]{{24}}) /\* {re.escape(anchor_name)} in Sources \*/,", s)
    fref = gen()
    a = f'\t\t{aref} /* {anchor_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {anchor_name}; sourceTree = "<group>"; }};\n'
    s = s.replace(a, a + f'\t\t{fref} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};\n', 1)
    g = f'\t\t\t\t{aref} /* {anchor_name} */,\n'
    s = s.replace(g, g + f'\t\t\t\t{fref} /* {fname} */,\n', 1)
    for o in bf:
        n = gen()
        da = f'\t\t{o} /* {anchor_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {aref} /* {anchor_name} */; }};\n'
        s = s.replace(da, da + f'\t\t{n} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* {fname} */; }};\n', 1)
        pa = f'\t\t\t\t{o} /* {anchor_name} in Sources */,\n'
        s = s.replace(pa, pa + f'\t\t\t\t{n} /* {fname} in Sources */,\n', 1)
    return s, True

changed = False
s, c1 = register(s, "DownloadManager.swift", "LibraryStore.swift")   # Services group
s, c2 = register(s, "SkeletonGrid.swift", "MediaCard.swift")          # Components group
changed = c1 or c2
if changed:
    open(pbx, "w").write(s)
print("DownloadManager:", "registered" if c1 else "already present")
print("SkeletonGrid:", "registered" if c2 else "already present")

# Ensure AppEnvironment creates the download manager.
env = os.path.join(here, "Astra", "App", "AppEnvironment.swift")
if os.path.exists(env):
    e = open(env).read()
    if "downloadManager" not in e and "let libraryEnricher = LibraryEnricher()" in e:
        e = e.replace("    let libraryEnricher = LibraryEnricher()\n",
                      "    let libraryEnricher = LibraryEnricher()\n    let downloadManager = DownloadManager()\n", 1)
        open(env, "w").write(e)
        print("AppEnvironment: wired downloadManager")
    else:
        print("AppEnvironment: already wired")
