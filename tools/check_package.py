#!/usr/bin/env python3
"""Check that a packaged addon zip holds exactly what the client loads.

The zip must hold CraftAlert/CraftAlert.toc, CraftAlert/Bindings.xml and every
file CraftAlert.toc lists, and nothing else: no tests/, docs/, tools/ or
folder-module init.lua stubs. Catches drift in scripts/package.ps1's item list.

Usage:  python tools/check_package.py dist/CraftAlert.zip
        python tools/check_package.py dist/CraftAlert.zip --toc path/to/CraftAlert.toc
"""

import argparse
import os
import sys
import zipfile

ADDON = "CraftAlert"
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_TOC = os.path.join(REPO_ROOT, ADDON + ".toc")


def toc_entries(toc_path):
    """File entries of a TOC (blank lines, comments and ## tags skipped), forward slashes."""
    with open(toc_path, encoding="utf-8") as handle:
        lines = [line.strip() for line in handle]
    return [line.replace("\\", "/") for line in lines if line and not line.startswith("#")]


def is_folder_module_stub(path):
    return path.endswith("/init.lua")


def expected_entries(toc_path):
    """Zip paths the package must hold. init.lua stubs never count, even when listed."""
    files = [ADDON + ".toc", "Bindings.xml"] + toc_entries(toc_path)
    return {ADDON + "/" + path for path in files if not is_folder_module_stub(path)}


def zip_entries(zip_path):
    """File entries of the zip with forward slashes; directory entries skipped."""
    with zipfile.ZipFile(zip_path) as archive:
        names = [name.replace("\\", "/") for name in archive.namelist()]
    return {name for name in names if not name.endswith("/")}


def check_package(zip_path, toc_path=DEFAULT_TOC):
    """Returns (missing, extra) as sorted lists of zip paths."""
    expected = expected_entries(toc_path)
    actual = zip_entries(zip_path)
    return sorted(expected - actual), sorted(actual - expected)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check a packaged CraftAlert zip against CraftAlert.toc.")
    parser.add_argument("zip", help="zip built by scripts/package.ps1")
    parser.add_argument("--toc", default=DEFAULT_TOC, help="TOC to check against (default: the repo's)")
    args = parser.parse_args(argv)

    try:
        missing, extra = check_package(args.zip, args.toc)
    except (OSError, zipfile.BadZipFile) as error:
        print(f"ERROR: cannot read package: {error}", file=sys.stderr)
        return 1

    for path in missing:
        print(f"missing: {path}", file=sys.stderr)
    for path in extra:
        print(f"extra: {path}", file=sys.stderr)
    if missing or extra:
        print(f"FAIL: {args.zip}: {len(missing)} missing, {len(extra)} extra", file=sys.stderr)
        return 1

    print(f"OK: {args.zip} holds exactly the {len(expected_entries(args.toc))} packaged files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
