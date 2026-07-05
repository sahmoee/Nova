#!/usr/bin/env python3
import re, uuid, os
here = os.path.dirname(os.path.abspath(__file__))
pbx = os.path.join(here, "Astra.xcodeproj", "project.pbxproj")
s = open(pbx).read()
def gen(): return uuid.uuid4().hex[:24].upper()
changed = False

# Haptics.swift belongs in the Utilities group (anchor LanguageNames.swift).
util = re.search(r"([0-9A-F]{24}) /\* LanguageNames\.swift \*/ = \{isa = PBXFileReference", s)
if util and "Haptics.swift in Sources" not in s:
    util_ref = util.group(1)
    bf = re.findall(r"([0-9A-F]{24}) /\* LanguageNames\.swift in Sources \*/,", s)
    fref = gen()
    a = f'\t\t{util_ref} /* LanguageNames.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LanguageNames.swift; sourceTree = "<group>"; }};\n'
    s = s.replace(a, a + f'\t\t{fref} /* Haptics.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Haptics.swift; sourceTree = "<group>"; }};\n', 1)
    g = f'\t\t\t\t{util_ref} /* LanguageNames.swift */,\n'
    s = s.replace(g, g + f'\t\t\t\t{fref} /* Haptics.swift */,\n', 1)
    for o in bf:
        n = gen()
        da = f'\t\t{o} /* LanguageNames.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {util_ref} /* LanguageNames.swift */; }};\n'
        s = s.replace(da, da + f'\t\t{n} /* Haptics.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* Haptics.swift */; }};\n', 1)
        pa = f'\t\t\t\t{o} /* LanguageNames.swift in Sources */,\n'
        s = s.replace(pa, pa + f'\t\t\t\t{n} /* Haptics.swift in Sources */,\n', 1)
    changed = True

# SkeletonGrid.swift belongs in the Components group (anchor MediaCard.swift).
mc = re.search(r"([0-9A-F]{24}) /\* MediaCard\.swift \*/ = \{isa = PBXFileReference", s)
if mc and "SkeletonGrid.swift in Sources" not in s:
    mc_ref = mc.group(1)
    bf = re.findall(r"([0-9A-F]{24}) /\* MediaCard\.swift in Sources \*/,", s)
    fref = gen()
    a = f'\t\t{mc_ref} /* MediaCard.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MediaCard.swift; sourceTree = "<group>"; }};\n'
    s = s.replace(a, a + f'\t\t{fref} /* SkeletonGrid.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SkeletonGrid.swift; sourceTree = "<group>"; }};\n', 1)
    g = f'\t\t\t\t{mc_ref} /* MediaCard.swift */,\n'
    s = s.replace(g, g + f'\t\t\t\t{fref} /* SkeletonGrid.swift */,\n', 1)
    for o in bf:
        n = gen()
        da = f'\t\t{o} /* MediaCard.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {mc_ref} /* MediaCard.swift */; }};\n'
        s = s.replace(da, da + f'\t\t{n} /* SkeletonGrid.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {fref} /* SkeletonGrid.swift */; }};\n', 1)
        pa = f'\t\t\t\t{o} /* MediaCard.swift in Sources */,\n'
        s = s.replace(pa, pa + f'\t\t\t\t{n} /* SkeletonGrid.swift in Sources */,\n', 1)
    changed = True

if changed: open(pbx,"w").write(s); print("Registered perf files")
else: print("Already registered")
