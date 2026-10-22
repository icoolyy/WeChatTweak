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
kept unchanged. Injection of the inventory probe into real WeChat has not yet
been validated.

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
