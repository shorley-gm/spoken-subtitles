"""Zip the addon for release: dist/SpokenSubtitles-<version>.zip, version read from the TOC.

The zip holds the SpokenSubtitles folder and nothing else (no tests, tools or mockups),
with LICENSE and CHANGELOG copied in so the store download carries them.
"""
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "SpokenSubtitles"
EXTRA = ["LICENSE", "CHANGELOG.md"]


def main():
    toc = (ADDON / "SpokenSubtitles.toc").read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    if not match:
        sys.exit("no ## Version in the TOC")
    version = match.group(1)

    out = ROOT / "dist" / f"SpokenSubtitles-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(ADDON.rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                zf.write(path, path.relative_to(ROOT).as_posix())
        for name in EXTRA:
            zf.write(ROOT / name, f"SpokenSubtitles/{name}")
    print(f"{out.relative_to(ROOT)}  ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
