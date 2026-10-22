#!/usr/bin/env python3
#
# Copyright (c) 2026, Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

"""Install the Android NDK C headers used by the Ubuntu build images."""

import argparse
import hashlib
from pathlib import Path
import shutil
# Commands use fixed argument lists without a shell.
import subprocess  # nosec B404
import tempfile
import zipfile


def download(url, destination, sha256):
    # Ubuntu 18.04 images build Python without the optional SSL module.
    subprocess.run(
        ["wget", "--retry-connrefused", "--waitretry=5", "--timeout=30",
         "--tries=5", "--no-verbose", "-O", str(destination), url],
        check=True,
    )
    digest = hashlib.sha256()
    with destination.open("rb") as archive:
        for chunk in iter(lambda: archive.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != sha256:
        raise RuntimeError("Checksum mismatch for " + url)


def install_ndk(directory, temporary):
    archive = temporary / "android-ndk-r27d-linux.zip"
    download(
        "https://dl.google.com/android/repository/android-ndk-r27d-linux.zip",
        archive,
        "601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9",
    )
    prefix = "android-ndk-r27d/toolchains/llvm/prebuilt/linux-x86_64/sysroot/"
    # Only C headers are needed. This does not execute NDK host binaries and
    # also works when building the image on an AArch64 host.
    with zipfile.ZipFile(archive) as ndk:
        for entry in ndk.infolist():
            if not entry.filename.startswith(prefix + "usr/include/"):
                continue
            relative = Path(entry.filename[len(prefix):])
            if relative.is_absolute() or ".." in relative.parts:
                raise RuntimeError("Invalid path in NDK archive")
            destination = directory / "sysroot" / relative
            if entry.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with ndk.open(entry) as source, destination.open("wb") as output:
                    shutil.copyfileobj(source, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk-dir", type=Path, default=Path("/usr/local/share/android-ndk"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temporary:
        install_ndk(args.ndk_dir, Path(temporary))


if __name__ == "__main__":
    main()
