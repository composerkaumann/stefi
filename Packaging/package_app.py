#!/usr/bin/env python3
"""Build a local signed .app. FFmpeg is an external dependency, never bundled.

The first release is 1.0.0; new successful releases increment the patch/build.
--same-version is for internal QA, not a new user-facing release.
"""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, capture=False):
    return subprocess.run([str(x) for x in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def publish_app(app, final):
    """Keep the visible filename stable and retain the previous generated app."""
    if final.is_symlink():
        raise RuntimeError(f"Refusing to replace a symlink: {final}")
    if final.exists():
        archives = final.parent / "archive"
        archives.mkdir(exist_ok=True)
        backup = Path(tempfile.mkdtemp(prefix="previous-", dir=archives))
        final.rename(backup / "SteFi.app")
    shutil.copytree(app, final)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--same-version", action="store_true")
    options = parser.parse_args()
    old_version = (ROOT / "VERSION").read_text().strip()
    previous_build = int((ROOT / "BUILD_NUMBER").read_text())
    parts = [int(part) for part in old_version.split(".")]
    if len(parts) != 3:
        raise RuntimeError("VERSION must contain major.minor.patch")
    if previous_build and not options.same_version:
        parts[2] += 1
    version = ".".join(map(str, parts))
    build_number = previous_build if options.same_version and previous_build else previous_build + 1
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    # Versions belong in metadata, never in the app's name or filename.
    final = dist / "SteFi.app"
    with tempfile.TemporaryDirectory(prefix="stereo-package-") as scratch:
        scratch = Path(scratch)
        run("swift", "build", "--package-path", ROOT, "--scratch-path", scratch / "build", "-c", "release")
        bin_dir = Path(run("swift", "build", "--package-path", ROOT, "--scratch-path", scratch / "build", "-c", "release", "--show-bin-path", capture=True).strip())
        app = scratch / final.name
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        shutil.copy2(bin_dir / "SteFi", contents / "MacOS" / "SteFi")
        info = {
            "CFBundleName": "SteFi", "CFBundleDisplayName": "SteFi",
            "CFBundleIdentifier": "ee.music.SteFi", "CFBundleExecutable": "SteFi",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
            "CFBundleVersion": str(build_number), "LSMinimumSystemVersion": "14.0",
            "NSPrincipalClass": "NSApplication", "NSHighResolutionCapable": True,
            "CFBundleIconFile": "AppIcon", "NSHumanReadableCopyright": "SteFi · Local media utility"
        }
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        run("swift", ROOT / "Packaging" / "make_icon.swift", scratch / "AppIcon.iconset")
        run("iconutil", "-c", "icns", scratch / "AppIcon.iconset", "-o", contents / "Resources" / "AppIcon.icns")
        run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        # Reject accidental external executable/library inclusion.
        if sorted(p.name for p in (contents / "MacOS").iterdir()) != ["SteFi"]:
            raise RuntimeError("Unexpected executable in app")
        if (contents / "Helpers").exists() or (contents / "Frameworks").exists():
            raise RuntimeError("This app must not bundle FFmpeg or its libraries")
        publish_app(app, final)
        run("codesign", "--verify", "--deep", "--strict", final)
    (ROOT / "VERSION").write_text(version + "\n")
    (ROOT / "BUILD_NUMBER").write_text(str(build_number) + "\n")
    print(f"Ready: {final}\nVersion: {version} ({build_number})\nMinimum macOS: 14.0\nFFmpeg: external installation required")


if __name__ == "__main__":
    main()
