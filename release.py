#!/usr/bin/env python3
"""
release.py — Bump version in distro.toml and optionally commit + tag.

Usage:
  python release.py --patch
  python release.py --minor
  python release.py --major
  python release.py --uv-version 0.11.0
  python release.py --minor --uv-version 0.11.0 --tag
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

DISTRO_TOML = Path(__file__).parent / "distro.toml"


def _read_toml_field(text: str, key: str) -> str:
    m = re.search(rf'^{re.escape(key)}\s*=\s*"([^"]+)"', text, re.MULTILINE)
    if not m:
        raise SystemExit(f"ERROR: {key!r} not found in distro.toml")
    return m.group(1)


def _set_toml_field(text: str, key: str, value: str) -> str:
    return re.sub(
        rf'^({re.escape(key)}\s*=\s*)"[^"]+"',
        rf'\g<1>"{value}"',
        text,
        flags=re.MULTILINE,
    )


def _bump(version: str, part: str) -> str:
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not m:
        raise SystemExit(f"ERROR: cannot parse version {version!r}")
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def _run(cmd: list[str]) -> None:
    result = subprocess.run(cmd)
    if result.returncode != 0:
        raise SystemExit(f"ERROR: {' '.join(cmd)} failed")


def main() -> None:
    p = argparse.ArgumentParser(description="Bump managed-python version in distro.toml")
    bump = p.add_mutually_exclusive_group()
    bump.add_argument("--patch", action="store_const", const="patch", dest="bump")
    bump.add_argument("--minor", action="store_const", const="minor", dest="bump")
    bump.add_argument("--major", action="store_const", const="major", dest="bump")
    p.add_argument("--uv-version", dest="uv_version", metavar="X.Y.Z",
                   help="Also update the pinned uv version")
    p.add_argument("--tag", action="store_true",
                   help="Commit distro.toml and create a git tag")
    p.add_argument("--yes", "-y", action="store_true",
                   help="Skip confirmation prompt")
    args = p.parse_args()

    if not args.bump and not args.uv_version:
        p.error("specify at least one of --patch/--minor/--major or --uv-version")

    text = DISTRO_TOML.read_text(encoding="utf-8")
    old_version = _read_toml_field(text, "version")
    old_uv      = _read_toml_field(text, "uv_version")

    new_version = _bump(old_version, args.bump) if args.bump else old_version
    new_uv      = args.uv_version or old_uv

    print(f"  distro version : {old_version} -> {new_version}" if new_version != old_version
          else f"  distro version : {old_version} (unchanged)")
    print(f"  uv version     : {old_uv} -> {new_uv}" if new_uv != old_uv
          else f"  uv version     : {old_uv} (unchanged)")

    if new_version == old_version and new_uv == old_uv:
        print("Nothing to change.")
        sys.exit(0)

    if args.tag:
        print(f"  git tag        : v{new_version}")

    if not args.yes:
        try:
            answer = input("\nProceed? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nAborted.")
            sys.exit(1)
        if answer not in ("y", "yes"):
            print("Aborted.")
            sys.exit(1)

    text = _set_toml_field(text, "version",    new_version)
    text = _set_toml_field(text, "uv_version", new_uv)
    DISTRO_TOML.write_text(text, encoding="utf-8")
    print(f"  updated distro.toml")

    if args.tag:
        tag = f"v{new_version}"
        _run(["git", "add", "distro.toml"])
        _run(["git", "commit", "-m", f"chore(release): bump to {tag}"])
        _run(["git", "tag", tag])
        print(f"  created tag {tag}")
        print(f"\n  Push with:  git push && git push origin {tag}")


if __name__ == "__main__":
    main()
