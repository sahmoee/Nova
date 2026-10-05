#!/usr/bin/env python3
"""Preview or pin one target's bundle identity without rewriting other targets."""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys


def pin(project, text, target, bundle_id):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", bundle_id):
        raise ValueError("Bundle ID must contain only letters, numbers, dots, and hyphens")
    objects = project["objects"]
    targets = [v for v in objects.values() if v.get("isa") == "PBXNativeTarget" and v.get("name") == target]
    if len(targets) != 1:
        raise ValueError("Specify exactly one existing target with --target")
    config_list = objects[targets[0]["buildConfigurationList"]]
    updated = text
    changed = []
    for identifier in config_list["buildConfigurations"]:
        config = objects[identifier]
        pattern = re.compile(r"^\t\t" + re.escape(identifier) + r" /\*[^\n]*\*/ = \{.*?^\t\t\};", re.MULTILINE | re.DOTALL)
        match = pattern.search(updated)
        if not match:
            raise ValueError("Unable to locate the target's build configuration")
        block, count = re.subn(r"PRODUCT_BUNDLE_IDENTIFIER = [^;]*;", f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};", match.group())
        if count != 1:
            raise ValueError("Each target configuration must declare exactly one bundle ID")
        changed.append((config["name"], config.get("buildSettings", {}).get("PRODUCT_BUNDLE_IDENTIFIER", ""), bundle_id))
        updated = updated[:match.start()] + block + updated[match.end():]
    if not changed:
        raise ValueError("Target has no build configurations")
    return updated, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--set", dest="bundle_id", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    pbx = args.project / "project.pbxproj"
    try:
        project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(pbx)], stderr=subprocess.PIPE))
        original = pbx.read_text()
        updated, changes = pin(project, original, args.target, args.bundle_id)
        for name, old, new in changes:
            print(f"{args.target} / {name}: {old} → {new}")
        if args.apply and updated != original:
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S%f")
            backup = pbx.with_name(pbx.name + ".bak." + stamp)
            backup.write_text(original)
            staging = pbx.with_name(pbx.name + ".pin.tmp")
            staging.write_text(updated)
            staging.replace(pbx)
            print("Updated only the requested target. Recovery copy saved beside the project.")
        else:
            print("No files written." if not args.apply else "Bundle identity already matches.")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Bundle ID update rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
