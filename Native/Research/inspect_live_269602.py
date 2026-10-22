"""LLDB-only read-only cache check. Prints aggregate evidence, never contacts.

Import with `command script import /absolute/path/inspect_live_269602.py`
after attaching to the explicitly prepared temporary copy. The process must be
stopped. No target expressions or native functions are executed.
"""

import json
from pathlib import Path

import lldb

EXPECTED_UUID = "CDB81058-0FAC-3518-95F5-C0CC7860F9B5"
COPY = Path("/tmp/wechattweak-runtime-inventory/WeChat.app").resolve()
MAX_ROWS = 30000


def inspect():
    target = lldb.debugger.GetSelectedTarget()
    process = target.GetProcess()
    if process.GetState() != lldb.eStateStopped:
        raise RuntimeError("requires a stopped temporary-copy process")
    executable = Path(target.GetExecutable().fullpath).resolve()
    if executable != COPY / "Contents/MacOS/WeChat":
        raise RuntimeError("refusing any executable except the prepared temporary copy")
    modules = [
        module
        for module in target.modules
        if Path(module.file.fullpath).resolve()
        == COPY / "Contents/Resources/wechat.dylib"
    ]
    if len(modules) != 1 or modules[0].GetUUIDString().upper() != EXPECTED_UUID:
        raise RuntimeError("269602 arm64 module UUID does not match")
    base = modules[0].GetObjectFileHeaderAddress().GetLoadAddress(target)

    def read(address, size):
        error = lldb.SBError()
        data = process.ReadMemory(address, size, error)
        if not error.Success() or len(data) != size:
            raise RuntimeError("unreadable research object; no capability established")
        return data

    def pointer(address):
        return int.from_bytes(read(address, 8), "little")

    def string(address):
        data = read(address, 24)
        if data[23] & 128:
            length = int.from_bytes(data[8:16], "little")
            if length > 4096:
                raise RuntimeError("unexpected string length")
            data = read(int.from_bytes(data[:8], "little"), length) if length else b""
        else:
            if data[23] > 22:
                raise RuntimeError("unexpected inline string length")
            data = data[: data[23]]
        return data.decode("utf8")

    def nodes(address):
        declared = pointer(address + 24)
        if declared > MAX_ROWS:
            raise RuntimeError("unexpected collection size")
        node = pointer(address + 16)
        seen = set()
        result = []
        while node:
            if node in seen or len(seen) >= MAX_ROWS:
                raise RuntimeError("cyclic or oversized collection")
            seen.add(node)
            result.append(node)
            node = pointer(node)
        if len(result) != declared:
            raise RuntimeError("collection layout/count mismatch")
        return result

    # Proven by getter instructions 0x42af2f0, 0x42afe5c, 0x4198600.
    manager = pointer(base + 0x9E66158)
    if not manager or pointer(manager) != base + 0x98C53D0:
        raise RuntimeError("manager unavailable or has unexpected type")
    account = pointer(manager + 0x68)
    if not account or pointer(account) != base + 0x98BA858:
        raise RuntimeError("account manager unavailable or has unexpected type")
    factory = pointer(account + 0x368)
    if not factory or pointer(factory) != base + 0x98B87F8:
        raise RuntimeError("service registry unavailable or has unexpected type")
    registry = nodes(factory + 0x70)
    storages = []
    for node in registry:
        value = pointer(node + 0x28)
        if value and pointer(value) == base + 0x98B92D8:
            storages.append(value)
    if len(storages) != 1:
        raise RuntimeError("requires exactly one contact storage")
    storage = storages[0]
    contacts = nodes(storage + 0x98)
    fields = {
        "id": 8,
        "alias": 0x20,
        "remark": 0x60,
        "nickname": 0xA8,
        "remarkPinyin": 0x78,
        "remarkInitials": 0x90,
        "nicknameInitials": 0xC0,
        "nicknamePinyin": 0xD8,
    }
    present = dict.fromkeys(fields, 0)
    ids_match = 0
    builtin_verified = False
    for node in contacts:
        key = string(node + 0x10)
        record = pointer(node + 0x28)
        if not record:
            raise RuntimeError("null cached contact")
        values = {name: string(record + offset) for name, offset in fields.items()}
        ids_match += bool(key and values["id"] == key)
        for name, value in values.items():
            present[name] += bool(value)
        if key == "filehelper":
            builtin_verified = values["id"] == "filehelper" and values["nickname"] in {
                "文件传输助手",
                "文件傳輸助手",
                "File Transfer",
            }
    print(
        json.dumps(
            {
                "moduleMatched": True,
                "registeredServices": len(registry),
                "cachedContacts": len(contacts),
                "matchingStableIDs": ids_match,
                "nonemptyFields": present,
                "builtinVerified": builtin_verified,
                "fullEnumerationVerified": False,
                "openChatVerified": False,
            }
        )
    )


inspect()
