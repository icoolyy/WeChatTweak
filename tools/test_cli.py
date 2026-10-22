#!/usr/bin/env python3
"""Exercise the built CLI against disposable application packages, never real WeChat."""
import hashlib
import json
import pathlib
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile


def main():
    executable = pathlib.Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="wechattweak-cli-") as directory:
        root = pathlib.Path(directory)
        app = root / "Test WeChat $(echo literal).app"
        binary = app / "Contents/MacOS/WeChat"
        binary.parent.mkdir(parents=True)
        image = bytearray(512)
        struct.pack_into("<8I", image, 0, 0xFEEDFACF, 0x0100000C, 0, 2, 1, 72, 0, 0)
        struct.pack_into("<II16sQQQQiiII", image, 32, 0x19, 72, b"__TEXT", 0x1000, 0x400, 0, 512, 5, 5, 0, 0)
        image[256:264] = bytes.fromhex("0102030405060708")
        binary.write_bytes(image)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "test.wechattweak.fixture",
            "CFBundleShortVersionString": "4.1.13", "CFBundleVersion": "269602",
        }))
        config = root / "config.json"
        config.write_text(json.dumps([{"version": "269602", "targets": [{
            "identifier": "revoke", "entries": [{"arch": "arm64", "addr": "1100",
                "asm": "00008052C0035FD6", "original": "0102030405060708"}]}]}]))
        staged = root / "wechattweak"
        shutil.copy2(executable, staged)

        def run(*args):
            return subprocess.run([str(staged), *args], cwd="/tmp", text=True,
                                  capture_output=True, timeout=15)

        original = hashlib.sha256(binary.read_bytes()).hexdigest()
        result = run("versions", "--app", str(app))
        assert result.returncode == 0, result.stderr
        assert "4.1.13 (269602)" in result.stdout
        assert config.as_uri() in result.stdout
        # Isolate this fixture from any real bridge already running on the host.
        report = run("doctor", "--app", str(app), "--json", "--credential-file", str(root / "missing-token"))
        assert report.returncode == 0, report.stderr
        data = json.loads(report.stdout)
        assert data["patchState"] == "ready" and data["pendingWrites"] == 1
        assert data["contactsBridgeAvailable"] is False
        dry_run = run("patch", "--app", str(app), "--dry-run")
        assert dry_run.returncode == 0, dry_run.stderr
        assert "Dry run: no files changed" in dry_run.stdout
        assert hashlib.sha256(binary.read_bytes()).hexdigest() == original
        image[256] = 99
        binary.write_bytes(image)
        mismatch = run("patch", "--app", str(app), "--dry-run")
        assert mismatch.returncode != 0 and "Original bytes mismatch" in mismatch.stderr
        assert binary.read_bytes() == image
        missing = run("doctor", "--app", str(root / "Missing.app"), "--json", "--credential-file", str(root / "missing-token"))
        assert missing.returncode != 0
        assert json.loads(missing.stdout)["patchState"] == "error"
        assert not list(root.glob(".WeChatTweak-stage-*"))
        assert not (root / ".WeChatTweakBackups").exists()
    print("CLI integration: 6 scenarios passed; temporary fixtures only")


if __name__ == "__main__":
    main()
