#!/usr/bin/env python3
import re, sys, uuid
PBX = "Nova.xcodeproj/project.pbxproj"
# Register DateFormatting.swift in the Utilities group (anchor on an existing
# Utilities file). Find a suitable anchor dynamically.
FNAME = "DateFormatting.swift"

def mkid(): return uuid.uuid4().hex[:24].upper()
src = open(PBX).read()

if re.search(r'/\* ' + re.escape(FNAME) + r'(?: in Sources)? \*/', src):
    print(f"SKIP {FNAME}: already registered"); sys.exit(0)

# Pick an anchor that is a file in the Utilities group. Look for the Utilities
# group block and grab its first child .swift file.
m = re.search(r'/\* Utilities \*/ = \{\s*isa = PBXGroup;\s*children = \(\s*([0-9A-F]{24}) /\* ([^*]+?) \*/,', src)
if not m:
    sys.exit("ERROR: could not find a Utilities group anchor")
anchor = m.group(2).strip()
print(f"Using Utilities anchor: {anchor}")

file_ref = mkid(); ios_build = mkid(); tvos_build = mkid(); ids=[ios_build,tvos_build]

ref_pat = re.compile(r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) +
    r' \*/ = \{isa = PBXFileReference;[^\n]*\};\n)')
mm = ref_pat.search(src)
if not mm: sys.exit(f"ERROR: file-ref anchor {anchor} not found")
src = src[:mm.end(1)] + (f'\t\t{file_ref} /* {FNAME} */ = {{isa = PBXFileReference; '
    f'lastKnownFileType = sourcecode.swift; path = {FNAME}; sourceTree = "<group>"; }};\n') + src[mm.end(1):]

bf_pat = re.compile(r'(\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) +
    r' in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) /\* ' +
    re.escape(anchor) + r' \*/; \};\n)')
bfs=list(bf_pat.finditer(src))
if len(bfs)<2: sys.exit(f"ERROR: expected 2 build-file anchors for {anchor}, found {len(bfs)}")
for i,x in enumerate(bfs[:2][::-1]):
    bid=ids[::-1][i]
    src=src[:x.end(1)]+(f'\t\t{bid} /* {FNAME} in Sources */ = '
        f'{{isa = PBXBuildFile; fileRef = {file_ref} /* {FNAME} */; }};\n')+src[x.end(1):]

child_pat=re.compile(r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) + r' \*/,\n)')
cm=child_pat.search(src)
if not cm: sys.exit(f"ERROR: group child anchor {anchor} not found")
src=src[:cm.end(1)]+f'\t\t\t\t{file_ref} /* {FNAME} */,\n'+src[cm.end(1):]

phase_pat=re.compile(r'(\t\t\t\t([0-9A-F]{24}) /\* ' + re.escape(anchor) + r' in Sources \*/,\n)')
pms=list(phase_pat.finditer(src))
if len(pms)<2: sys.exit(f"ERROR: expected 2 phase anchors for {anchor}, found {len(pms)}")
for i,x in enumerate(pms[:2][::-1]):
    pid=ids[::-1][i]
    src=src[:x.end(1)]+f'\t\t\t\t{pid} /* {FNAME} in Sources */,\n'+src[x.end(1):]

open(PBX,"w").write(src)
print(f"REGISTERED {FNAME}")
