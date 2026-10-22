#!/usr/bin/env python3
"""Exercise the real transport with a test-only adapter, never WeChat."""
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import selectors
import socket
import stat
import subprocess
import tempfile
import time
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]


def start(executable, credential, port=0):
    child = subprocess.Popen(
        [str(executable), str(credential), str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    ready = selector.select(5)
    line = child.stdout.readline().strip() if ready else ""
    selector.close()
    if not line.startswith("port="):
        child.terminate()
        _, error = child.communicate(timeout=5)
        raise AssertionError("fixture did not start: " + error)
    return child, int(line.split("=", 1)[1])


def stop(child):
    child.terminate()
    child.communicate(timeout=5)
    assert child.returncode == 0, "fixture did not stop cleanly"


with tempfile.TemporaryDirectory(prefix="wct-transport-tests-") as directory:
    directory = Path(directory)
    executable = directory / "server"
    source = ROOT / "Native/Bridge"
    subprocess.run(
        [
            "/usr/bin/clang++",
            "-std=c++17",
            "-fobjc-arc",
            "-framework",
            "Foundation",
            "-Wall",
            "-Wextra",
            "-Werror",
        ]
        + [
            str(source / name)
            for name in [
                "Protocol.mm",
                "Credentials.mm",
                "Server.mm",
                "ServerFixture.mm",
            ]
        ]
        + ["-o", str(executable)],
        check=True,
    )
    credential = directory / "private/token"
    child, port = start(executable, credential)
    try:
        metadata = credential.stat()
        assert (
            metadata.st_uid == os.getuid() and stat.S_IMODE(metadata.st_mode) == 0o600
        )
        token = credential.read_text()
        assert len(token) == 64

        def request(target, auth=True, headers=None, method="GET"):
            supplied = {"Authorization": "Bearer " + token} if auth else {}
            supplied.update(headers or {})
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=7)
            connection.request(method, target, headers=supplied)
            response = connection.getresponse()
            body = json.loads(response.read())
            assert response.getheader("Cache-Control") == "no-store"
            assert response.getheader("Access-Control-Allow-Origin") is None
            connection.close()
            return response.status, body

        nonce = "b" * 64
        status, health = request("/health?challenge=" + nonce, auth=False)
        assert status == 200 and health["protocol"] == 1
        expected = hmac.new(
            token.encode(), ("wechattweak-health-v1:" + nonce).encode(), hashlib.sha256
        ).hexdigest()
        assert hmac.compare_digest(health["proof"], expected), "health proof mismatch"
        epoch = health["session"]
        for _ in range(10):
            assert request("/wechat/search", auth=False)[0] == 401
            assert (
                request("/wechat/search", headers={"Authorization": "Bearer wrong"})[0]
                == 401
            )
            assert (
                request(
                    "/wechat/search", headers={"Origin": "https://example.invalid"}
                )[0]
                == 403
            )
            status, body = request("/wechat/search?keyword=fixture&usePinyin=1&fuzzy=1")
            assert status == 200 and body["items"][0]["arg"] == "fixture_0"
        with socket.create_connection(("127.0.0.1", port), timeout=4) as fragmented:
            fragmented.sendall(b"GET /wechat/search HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthoriz")
            time.sleep(0.01)
            fragmented.sendall(("ation: Bearer " + token + "\r\n\r\n").encode())
            assert b"200" in fragmented.recv(4096).split(b"\r\n", 1)[0]
        print("PASS: 40 mixed authorization requests and fragmented header", flush=True)
        assert request("/wechat/search?keyword=%E4")[0] == 400
        assert request("/wechat/search?" + urlencode({"keyword": "中" * 342}))[0] == 400
        assert len(request("/wechat/search?keyword=many")[1]["items"]) == 100
        assert (
            request("/health", auth=False, headers={"Host": "attacker.invalid"})[0]
            == 400
        )
        assert request("/health", auth=False, method="POST")[0] == 405
        assert (
            request(
                "/wechat/start?" + urlencode({"session": "fixture_0", "epoch": epoch})
            )[0]
            == 200
        )
        assert request("/wechat/start?session=fixture_0&epoch=old")[0] == 409
        print("PASS: protocol bounds, native result cap and stale epoch", flush=True)
        contender = subprocess.run(
            [str(executable), str(directory / "unused/token"), str(port)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert contender.returncode != 0 and not (directory / "unused/token").exists()
        assert (
            credential.read_text() == token
        ), "existing credential changed on port collision"
        print("PASS: occupied port fails without touching credentials", flush=True)
        began = time.monotonic()
        assert request("/wechat/search?keyword=timeout")[0] == 504
        assert (
            4.5 <= time.monotonic() - began < 6.0
        ), "operation deadline was not enforced"
        with socket.create_connection(("127.0.0.1", port), timeout=4) as slow:
            slow.sendall(b"GET /health HTTP/1.1\r\nHost:")
            assert b"408" in slow.recv(4096).split(b"\r\n", 1)[0]
        print("PASS: operation and slow-header timeouts", flush=True)
    finally:
        stop(child)
    child, reopened = start(executable, credential, port)
    try:
        assert reopened == port
        assert (
            request(
                "/wechat/start?" + urlencode({"session": "fixture_0", "epoch": epoch})
            )[0]
            == 409
        )
        assert credential.read_text() == token, "credential did not survive restart"
        print("PASS: graceful stop, immediate rebind and restart epoch", flush=True)
    finally:
        stop(child)
