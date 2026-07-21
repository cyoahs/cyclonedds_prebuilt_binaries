#!/usr/bin/env python3
"""Regenerate the PEP 503 simple index under public/simple/ from public/packages/.

Usage:
    python3 generate_simple_index.py

Parses every *.whl in public/packages/, groups them by normalized project name,
and writes public/simple/index.html plus public/simple/<name>/index.html.
No third-party dependencies required.
"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PKG_DIR = ROOT / "public" / "packages"
SIMPLE_DIR = ROOT / "public" / "simple"

_canonicalize_re = re.compile(r"[-_.]+")


def canonicalize_name(name: str) -> str:
    # PEP 503 normalization.
    return _canonicalize_re.sub("-", name).lower()


def project_from_wheel(filename: str) -> str:
    # Wheel filename: {distribution}-{version}(-{build})?-{python}-{abi}-{platform}.whl
    # The distribution is everything before the first '-'.
    stem = filename[:-len(".whl")] if filename.endswith(".whl") else filename
    distribution = stem.split("-", 1)[0]
    return canonicalize_name(distribution)


def main() -> None:
    projects: dict[str, list[str]] = {}
    for whl in sorted(PKG_DIR.glob("*.whl")):
        project = project_from_wheel(whl.name)
        projects.setdefault(project, []).append(whl.name)

    SIMPLE_DIR.mkdir(parents=True, exist_ok=True)

    # Top-level /simple/index.html
    with (SIMPLE_DIR / "index.html").open("w", encoding="utf-8") as f:
        f.write("<!DOCTYPE html>\n<html>\n  <body>\n")
        for project in sorted(projects):
            f.write(f'    <a href="{project}/">{project}</a><br>\n')
        f.write("  </body>\n</html>\n")

    # Per-project /simple/<name>/index.html
    for project, files in sorted(projects.items()):
        project_dir = SIMPLE_DIR / project
        project_dir.mkdir(parents=True, exist_ok=True)
        with (project_dir / "index.html").open("w", encoding="utf-8") as f:
            f.write("<!DOCTYPE html>\n<html>\n  <body>\n")
            for filename in sorted(files):
                escaped = html.escape(filename)
                f.write(
                    f'    <a href="../../packages/{escaped}">{escaped}</a><br>\n'
                )
            f.write("  </body>\n</html>\n")

    print("Generated simple index:")
    for project in sorted(projects):
        print(f"  /simple/{project}/  ({len(projects[project])} file(s))")


if __name__ == "__main__":
    main()
