# IriX 1.3.0: Device-Bound Logins and Per-Request Proofs for IriX Nodes

## Summary

IriX 1.3.0 adds client-side device binding for IriX nodes (protocol v1.4.0).
Every installation generates its own device key pair. Logging in to a node now
signs a one-time server challenge with that private key, and every request after
login carries an HMAC proof bound to the session. Accounts configured with the
`required` policy can only log in from a bound device, so a stolen password or a
leaked session token is no longer enough to reach the node.

The private key is created and used inside the native module and never enters the
Dart heap. On Windows it is sealed with DPAPI under the current Windows account;
on other platforms it is stored in a 0600 file. The `keyProtection` value reported
to the node reflects what is actually used.

| Item | Details |
|------|---------|
| What | Device-bound login, per-request session proofs, device management UI |
| When | October 31, 2026 |
| Who | IriX project team |
| For | Minecraft server administrators running IriX nodes |
| Where | GitHub Releases and the official download page |
| Why | Close the gap between "password only" and "password plus a device the user holds" |
| How | Install over the previous version; bind a device from the node card or the credentials dialog |

**One line:** IriX 1.3.0 lets each machine prove it is the machine that was
authorized, on login and on every request that follows.

## Highlights

- Local device keys: ed25519 by default, P-256 supported by the native module.
  Private keys are generated, stored, and used only inside `xmc_device_auth`.
- Password plus signature login: the client signs a 60-second, single-use
  challenge from the node, including the node's TLS certificate fingerprint.
- Per-request proofs: `X-Device-Id`, `X-Session-Timestamp`, `X-Session-Seq`, and
  `X-Session-Proof` are attached to every request and to the WebSocket handshake.
- Replay protection: a monotonic request sequence and the server's 1024-entry
  sliding window reject duplicated or stale proofs. Retries always use a new
  sequence number.
- Trust on first use for TLS: the certificate fingerprint returned by the
  challenge is compared with the value recorded at pairing, before the password
  is sent. A mismatch aborts the login.
- Device management: list bound devices, bind this machine, revoke a device, and
  unbind locally. Revocation requires the account password.
- No silent downgrade: if the node rejects a device login or a session proof, the
  client raises a dedicated error and never retries the request without proofs.

## Changes

### New

- `device_auth` native module (`xmc_device_auth`) providing ed25519 and ECDSA
  P-256 signatures (P1363 `r||s`), HMAC-SHA256, SHA-256, and a system CSPRNG,
  built on `ring` with no OpenSSL dependency.
- Client device protocol implementation: challenge request, device registration,
  password plus signature login, per-request proofs, device list, and revocation.
- Binding records stored per node in the settings table. Only public material is
  persisted: device id, account name, key type, key protection, and the pinned
  TLS fingerprint.
- Device management dialog with device list, current-device marker, bind, and
  revoke actions. A device section was added to the node credentials dialog.
- New entry in the node card menu: "Devices".
- English and Chinese strings for the new UI.
- Tests: native signature and HMAC vectors verified independently with
  `package:cryptography`, plus a local mock IriX node v1.4 server that verifies
  registration signatures, login signatures, proof headers, the sequence window,
  the `required` policy, and TLS fingerprint mismatches.

### Improved

- Node sessions now carry the proof key, device id, and next sequence number for
  device-bound sessions; password-only sessions are unchanged.
- The real-time console WebSocket handshake authenticates with the session token
  in the query string and, for bound sessions, the same proof headers as regular
  requests.
- Node credential changes and node deletion now clear the associated binding
  record so a new node cannot inherit an old device id.

### Fixed

- Requests with no query parameters were serialized with a trailing `?`
  (`/api/overview?`). The signed canonical string then disagreed with the
  request URI observed by the server, and device-bound sessions failed with a 403
  proof error. Bare paths are now kept bare.

## Other changes in this build

- Instance backup was reworked. Full backup still compresses the whole instance
  directory into one ZIP in parallel, and incremental backup is new: Linux and
  macOS create hardlink snapshots with `rsync --link-dest` (falling back to a
  native hardlink snapshot), while Windows uses SHA-256 content-addressed storage
  that deduplicates unchanged files across snapshots and reclaims unreferenced
  objects when a snapshot is deleted. The backup tab now has two actions, full and
  incremental, with a backup history list underneath.
- The `zip` dependency was upgraded to 9.2.0, which addresses three security
  advisories (one critical, one high, one medium) in archive handling.

## Compatibility and upgrade notes

- Device binding requires IriX node v1.4.0 or newer. Older nodes keep working
  with the existing password login.
- Accounts on the `optional` policy need no action. Password login remains the
  default and still works without a bound device.
- Accounts on the `required` policy must have at least one bound device. Bind the
  device before an administrator switches the account to `required`; otherwise
  the node refuses password logins by design.
- Device login requires TLS on the node. Nodes running without TLS reject device
  logins; this is a server-side rule, not a client fallback.
- If the app is moved to another machine, or the Windows account changes, the
  sealed key can no longer be opened. Sign in with the password (on `optional`
  accounts) and bind the new device from the device management dialog.
- The session proof key and sequence number are kept in memory only. Restarting
  the app performs a fresh device-signed login, which is also what makes a lost
  sequence number a non-issue.
- Upgrading is a normal install over the previous version. No database migration
  is required.

## Security notes

Covered by this release:

- Password-only attackers cannot produce a valid login signature without the
  device private key.
- A leaked session token is not usable without the session proof key.
- Replayed requests are rejected by the sequence window and timestamp checks.
- A changed server certificate is detected before the password leaves the client.

Not covered, by design:

- A fully compromised client machine, where the private key is usable.
- Direct writes to the server database, which can replace public keys or policy.
- Tampering with request bodies, which is protected by TLS only.
- A first-contact man-in-the-middle when no fingerprint has been pinned yet. The
  fingerprint is trusted on first use and verified on every later login.

## Known limitations

- TPM 2.0 key storage is not implemented yet. Windows uses DPAPI and reports
  `os-keychain`; other platforms use a 0600 file and report `file`.
- Transport-level certificate pinning is not implemented in the HTTP layer. The
  fingerprint comparison uses the value returned in the challenge response, so it
  protects every login after the first pairing but not the first contact itself.
- The native module supports P-256 keys, but the client currently issues ed25519
  keys. Switching key types requires unbinding and binding again.
- A device list, bind, or revoke action against a node older than v1.4.0 fails
  with a clear error; there is no device support to fall back to.

## Downloads

Installers are built by the Package workflow and the portable archives are the
complete application directory from the Build and Test workflow. Install over the
previous version: settings, instances, and node credentials are kept. Windows users
who installed from the Microsoft Store should use the MSIX package.

| File | Size | SHA-256 |
|------|------|---------|
| irix-1.3.0-windows-x64.exe | 24.8 MB | `f190066c49a1bd6826d00c6a76369c1dc3e951ff5245fe1101d020eb3d6933f9` |
| irix-1.3.0-windows-x64.msix | 37.2 MB | `cfb56eab35976c597a583898a2a7599d62b7ca57cef8144c9a92bd77fc1553ef` |
| irix-1.3.0-windows-x64.zip | 35.1 MB | `22914ab199e9b86ce1727a134fffafca8bda9041cd5c82883eafedb9747768d4` |
| irix-1.3.0-linux-x64.AppImage | 43.7 MB | `e286359a1a0f4f918dba19bf4cfeb225eab20528610151b91ce5335a5798e460` |
| irix-1.3.0-linux-x64.deb | 25.1 MB | `d45332a9b7982970cdd8678ebfbbafe55347301d72e1581c63cd963825dbb698` |
| irix-1.3.0-linux-x64.rpm | 34.1 MB | `d8eae34d367d75dfde3e55f85645ed92a7ff3b310b06256d6bd67b5a54380822` |
| irix-1.3.0-linux-x64.zip | 35.1 MB | `e7b565c70222e1416d80f5209f92164ef74fa7ade58c3f9f0042aa97d9895fa1` |
| irix-1.3.0-macOS-arm64.dmg | 56.5 MB | `8c63acaa4a8a39b3a65ee54eef6ff63de9c0826cd36fe1fcebae5a101414e07a` |
| irix-1.3.0-macOS-arm64.zip | 119.7 MB | `33965cab4bb0576a3dd65a06051ad0bbaa424c5f79616628c9c347b3e0c6c37c` |

The `windows-x64.zip` and `linux-x64.zip` archives unpack into a runnable
directory; the `macOS-arm64.zip` contains `lrix.app`.

## Verification

- `cargo test -p xmc_device_auth`: 10 passed. Covers the device id formula,
  ed25519 and P-256 round trips, an RFC 4231 HMAC vector, SHA-256 vectors, key
  protection round trips, and rejection of tampered key files.
- `flutter test test/device_auth_ffi_test.dart test/node_device_binding_test.dart`:
  17 passed. Native signatures and HMACs are verified independently, and the mock
  node covers registration, login, proofs, sequence numbers, the `required`
  policy, and fingerprint mismatch handling.
- `flutter test`: 302 passed, 3 skipped.
- `dart analyze`: no issues.
- `dart tool/ffi_dlls.dart lists`: all 12 native modules are covered by the build
  scripts, CMake, Xcode, and both CI workflows.
- `flutter build windows --debug`: succeeds, and the output contains all 12
  `xmc_*.dll` files including `xmc_device_auth.dll`.
