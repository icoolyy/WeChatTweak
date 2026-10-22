#!/usr/bin/env python3
"""Build and run native adapter fixtures without loading WeChat."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "Native/269602"
CASES = [
    ("mutex", ["NativeMutexTests.cpp"], False),
    ("cache", ["ContactCache.mm", "ContactCacheTests.mm"], True),
    ("search", ["ContactSearch.mm", "ContactSearchTests.mm"], True),
    (
        "adapter",
        ["Adapter.mm", "ContactCache.mm", "ContactSearch.mm", "AdapterTests.mm"],
        True,
    ),
    ("../Bridge/protocol", ["../Bridge/Protocol.mm", "../Bridge/ProtocolTests.mm"], True),
    ("../Bridge/credentials", ["../Bridge/Credentials.mm", "../Bridge/CredentialsTests.mm"], True),
    ("../Bridge/operation", ["../Bridge/Protocol.mm", "../Bridge/NativeOperation.mm", "../Bridge/NativeOperationTests.mm"], True),
]

with tempfile.TemporaryDirectory(prefix="wct-native-tests-") as directory:
    for name, sources, objc in CASES:
        executable = Path(directory) / Path(name).name
        command = ["/usr/bin/clang++", "-std=c++17", "-Wall", "-Wextra", "-Werror"]
        if objc:
            command += ["-fobjc-arc", "-framework", "Foundation"]
        subprocess.run(
            command
            + [str(NATIVE / source) for source in sources]
            + ["-o", str(executable)],
            check=True,
        )
        subprocess.run([str(executable)], check=True)
print("PASS: all native adapter fixture suites")
