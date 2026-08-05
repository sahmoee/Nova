#!/usr/bin/env python3
"""Register Apple TV rehaul Swift sources in both Nova app targets."""
import os
import re
import uuid

ROOT = os.path.dirname(os.path.abspath(__file__))
PBX = os.path.join(ROOT, "Nova.xcodeproj", "project.pbxproj")
text = open(PBX, encoding="utf-8").read()


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


def register(source: str, anchor: str) -> bool:
    global text
    if f"{source} in Sources" in text:
        return False

    anchor_match = re.search(
        rf"([0-9A-F]{{24}}) /\* {re.escape(anchor)} \*/ = \{{isa = PBXFileReference",
        text,
    )
    if not anchor_match:
        raise RuntimeError(f"Anchor not found: {anchor}")

    anchor_ref = anchor_match.group(1)
    build_refs = re.findall(
        rf"([0-9A-F]{{24}}) /\* {re.escape(anchor)} in Sources \*/,", text
    )
    if len(build_refs) != 2:
        raise RuntimeError(f"Expected two target memberships for {anchor}, found {len(build_refs)}")

    file_ref = uid()
    anchor_def = (
        f'\t\t{anchor_ref} /* {anchor} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = {anchor}; sourceTree = "<group>"; }};\n'
    )
    file_def = (
        f'\t\t{file_ref} /* {source} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = {source}; sourceTree = "<group>"; }};\n'
    )
    if anchor_def not in text:
        raise RuntimeError(f"Exact anchor definition not found: {anchor}")
    text = text.replace(anchor_def, anchor_def + file_def, 1)

    group_line = f"\t\t\t\t{anchor_ref} /* {anchor} */,\n"
    if group_line not in text:
        raise RuntimeError(f"Group entry not found: {anchor}")
    text = text.replace(group_line, group_line + f"\t\t\t\t{file_ref} /* {source} */,\n", 1)

    for anchor_build_ref in build_refs:
        build_ref = uid()
        build_def = (
            f"\t\t{anchor_build_ref} /* {anchor} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {anchor_ref} /* {anchor} */; }};\n"
        )
        source_build_def = (
            f"\t\t{build_ref} /* {source} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ref} /* {source} */; }};\n"
        )
        if build_def not in text:
            raise RuntimeError(f"Build definition not found: {anchor_build_ref}")
        text = text.replace(build_def, build_def + source_build_def, 1)

        phase_line = f"\t\t\t\t{anchor_build_ref} /* {anchor} in Sources */,\n"
        if phase_line not in text:
            raise RuntimeError(f"Build phase entry not found: {anchor_build_ref}")
        text = text.replace(phase_line, phase_line + f"\t\t\t\t{build_ref} /* {source} in Sources */,\n", 1)

    return True


files = [
    ("PlatformCapabilities.swift", "Theme.swift"),
    ("ViewingProfileStore.swift", "SettingsStore.swift"),
    ("PersonalizedHomeEngine.swift", "ShelfLoader.swift"),
    ("AppleTVExperience.swift", "FeaturedHero.swift"),
]

changed = False
for source, anchor in files:
    added = register(source, anchor)
    changed = changed or added
    print(f"{source}: {'registered' if added else 'already registered'}")

if changed:
    with open(PBX, "w", encoding="utf-8") as handle:
        handle.write(text)
