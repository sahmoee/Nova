#!/usr/bin/env python3
"""Verify source membership by following Xcode target and group references."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

IOS_ONLY = {
    "Nova/App/PositionSync.swift", "Nova/App/LiveActivity.swift",
    "Nova/App/QuickActions.swift", "Nova/App/CarPlayDelegate.swift",
    "Nova/Views/Player/NovaChapterBar.swift", "Nova/Services/NovaEpisodeCalendar.swift",
    "Nova/Services/Watch/NovaWatchRemotePlayer.swift",
    "Nova/Services/Watch/NovaPhoneWatchBridge.swift",
}
# Retained source copies are not alternative active implementations. The app uses
# UnifiedQAReporter and TrackingProvider's EpisodeAvailabilityNotifier.
INACTIVE = {
    "Nova/QAAppConfig.swift", "Nova/QABackgroundRunner+Nova.swift",
    "Nova/QAInvariants+Nova.swift", "Nova/QAChecklist+Nova.swift",
    "Nova/Services/EpisodeAvailabilityNotifier.swift",
}


def source_membership(project):
    objects = project["objects"]
    root = objects[project["rootObject"]]
    paths = {}

    def visit(identifier, parent, stack):
        if identifier in stack:
            raise ValueError("Cycle in project groups")
        node = objects[identifier]
        source_tree = node.get("sourceTree", "<group>")
        if source_tree not in ("<group>", "SOURCE_ROOT"):
            return
        base = Path() if source_tree == "SOURCE_ROOT" else parent
        path = base / node.get("path", "")
        if node["isa"] == "PBXFileReference":
            paths[identifier] = os.path.normpath(path.as_posix())
        for child in node.get("children", []):
            visit(child, path, stack | {identifier})

    visit(root["mainGroup"], Path(), set())
    membership = {}
    for node in objects.values():
        if node["isa"] != "PBXNativeTarget":
            continue
        sources = set()
        for phase_id in node.get("buildPhases", []):
            phase = objects[phase_id]
            if phase["isa"] != "PBXSourcesBuildPhase":
                continue
            for build_id in phase.get("files", []):
                reference = objects[build_id].get("fileRef")
                if reference in paths:
                    sources.add(paths[reference])
        membership[node["name"]] = sources
    return membership


def validate(project, sources):
    membership = source_membership(project)
    problems = []
    for name in ("Nova-iOS", "Nova-tvOS"):
        if name not in membership:
            problems.append(f"Missing target: {name}")
    for path in sorted(sources):
        if path in INACTIVE or path.startswith("Nova/QACore/"):
            continue
        expected = ("Nova-iOS",) if path in IOS_ONLY else ("Nova-iOS", "Nova-tvOS")
        for target in expected:
            if path not in membership.get(target, set()):
                problems.append(f"{path}: missing from {target} Sources")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        project = json.loads(subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-",
            str(root / "Nova.xcodeproj/project.pbxproj"),
        ], stderr=subprocess.PIPE))
        sources = {p.relative_to(root).as_posix() for p in (root / "Nova").rglob("*.swift")
                   if not p.name.startswith("._")}
        problems = validate(project, sources)
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"verify_registration: unable to inspect project ({type(error).__name__})", file=sys.stderr)
        return 2
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("verify_registration: FAILED", file=sys.stderr)
        return 1
    print("verify_registration: OK — shared and platform-specific sources match their targets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
