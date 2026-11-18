#!/usr/bin/env python3
"""Verify the project's signed ARM64 APK without extracting or modifying it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile


PACKAGE = "io.github.sakurabluer.stashflow"
CERTIFICATE = "3a543b54fad6b0242fab8ee6511bf1f73b2caf6b4e25ef1c1217c3b804dbae58"


def sdk_path(explicit):
    if explicit:
        return Path(explicit)
    for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(name):
            return Path(os.environ[name])
    properties = Path(__file__).resolve().parents[4] / "android/local.properties"
    if properties.is_file():
        for line in properties.read_text(encoding="utf-8").splitlines():
            if line.startswith("sdk.dir="):
                return Path(line.split("=", 1)[1].replace("\\\\", "\\").replace("\\:", ":"))
    raise ValueError("Android SDK not found; supply --sdk or ANDROID_HOME.")


def android_tools(sdk):
    build_tools = sdk / "build-tools"
    candidates = []
    if build_tools.is_dir():
        for folder in build_tools.iterdir():
            if folder.is_dir() and re.fullmatch(r"\d+(?:\.\d+)*", folder.name):
                candidates.append(folder)
    for folder in sorted(candidates, key=lambda p: tuple(map(int, p.name.split("."))), reverse=True):
        aapt = folder / ("aapt.exe" if os.name == "nt" else "aapt")
        signer = folder / ("apksigner.bat" if os.name == "nt" else "apksigner")
        if aapt.is_file() and signer.is_file():
            return aapt, signer
    raise ValueError("Install Android build-tools containing aapt and apksigner.")


def command_output(command):
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise ValueError(f"{Path(command[0]).name} failed: {result.stdout.strip()} {result.stderr.strip()}")
    return result.stdout


def verify(args):
    apk = args.apk.resolve(strict=True)
    forbidden = []
    for name in args.forbid_env:
        value = os.environ.get(name)
        if not value:
            raise ValueError(f"Required scan environment variable is empty: {name}")
        forbidden.append(value.encode("utf-8"))
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        abis = {name.split("/")[1] for name in names if name.startswith("lib/") and name.endswith(".so")}
        if abis != {"arm64-v8a"}:
            raise ValueError(f"APK must contain only arm64-v8a native libraries; found {sorted(abis)}")
        for name in ("lib/arm64-v8a/libapp.so", "lib/arm64-v8a/libflutter.so"):
            if name not in names:
                raise ValueError(f"Missing runtime: {name}")
        for info in archive.infolist():
            if forbidden and not info.is_dir():
                data = archive.read(info)
                if any(value in data for value in forbidden):
                    # Deliberately omit both secret values and the containing bytes.
                    raise ValueError("APK contains a forbidden environment value.")
    aapt, signer = android_tools(sdk_path(args.sdk))
    badging = command_output([str(aapt), "dump", "badging", str(apk)])
    match = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    if not match:
        raise ValueError("Cannot read APK package/version metadata.")
    package, code, name = match.groups()
    if (package, int(code), name) != (PACKAGE, args.version_code, args.version_name):
        raise ValueError(f"Package/version mismatch: {package}, {code}, {name}")
    native = re.search(r"^native-code:\s*(.*)$", badging, re.MULTILINE)
    if not native or set(re.findall(r"'([^']+)'", native.group(1))) != {"arm64-v8a"}:
        raise ValueError("Android package metadata does not advertise ARM64 only.")
    signature = command_output([str(signer), "verify", "--print-certs", str(apk)])
    certificates = re.findall(r"certificate SHA-256 digest:\s*([a-fA-F0-9]+)", signature)
    if {cert.lower() for cert in certificates} != {CERTIFICATE}:
        raise ValueError("APK does not use the official Stash Flow release certificate.")
    return {
        "apk": str(apk), "package": package, "version_name": name,
        "version_code": int(code), "abis": sorted(abis), "bytes": apk.stat().st_size,
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "certificate_sha256": CERTIFICATE, "forbidden_values_checked": len(forbidden),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--sdk")
    parser.add_argument("--version-name", required=True)
    parser.add_argument("--version-code", type=int, required=True)
    parser.add_argument("--forbid-env", action="append", default=[])
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args), indent=2, ensure_ascii=True))
        return 0
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f"APK verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
