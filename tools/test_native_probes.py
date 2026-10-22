#!/usr/bin/env python3
"""Exercise the research probe in disposable hosts, never in WeChat."""
import os
import ctypes
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="wct-probe-tests-") as scratch:
    scratch = Path(scratch)
    heap_test = scratch / "heap-test"
    library = scratch / "inventory.dylib"
    host = scratch / "host"
    source = scratch / "host.c"
    source.write_text(
        "#include <dispatch/dispatch.h>\n#include <unistd.h>\n"
        "static void stop(void *ctx) {(void)ctx; _exit(0);}\n"
        "int main(int argc, char **argv) {(void)argv; if(argc==1) return 0;"
        "dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,35LL*NSEC_PER_SEC),"
        "dispatch_get_main_queue(),0,stop);dispatch_main();}\n"
    )
    flags = ["/usr/bin/clang", "-Wall", "-Wextra", "-Werror"]
    open_probe = scratch / "open-chat.dylib"
    run(
        *flags,
        "-dynamiclib",
        "-arch",
        "arm64",
        str(ROOT / "Native/Probes/open_chat_probe.c"),
        "-o",
        str(open_probe)
    )
    probe = ctypes.CDLL(str(open_probe))
    assert probe.wct_probe_open_filehelper() == -2
    assert probe.wct_probe_current_filehelper() == -2
    print("PASS: open-chat probe refuses missing module", flush=True)
    run(*flags, str(ROOT / "Native/Probes/heap_inventory_test.c"), "-o", str(heap_test))
    result = run(str(heap_test))
    assert "fixture=4 absent=0" in result.stdout, result.stdout
    assert "after_free=0" in result.stdout, result.stdout
    print("PASS: allocated objects found, absent/freed objects excluded", flush=True)
    run(
        *flags,
        "-dynamiclib",
        "-arch",
        "arm64",
        str(ROOT / "Native/Probes/object_inventory.c"),
        "-o",
        str(library)
    )
    run(*flags, str(source), "-o", str(host))
    env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(library))
    env.pop("WCT_INVENTORY_OUTPUT", None)
    run(str(host), env=env)
    print("PASS: no output path is inert", flush=True)
    sentinel = scratch / "sentinel"
    sentinel.write_text("untouched")
    env["WCT_INVENTORY_OUTPUT"] = str(sentinel)
    run(str(host), env=env)
    assert sentinel.read_text() == "untouched"
    link = scratch / "link"
    link.symlink_to(sentinel)
    env["WCT_INVENTORY_OUTPUT"] = str(link)
    run(str(host), env=env)
    assert sentinel.read_text() == "untouched"
    print("PASS: existing files and symlinks are refused", flush=True)
    output = scratch / "result"
    env["WCT_INVENTORY_OUTPUT"] = str(output)
    run(str(host), "wait", env=env, timeout=45)
    assert output.read_text() == "probe_loaded=1\nmodule_match=0\n", output.read_text()
    assert output.stat().st_mode & 0o777 == 0o600
    print("PASS: wrong/missing module refused; report permissions 0600", flush=True)
