# Stable account identity investigation — 269602 arm64

Status: static candidate found; same-account process restart and logged-out refusal observed in temporary copies. Different-account validation and immutable-field semantics remain unverified. This document does not enable account persistence.

- Module UUID: CDB81058-0FAC-3518-95F5-C0CC7860F9B5.
- Global manager `0x9e66158`, vtable `0x98c53d0`; current account shared pointer at manager `+0x68`, copied by `0x42afe5c` with a control-block retain.
- Account vtable `0x98ba858`: slot `+0x10` loads `[this+0x40]`; slot `+0x18` (`0x419ac60`) returns `this+0x48`; slot `+0x20` returns `this+0x60`. The latter two are adjacent 24-byte string candidates. Numeric versus string field semantics still require proof.
- Manager slot `+0x28` (`0x42b614c`) obtains the account shared pointer, calls account slot `+0x18`, releases shared ownership and returns the string reference. `PreferencePageAccount` population at `0x123a510` calls this manager slot. This connects the candidate with the current account settings UI; it does not alone establish an immutable username.
- `0x4197cb0` accesses `this+0x318` with lazy initialization and file/config fallback. It is a separate string and must not be assumed to be account identity.
- Research probe reads the `+0x48` candidate on the main queue, checks LoginState, manager/account vtables and getter bytes. It never calls a guessed native function, retains a foreign pointer across callbacks, or writes raw account data. Output is availability and a domain-separated HMAC for equality comparisons only.

Required evidence before production: username semantics (including distinction from editable alias/display name), same-account restart stability, logged-out refusal, different-account separation, ownership/thread synchronization. Probe comparison key is temporary and separate from future production scope keys. Runtime tests must use a temporary copy while the formal installation is stopped, with user coordination.

## Runtime evidence — 2026-10-22

The user authorized normal exit of the formal installation and temporary-copy login/logout/restart validation. No message APIs were invoked and no raw identity was printed.

- Two temporary processes produced valid candidates with the same comparison digest, using one temporary private HMAC key. Each process had only one distinct valid comparison value.
- First process: 63 unavailable samples followed by 3 available samples before termination during startup diagnosis.
- Second process: 3 unavailable samples, 24 available samples, then 4 unavailable samples. The UI returned to the login screen after an account-security re-login notice. This establishes refusal after that logout; it is not an explicit user-initiated account-switch test.
- `doctor` independently reported `not_logged_in` after the second process returned to login.
- The user has no second test account and explicitly chose to retain the unverified limitation. Do not mark cross-account isolation as runtime passed or enable persistent account-bound features on this evidence alone.
- Only the temporary application's payload was changed. The temporary copy was stopped after testing and its normal bridge restored; the formal installation was launched again unchanged.

## Startup observation and probe initialization

The first startup exceeded the UI automation timeout. A stack sample showed the WeChat custom loader performing file opens and extended-attribute checks before loading the business module. The process subsequently produced valid samples, so the initial UI timeout was not proof of a permanent deadlock.

The research probe now defers all Foundation/NSBundle work to the main queue, matching the production Host constructor. The next temporary launch reached the login UI, but the unchanged formal application also experienced a UI timeout on restoration. Therefore early NSBundle initialization is a plausible contributing difference, not a proven sole root cause. Keep the safer deferred initialization, and do not add startup bypass patches on this evidence.
