# Native research tools

These tools are experiments, not the contacts bridge. They do not establish
support for searching contacts or opening chats.

`Research/inspect_269602.py MODULE NEW_OUTPUT_DIRECTORY` reads the pristine
269602 module, checks its full SHA-256, and writes Qt metadata and candidate
vtables as JSON. It does not load or call WeChat. Run it with Python 3.9+:

```sh
rtk proxy python3 Native/Research/inspect_269602.py \
  /Applications/WeChat.app/Contents/Resources/wechat.dylib /tmp/wct-qt-inventory
```

`Probes/load_probe.c` exits the host process immediately. Use it only with
the disabled-entry disposable copy described in the research record.

`Probes/object_inventory.c` is a different, read-only runtime experiment. It
requires `WCT_INVENTORY_OUTPUT` to name a new absolute output file, waits 30
seconds on the main queue, and checks the loaded arm64 business module's UUID.
Only after that match does it enumerate allocated heap ranges and count candidate
vtable pointers in their first 64 bytes. This includes objects after shared-pointer
control blocks. Counts are observations, not owned object references or verified
service instances; they can include another structure containing the same pointer.
The report contains only fixed type labels, counts and error states, with mode
0600. It refuses existing files and symlinks. No object methods, contact fields,
network endpoints or chat actions are invoked. Heap scanning can briefly pause
allocation; it is not intended for routine use.

Do not inject either probe into the user's normal installation. A runtime
experiment requires a prepared copy and coordination of the active WeChat session
to prevent simultaneous access to account storage. The original installation is
kept unchanged. The inventory probe has run successfully in a logged-in temporary copy after
fixing a custom-zone reader failure; see the research record. This does not
validate any contacts API.

For debugger-only repeated research, `wct_inventory_snapshot(path)` runs a fresh
main-thread snapshot into a new report. `wct_inventory_candidate(index)` exposes
the first observed pointer only to the debugger, never in the report. Such a
pointer is not retained, can be stale as soon as execution resumes, and is not
a verified service handle. Do not call unknown WeChat methods through it.

The following test compiles both the inventory and a disposable host, and never
launches WeChat. It checks ordinary and prefixed allocations, exclusion after
free, missing-module refusal, output-file permissions and refusal to overwrite
files or follow symlinks. It takes about 35 seconds:

```sh
rtk proxy python3 tools/test_native_probes.py
```

The heap introspection interfaces are documented in Apple's SDK `malloc.h` and
[libmalloc source](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/malloc.c).
The Qt metadata layout was cross-checked against the
[Qt 5.15 private metadata header](https://github.com/qt/qtbase/blob/5.15/src/corelib/kernel/qmetaobject_p.h).

`Research/inspect_live_269602.py` is an LLDB import that only reads a stopped
prepared-copy process. It checks the executable path and module UUID, walks the
service registry and checks cached contact IDs and schema-backed fields. It prints
aggregate counts and built-in verification flags, never contact names or IDs.
A cache snapshot does not establish full database coverage.

`Probes/open_chat_probe.c` is an explicit, main-thread research operation for the
fixed built-in `filehelper` target. It checks UUID, entry bytes and application
vtable before using the call convention observed at two real native callers.
The call returning `1` means invocation only. Confirm it with the selected-session
model and the real UI. The probe has opened File Transfer successfully without
typing or sending a message; it is not a general chat API or production bridge.
