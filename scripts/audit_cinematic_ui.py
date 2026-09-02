#!/usr/bin/env python3
"""Static guardrails for Nova's single cinematic SwiftUI presentation system."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT_ROOTS = (ROOT / "Nova" / "Views", ROOT / "Nova" / "Components", ROOT / "Nova" / "Services")

# These patterns represent presentation forks or stock button treatments that can
# silently reintroduce a second visual language. Persisted enum declarations and
# migration storage in SettingsStore intentionally live outside the scanned roots.
FORBIDDEN = {
    "stock bordered button": re.compile(r"\.buttonStyle\(\.(?:bordered|borderedProminent)\)"),
    "live component-style branch": re.compile(r"Theme\.uiStyle"),
    "live legacy style selection": re.compile(
        r"settings\.(?:homeStyle|libraryStyle|detailStyle|tabBarStyle|vlcOverlayStyle)"
    ),
}

PRESENTATIONS = re.compile(r"\.(?:sheet|fullScreenCover|popover)\s*\(")


def swift_files() -> list[Path]:
    return sorted(path for root in SWIFT_ROOTS for path in root.rglob("*.swift"))


def main() -> int:
    violations: list[str] = []
    presentation_count = 0
    files = swift_files()

    for path in files:
        text = path.read_text(encoding="utf-8")
        presentation_count += len(PRESENTATIONS.findall(text))
        for label, pattern in FORBIDDEN.items():
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                violations.append(f"{path.relative_to(ROOT)}:{line}: {label}")

    print(f"Scanned {len(files)} Swift UI/service files and {presentation_count} presentation sites.")
    if violations:
        print("Cinematic UI audit failed:")
        print("\n".join(f"  - {item}" for item in violations))
        return 1

    print("Cinematic UI audit: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
