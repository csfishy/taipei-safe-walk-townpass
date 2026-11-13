#!/usr/bin/env python3
"""Read-only source/package checks. Never connects to a reference database.

This is a packaging and obvious-write guard, not a SQL security parser. Remote
permissions and a trusted, explicitly invoked import remain necessary.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile


SQLITE_HEADER = b"SQLite format 3\x00"
# One reviewed public OSM basemap, never a generic SQLite/MBTiles exemption.
# Changing the snapshot requires reviewing this digest along with its provenance.
PUBLIC_BASEMAP_SHA256 = '774d69bad7866536abbd679d0dc4d8d9f97bedc45d3db398cd14c32d061d4f25'
PUBLIC_BASEMAP_PATHS = {
    'assets/safe_walk/map/taipei.mbtiles',
    'assets/assets/safe_walk/map/taipei.mbtiles',
    'assets/flutter_assets/assets/safe_walk/map/taipei.mbtiles',
    'payload/runner.app/frameworks/app.framework/flutter_assets/assets/safe_walk/map/taipei.mbtiles',
}


def reviewed_public_basemap(name, stream):
    if normalized_name(name) not in PUBLIC_BASEMAP_PATHS:
        return False
    digest = hashlib.sha256(SQLITE_HEADER)
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(block)
    return digest.hexdigest() == PUBLIC_BASEMAP_SHA256

PRIVATE_DIRECTORIES = {".local-data", "crime-reference-data"}
MANUAL_SQL_DIRECTORY = "supabase/crime_reference/"
SHELL_SUFFIXES = {".sh", ".bash", ".ps1", ".cmd", ".bat"}
SCHEMA = r'"?crime_reference"?'
WRITE_PATTERN = re.compile(
    r"\b(?:insert\s+into|update|delete\s+from|merge\s+into|copy|"
    r"truncate(?:\s+table)?|drop\s+(?:schema|table|function|view|sequence)|"
    r"alter\s+(?:schema|table|function|view|sequence)|"
    r"create\s+(?:or\s+replace\s+)?(?:schema|table|function|view|sequence)|"
    r"call)\s+(?:if\s+(?:not\s+)?exists\s+)?" + SCHEMA + r"(?=\s*\.|\s|;|$)",
    re.IGNORECASE,
)
PRIVILEGE_PATTERN = re.compile(
    r"\b(?:grant|revoke)\b[^;]*\b(?:on|in)\s+(?:schema\s+)?"
    + SCHEMA + r"(?:\s*\.|\b)", re.IGNORECASE,
)
INDEX_PATTERN = re.compile(
    r"\bcreate\s+(?:unique\s+)?index\b[^;]*\bon\s+"
    + SCHEMA + r"\s*\.", re.IGNORECASE,
)
FUNCTION_CALL_PATTERN = re.compile(
    r"\b(?:select|perform)\s+" + SCHEMA + r'\s*\.\s*"?\w+"?\s*\(',
    re.IGNORECASE,
)
PRIVATE_SEARCH_PATH_PATTERN = re.compile(
    # SET [LOCAL] search_path, set_config('search_path', ...), and shell/YAML
    # PGOPTIONS may make otherwise unqualified SQL target the private schema.
    # Read-only scripts outside the reviewed manual SQL must qualify table names.
    r"\b(?:search_path|PGOPTIONS)\b[^;]*\bcrime_reference\b", re.IGNORECASE,
)


def normalized_name(name: str) -> str:
    return name.replace("\\", "/").lower()


def forbidden_database_name(name: str) -> bool:
    path = PurePosixPath(normalized_name(name))
    return (
        any(part in PRIVATE_DIRECTORIES for part in path.parts)
        or re.fullmatch(r"nnk-crime.*\.sqlite[^/]*", path.name) is not None
    )


def without_comments(text: str) -> str:
    # Preserve quoted values: line comments alone must not turn prose into SQL.
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    return "\n".join(
        line for line in text.splitlines()
        if not line.lstrip().startswith(("#", "--"))
    )


def write_policy_errors(name: str, text: str) -> list[str]:
    """Reject direct schema writes outside reviewed manual SQL and all CI imports."""
    path = normalized_name(name)
    content = without_comments(text)
    workflow = path.startswith(".github/workflows/") or path.startswith(".github/actions/")
    controlled_sql = path.startswith(MANUAL_SQL_DIRECTORY) and path.endswith(".sql")
    errors = []
    if not controlled_sql and any(pattern.search(content) for pattern in (
            WRITE_PATTERN, PRIVILEGE_PATTERN, INDEX_PATTERN, FUNCTION_CALL_PATTERN)):
        errors.append(f"{name}: crime_reference writes belong only in reviewed manual SQL")
    if not controlled_sql and PRIVATE_SEARCH_PATH_PATTERN.search(content):
        errors.append(f"{name}: crime_reference search_path/PGOPTIONS belong only in reviewed manual SQL")
    if workflow:
        prohibited = (
            re.search(r"supabase[/\\]crime_reference", content, re.IGNORECASE)
            or re.search(r"\bimport-new\b", content, re.IGNORECASE)
            or re.search(r"\bsupabase\s+(?:db\s+(?:reset|push)|migration\s+up)\b", content, re.IGNORECASE)
            or re.search(r"\b(?:import|seed|reset|truncate|drop)[\w./-]*crime_reference\b", content, re.IGNORECASE)
            or re.search(r"\bcrime_reference[\w./-]*(?:import|seed|reset)\b", content, re.IGNORECASE)
        )
        if prohibited:
            errors.append(f"{name}: CI must not import, reset or apply crime reference data")
    elif not controlled_sql and re.search(r"supabase[/\\]crime_reference[/\\]", content, re.IGNORECASE):
        errors.append(f"{name}: do not automate the explicitly manual crime reference SQL")
    return errors


def git_paths(root: Path, *, tracked_only: bool = False) -> list[str]:
    args = ["git", "-C", str(root), "ls-files", "-z", "--cached"]
    if not tracked_only:
        args += ["--others", "--exclude-standard"]
    result = subprocess.run(args, check=True, capture_output=True)
    return sorted(set(os.fsdecode(part) for part in result.stdout.split(b"\0") if part))


def contained_regular_file(root: Path, relative: str) -> tuple[Path | None, str | None]:
    candidate = root / relative
    try:
        candidate.resolve().relative_to(root)
    except (ValueError, OSError):
        return None, f"{relative}: points outside checkout; no external file was opened"
    try:
        mode = candidate.lstat().st_mode
    except FileNotFoundError:
        return None, None  # A tracked deletion is not packaged by this checkout.
    if stat.S_ISLNK(mode):
        return None, f"{relative}: symlinks cannot be verified without following external data"
    if not stat.S_ISREG(mode):
        return None, None
    return candidate, None


def asset_files(root: Path) -> tuple[set[str], list[str]]:
    """Scan declared Flutter assets (including ignored files) without YAML deps."""
    paths = {"assets", "fonts"}
    spec = root / "pubspec.yaml"
    if spec.exists():
        in_flutter = False
        for line in spec.read_text(encoding="utf-8").splitlines():
            if re.match(r"^flutter:\s*(?:#.*)?$", line):
                in_flutter = True
                continue
            if in_flutter and line and not line[0].isspace() and not line.startswith("#"):
                in_flutter = False
            if in_flutter:
                match = re.match(r"^\s*-\s*(?:asset:\s*)?['\"]?([^'\"\s:#]+)", line)
                if match and "/" in match[1]:
                    paths.add(match[1])
    found: set[str] = set()
    errors: list[str] = []
    for relative in sorted(paths):
        target = root / relative
        try:
            target.resolve().relative_to(root)
        except (ValueError, OSError):
            errors.append(f"{relative}: asset declaration points outside checkout")
            continue
        if target.is_symlink():
            errors.append(f"{relative}: asset symlink is not allowed")
        elif target.is_file():
            found.add(target.relative_to(root).as_posix())
        elif target.is_dir():
            for directory, subdirs, files in os.walk(target, followlinks=False):
                for child in list(subdirs):
                    child_path = Path(directory) / child
                    if child_path.is_symlink():
                        errors.append(f"{child_path.relative_to(root).as_posix()}: asset symlink is not allowed")
                        subdirs.remove(child)
                found.update((Path(directory) / child).relative_to(root).as_posix() for child in files)
    return found, errors


def scan_repository(root: Path) -> list[str]:
    root = root.resolve()
    tracked = set(git_paths(root, tracked_only=True))
    sources = set(git_paths(root))
    assets, errors = asset_files(root)
    for relative in sorted(tracked | assets):
        candidate, error = contained_regular_file(root, relative)
        if error:
            errors.append(error)
        if candidate is None:
            continue
        if forbidden_database_name(relative):
            errors.append(f"{relative}: private crime database/data path cannot be tracked or packaged")
        with candidate.open("rb") as stream:
            if (stream.read(len(SQLITE_HEADER)) == SQLITE_HEADER
                    and not reviewed_public_basemap(relative, stream)):
                errors.append(f"{relative}: SQLite binary cannot be tracked or packaged")
    for relative in sorted(sources):
        path = normalized_name(relative)
        if not (Path(path).suffix in SHELL_SUFFIXES | {".sql"}
                or path.startswith((".github/workflows/", ".github/actions/"))):
            continue
        candidate, error = contained_regular_file(root, relative)
        if error:
            errors.append(error)
        elif candidate:
            errors += write_policy_errors(relative, candidate.read_text(encoding="utf-8"))
    return sorted(set(errors))


def scan_archive(path: Path) -> list[str]:
    errors = []
    try:
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                if member.is_dir():
                    continue
                label = f"{path.name}!{member.filename}"
                if forbidden_database_name(member.filename):
                    errors.append(f"{label}: private crime database/data path in package")
                with archive.open(member) as stream:
                    if (stream.read(len(SQLITE_HEADER)) == SQLITE_HEADER
                            and not reviewed_public_basemap(member.filename, stream)):
                        errors.append(f"{label}: SQLite binary in package")
    except (OSError, RuntimeError, zipfile.BadZipFile, NotImplementedError) as error:
        errors.append(f"{path.name}: archive cannot be verified ({type(error).__name__})")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--archive", action="append", type=Path, default=[], help="Web ZIP, APK or IPA; may repeat")
    args = parser.parse_args(argv)
    try:
        errors = scan_repository(args.root)
        for archive in args.archive:
            errors += scan_archive(archive)
    except (OSError, subprocess.CalledProcessError, UnicodeError) as error:
        print(f"Crime database isolation check could not complete: {type(error).__name__}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"PASS: crime reference isolation; source and {len(args.archive)} archive(s) checked; no external database opened")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
