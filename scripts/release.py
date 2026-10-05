#!/usr/bin/env python3
"""Reproducible local release gates. Never uploads, bumps versions, or installs an app."""
import argparse, json, os, pathlib, plistlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]

def absolute_path(value, label):
    if not value or not pathlib.Path(value).is_absolute():
        raise ValueError(label + " must be an absolute path")
    path = pathlib.Path(value)
    if ".." in path.parts:
        raise ValueError(label + " must not contain parent traversal")
    return path.resolve()

def validate_scheme(name):
    if not isinstance(name, str) or not name.strip() or name in (".", "..") or any(c in name for c in "/\\\x00\r\n"):
        raise ValueError("Unsafe scheme name")
    return name

def validate_archive(path, approved):
    path = absolute_path(str(path), "Archive")
    if not path.is_dir(): raise ValueError("Archive directory is missing")
    apps = list((path / "Products/Applications").glob("*.app"))
    if len(apps) != 1: raise ValueError("Archive must contain exactly one main application")
    def metadata(bundle):
        info = bundle / "Info.plist"
        if not info.exists(): info = bundle / "Contents/Info.plist"
        if not info.resolve().is_relative_to(path): raise ValueError("Bundle metadata escapes archive")
        try: value = plistlib.loads(info.read_bytes())
        except (OSError, plistlib.InvalidFileException, ValueError) as error:
            raise ValueError("Unreadable bundle metadata") from error
        if not isinstance(value, dict): raise ValueError("Bundle metadata must be a dictionary")
        return value
    main = metadata(apps[0])
    if not main.get("CFBundleVersion") or not main.get("CFBundleShortVersionString"):
        raise ValueError("Missing app versions")
    identifiers = set()
    for bundle in [apps[0]] + list(apps[0].rglob("*.appex")) + list(apps[0].rglob("*.app")):
        if not bundle.resolve().is_relative_to(path): raise ValueError("Bundle escapes archive")
        info = metadata(bundle)
        for key in ("CFBundleVersion", "CFBundleShortVersionString"):
            value = info.get(key)
            if not isinstance(value, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
                raise ValueError("Invalid app version: " + key)
        if info.get("CFBundleVersion") != main.get("CFBundleVersion"): raise ValueError("Embedded build numbers disagree")
        if info.get("CFBundleShortVersionString") != main.get("CFBundleShortVersionString"): raise ValueError("Embedded marketing versions disagree")
        if info.get("DTXcodeBuild") not in approved: raise ValueError("Archive used an unapproved Xcode build")
        platform = info.get("DTPlatformName")
        supported = info.get("CFBundleSupportedPlatforms", [])
        if not isinstance(supported, list) or any(not isinstance(p, str) for p in supported):
            raise ValueError("Invalid supported platforms")
        if isinstance(platform, str) and "simulator" in platform.lower() or any("simulator" in p.lower() for p in supported):
            raise ValueError("Simulator archive cannot be released")
        if platform not in ("iphoneos", "appletvos", "watchos", "macosx", "xros"):
            raise ValueError("Missing or unsupported archive platform")
        identifier = info.get("CFBundleIdentifier")
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", identifier):
            raise ValueError("Invalid bundle identifier")
        if identifier in identifiers: raise ValueError("Duplicate bundle identifier")
        identifiers.add(identifier)
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable or pathlib.Path(executable).name != executable or executable in (".", ".."):
            raise ValueError("Invalid bundle executable")
        executable_path = bundle / ("Contents/MacOS" if (bundle / "Contents/Info.plist").is_file() else "") / executable
        if not executable_path.resolve().is_relative_to(bundle.resolve()) or not executable_path.is_file() or not os.access(executable_path, os.X_OK):
            raise ValueError("Missing or unsafe bundle executable")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(apps[0])], check=True)
    return main

def validate_output(value):
    path = absolute_path(value, "SOWENS_BUILD_ROOT")
    if path == ROOT or path.is_relative_to(ROOT):
        raise ValueError("Build output must be outside the source repository")
    if path.exists() and not path.is_dir(): raise ValueError("Build output is not a directory")
    if path.parts[:2] == ("/", "Volumes"):
        if len(path.parts) < 3: raise ValueError("Choose a mounted output volume")
        mount = pathlib.Path(*path.parts[:3])
        if not mount.is_mount(): raise ValueError("Output volume is not mounted")
        expected = os.environ.get("SOWENS_BUILD_VOLUME_UUID")
        if not expected: raise ValueError("Set SOWENS_BUILD_VOLUME_UUID to the verified output volume UUID")
        info = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", str(mount)]))
        if info.get("VolumeUUID", "").upper() != expected.upper() or info.get("FilesystemType") != "apfs":
            raise ValueError("Output volume identity or filesystem does not match")
    return path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["check", "check-output", "build", "archive", "validate-archive"])
    parser.add_argument("--scheme")
    parser.add_argument("--archive")
    args = parser.parse_args()
    config = json.loads((ROOT / "tooling.json").read_text())
    if args.action == "check-output":
        validate_output(os.environ.get("SOWENS_BUILD_ROOT"))
        return
    if args.action == "validate-archive":
        if not args.archive: parser.error("--archive is required")
        validate_archive(args.archive, config["approved_xcode_builds"])
        print("Archive metadata and signatures verified")
        return
    version = subprocess.check_output(["xcodebuild", "-version"], text=True)
    build = re.search(r"Build version (\S+)", version)
    if not build or build[1] not in config["approved_xcode_builds"]:
        raise ValueError("Select an approved release Xcode using DEVELOPER_DIR; beta/unknown builds are blocked")
    subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
    if args.action == "check":
        subprocess.run([sys.executable, str(ROOT / "scripts/quality.py")], check=True)
        return
    output = os.environ.get("SOWENS_BUILD_ROOT")
    validate_output(output)
    schemes = [x for x in config["schemes"] if args.scheme is None or x["name"] == args.scheme]
    if not schemes: raise ValueError("Unknown scheme")
    if args.action == "archive" and (not args.scheme or not args.archive):
        parser.error("archive requires --scheme and a new --archive destination")
    for scheme in schemes:
        validate_scheme(scheme["name"])
        cmd = ["xcodebuild", "-project", str(ROOT / config["project"]), "-scheme", scheme["name"],
               "-destination", scheme["destination"], "-configuration", "Release",
               "-derivedDataPath", str(pathlib.Path(output) / ROOT.name / scheme["name"])]
        if args.action == "archive":
            archive = validate_output(args.archive)
            if pathlib.Path(args.archive).is_symlink() or archive.exists(): raise ValueError("Refusing to overwrite an existing archive")
            if archive.suffix != ".xcarchive": raise ValueError("Archive destination must end in .xcarchive")
            cmd += ["-archivePath", str(archive), "archive"]
        else: cmd += ["CODE_SIGNING_ALLOWED=NO", "build"]
        subprocess.run(cmd, cwd=ROOT, check=True)
        if args.action == "archive": validate_archive(args.archive, config["approved_xcode_builds"])

if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
