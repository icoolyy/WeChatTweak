# Stable account identity investigation — 269602 arm64

Status: static candidate found; runtime lifecycle verification pending. This document does not enable account persistence.

- Module UUID: CDB81058-0FAC-3518-95F5-C0CC7860F9B5.
- Global manager `0x9e66158`, vtable `0x98c53d0`; current account shared pointer at manager `+0x68`, copied by `0x42afe5c` with a control-block retain.
- Account vtable `0x98ba858`: slot `+0x10` loads `[this+0x40]`; slot `+0x18` (`0x419ac60`) returns `this+0x48`; slot `+0x20` returns `this+0x60`. The latter two are adjacent 24-byte string candidates. Numeric versus string field semantics still require proof.
- Manager slot `+0x28` (`0x42b614c`) obtains the account shared pointer, calls account slot `+0x18`, releases shared ownership and returns the string reference. `PreferencePageAccount` population at `0x123a510` calls this manager slot. This connects the candidate with the current account settings UI; it does not alone establish an immutable username.
- `0x4197cb0` accesses `this+0x318` with lazy initialization and file/config fallback. It is a separate string and must not be assumed to be account identity.
- Research probe reads the `+0x48` candidate on the main queue, checks LoginState, manager/account vtables and getter bytes. It never calls a guessed native function, retains a foreign pointer across callbacks, or writes raw account data. Output is availability and a domain-separated HMAC for equality comparisons only.

Required evidence before production: username semantics (including distinction from editable alias/display name), same-account restart stability, logged-out refusal, different-account separation, ownership/thread synchronization. Probe comparison key is temporary and separate from future production scope keys. Runtime tests must use a temporary copy while the formal installation is stopped, with user coordination.
