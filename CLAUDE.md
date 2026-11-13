# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build / Test / Lint

```bash
# Rust FFI libs (must recompile after any Rust change)
cargo build --release --manifest-path rust/Cargo.toml
# Windows: double-click build_rust.bat | Linux/macOS: ./build_rust.sh
# Scripts auto-copy .dll/.so/.dylib to platform directories

flutter pub get
flutter run
flutter analyze          # lint check — run before committing
flutter test             # FFI tests need Rust libs pre-built
flutter test test/knowledge_ffi_test.dart   # single test

# Release builds
flutter build windows --release
flutter build linux --release    # needs ./build_rust.sh first
flutter build macos --release    # needs ./build_rust.sh first
```

## Architecture

### Navigation hub

`HomeScreen` is the root, using a `NavigationRail` with 6 tabs:

| Index | Tab | Screen |
|-------|-----|--------|
| 0 | 实例列表 | Instance list (in-widget, not separate screen) |
| 1 | 节点管理 | `NodesScreen` |
| 2 | 内网穿透 | `FrpScreen` |
| 3 | 数据库 | `DatabaseScreen` |
| 4 | 市场 | `MarketplaceScreen` |
| 5 | AI 助手 | `AiScreen` |

All sub-pages (instance detail, config editor, file manager, DB detail, etc.) are pushed via `Navigator.push` — use `pushPage<T>(context, builder)` from `apple_widgets.dart` for consistent transitions. Dialogs use `showAppDialog<T>(context, builder)`.

### State management

Two `ChangeNotifier` providers at the root (`main.dart`):
- **`AppState`** — all server instances, running processes (`ServerProcessManager` per instance), selected instance, download thread count. Persisted via `InstanceStore` → `DatabaseManager` → SQLite.
- **`NodeState`** — all remote nodes (MCSManager panel / IriX Go daemon), persisted via `DatabaseManager` → SQLite.

Access with `context.read<AppState>()` / `context.watch<AppState>()`. Never hold global state inside widgets.

### Data flow: Store → Manager → SQLite

All persistence goes through `DatabaseManager` (singleton, `sqflite_common_ffi`). Domain-level stores (`InstanceStore`, `NodeStore`, etc.) wrap `DatabaseManager` with typed models and in-memory caching. Settings live in the `settings` key-value table (accessed via `DatabaseManager.instance.getSetting/setSetting`). No `SharedPreferences` anywhere.

### Rust FFI layer

Thirteen Rust crates compiled as separate `.dll`/`.so`/`.dylib` files (plus two rlib-only support crates: `time_base`, `time_tls`). Dart FFI wrappers in `lib/services/`:

| Crate | Dart wrapper | Purpose |
|-------|-------------|---------|
| `backup` | `backup_ffi.dart` → `backup_manager.dart` | Instance backup: full (parallel ZIP) + incremental (rsync hardlink snapshots / SHA-256 + CAS) |
| `downloader` | `downloader.dart` | HTTP streaming/chunked download with resume |
| `http_client` | `http_ffi.dart` | General HTTP (GET/POST/PUT/PATCH/DELETE/HEAD) |
| `file_ops` | `file_ops_ffi.dart` | File scan, move, trash |
| `db_client` | `db_client_ffi.dart` | MySQL/MariaDB/PostgreSQL/Redis remote DB |
| `logger` | `logger_ffi.dart` | Rust-side logging |
| `vector_store` | `knowledge_ffi.dart` | Milvus vector embeddings store (milvus-sdk-rust) |
| `nbt` | `nbt_ffi.dart` | Minecraft NBT encode/decode + tree editing |
| `devlog` | `devlog_ffi.dart` | Developer-mode full log persistence |
| `plugin_host` | `plugin_ffi.dart` | Native plugin host: C ABI loader, event dispatch, permission checks |
| `orchestrator` | `orchestrator_ffi.dart` | K8s-style instance orchestration (reconcile, self-heal, autoscale) |
| `device_auth` | `device_auth_ffi.dart` | Client device binding: ed25519/P-256 signing, HMAC request proofs, DPAPI-protected key |
| `time` | `time_ffi.dart` → `time_service.dart` | Unified clock: NTP (rusty_time-core), drift compensation, TSC precision, TLS time provider |

**All HTTP goes through Rust** — `HttpFfiService` for general requests, `Downloader.downloadFile` for large files. Do NOT add `package:http` in Dart. Exception: local loopback servers (OAuth callback, MCP server) use `dart:io HttpServer`.

**All remote DB goes through Rust** — `DbClientFfi.instance.request()` with op string. `RemoteDatabaseService` is the sole business-logic entry point for DB operations. Do NOT add Dart DB client packages.

### Unified time system (`xmc_time`)

Every "now" in the app must come from the same time authority. `rust/time` builds
`xmc_time.dll` (cdylib), `rust/time_base` is an rlib with `zeitstempel`, calendar/HTTP
date helpers and the cross-DLL bridge, `rust/time_tls` is an rlib with the rustls
`TimeProvider`.

- **Clock model**: `app_time = anchor_unix + (mono - anchor_mono) * (1 + rate_ppm*1e-6) + drain`.
  The OS clock is read once at startup and never adjusted; `zeitstempel` provides the
  monotonic axis; `high_water` prevents intra-process backwards steps (freezes at most 5s).
- **NTP**: `rusty_time-core` supplies the NTPv4 codec, weighted regression filter and
  discipline loop. The crate adds UDP I/O, CSPRNG nonce anti-spoofing, response validation
  (origin, mode, stratum, leap, RTT bounds, Kiss-o'-Death), multi-source falseticker
  selection, and `poll_drain` scheduling.
- **Drift**: a 4-state Kalman filter (offset, frequency, daily aging, temperature
  coefficient) replaces the old regression-frequency model. It fuses NTP offsets with
  temperature and history; `clock.rate = freq + temp_coeff*(T - T_ref)`. Aging is a state,
  so holdover continues to evolve; `KalmanSnapshot` persists frequency/aging/temp
  coefficient across restarts. The per-source regression is retained only for
  falseticker pre-screening and step/drain policy.
- **Batch timestamps**: NTP t1/t4 use `precise::batch_stamp(9)` — 9 TSC/monotonic pairs,
  MAD outlier rejection, residual-based uncertainty fed into the Kalman R.
- **Temperature**: Linux reads thermal/hwmon sysfs; Windows/macOS accept FFI
  `time_request("temperature", …)`; EMA + 60s throttle. Temperature is a covariate, not
  a claim that the sensor equals crystal temperature.
- **GNSS**: `Service::ingest_gnss` + FFI `time_request("gnss_sample", …)` accept
  Android GPS/BeiDou samples (`utc_ns`, `mono_ns`, `uncertainty_ns`, constellation, SV
  count, fix, leap seconds, discontinuity). Stale mono (>2s), invalid fixes and >50ms
  uncertainty are rejected; 2D/low-SV are down-weighted. GNSS feeds the same Kalman
  filter, so it can drive the clock without NTP. Cross-device samples require
  `transport_delay_ns`; same-device native Android uses the JNI bridge
  (`TimeNative` + `libxmc_time.so` arm64) in `D:\Irix-android`. 32-bit/x86 ABIs and the
  Android rustls TimeProvider remain to be integrated; see
  `docs/android-gnss-time-calibration.md`.
- **Physical limit**: 24h error = ppm × 86.4ms; 1ms/day needs <0.0116ppm residual. The
  code can reach ms-level only with a stable TCXO/OCXO and good thermal sensing; a
  motherboard crystal + CPU sensor realistically lands at a few-to-tens of ms/day.
- **Accuracy**: same quartz as the OS, so absolute accuracy is bounded by NTP paths; the win
  is independence from a wrong/unsynced/jumping OS clock plus better filtering, monotonicity
  and TSC resolution. `status.system_skew_ms` reports app clock minus OS clock.
- **Precision**: on x86_64, `high_precision_clock` (TSC) interpolates between
  `zeitstempel` samples (least-squares fit, 250ms sampling, 100µs sanity reset,
  auto-disable). NTP t1/t4 additionally use batch sampling with MAD rejection. Other
  architectures fall back to `zeitstempel`.
- **HTTPS**: `xmc_time_tls::client_config()` builds a rustls config with
  `builder_with_details(ring_provider, AppTimeProvider)`, so certificate
  `notBefore`/`notAfter` are judged by the NTP-disciplined clock. `http_client` and
  `downloader` set it on their ureq agents. HTTP `Date` headers are only reported as
  `date_skew_ms` — never used to steer the clock.
- **Dart**: `TimeService.instance` is the only entry point (`nowUnixMs`, `nowUnixSeconds`,
  `nowUnixMicros`, `nowUtc`, `nowLocal`, `httpDate`, `syncNow`, `probe`, `configure`). FFI ops go through
  `TimeFfi`/`time_request`; hot paths use the exported `xmc_time_now_unix_ms/ns` symbols.
  Use it for login/device-proof timestamps (`DeviceAuthProtocol.timestampText`), challenge
  expiry, TOTP, token expiry, migration deadlines, backup/log timestamps. UI display and
  pure ID naming may still use `DateTime.now()`.
- **Cross-DLL**: each FFI DLL statically links its own copy of Rust code, so
  `xmc_time_base::link` loads `xmc_time.dll` at runtime and calls its C exports; if the
  DLL is absent it falls back to a monotonic-anchored system-time estimate.
- **Tests**: `cargo test -p xmc_time_base -p xmc_time -p xmc_time_tls` and
  `flutter test test/time_ffi_test.dart` (local UDP NTP mock, no public network).
  Full design: `docs/time-system.md`.


### Instance backup: full + incremental (all in Rust)

`backup` (`xmc_backup`) owns both backup kinds; Dart never walks/copies files itself.
The instance "备份" tab (`screens/instance_backup_tab.dart`) has **exactly two action
buttons**: 全量备份 (full) and 增量备份 (incremental). Below them is a read-only backup
history list — tapping a row opens a dialog with restore / verify / delete.

- **Repository layout** (per instance, via `AppPaths.instanceBackupsRoot(id)` →
  `<data root>/backups/<instance id>/`): `full/` (ZIP + summary), `snapshots/<name>/`
  (hardlink trees), `cas/<xx>/<sha256>` (content-addressed objects), `meta/`
  (snapshot summary + manifest), `temp/` (rsync logs, CAS temp files).
- **Full backup** = the original feature: the whole instance directory is Deflate
  compressed in parallel (rayon) into one ZIP (`backup_directory` still exported for
  compatibility). Restore unzips it back (zip-slip guarded).
- **Incremental backup**, chosen by platform inside Rust:
  - Linux/macOS — `rsync -rlpt --checksum --link-dest=<previous snapshot> <src>/ <snapshot>/`
    so unchanged files become hardlinks into the previous snapshot. `--checksum` is
    mandatory: the default quick check (size plus second-granularity mtime) silently
    misses same-size edits made within one second and would hardlink stale content.
    `--info=progress2` is used when rsync ≥ 3.1 (parsed from a redirected log file
    for progress); when rsync is missing or fails, Rust falls back to its own
    hardlink snapshot, which compares size plus nanosecond mtime.
  - Windows — SHA-256 per file (`sha2`), content objects stored once under `cas/`
    (dedupe across snapshots), snapshot = manifest of path → hash. Deleting a
    snapshot runs a GC pass that removes unreferenced objects.
- **FFI**: single entry `backup_request(op, argsJson, progressCb) -> *mut c_char`
  returning `{"ok":true,"data":{…}}` / `{"ok":false,"error":…,"cancelled":bool}`;
  ops: `status`, `full_create`, `full_restore`, `full_delete`, `snapshot_create`,
  `snapshot_restore`, `snapshot_verify`, `snapshot_delete`, `gc`. `backup_ffi.dart`
  runs it in a background isolate with a `NativeCallable` progress callback and
  `cancel_backup()`; `backup_manager.dart` is the business entry point (paths,
  models, progress mapping).
- **Tests**: `cargo test -p xmc_backup` (CAS dedupe/GC, hardlink snapshots, ZIP
  roundtrip, name traversal rejection) and `test/backup_ffi_test.dart`.

### Adding a new Rust crate

When adding a crate, update ALL of these:
1. `rust/Cargo.toml` — workspace `members`
2. `build_rust.bat` and `build_rust.sh` — copy step
3. `linux/CMakeLists.txt` — install .so to bundle
4. `windows/runner/CMakeLists.txt` — copy .dll
5. `macos/Runner.xcodeproj/project.pbxproj` — dylib copy + code sign
6. `.github/workflows/build-and-test.yml` and `.github/workflows/package.yml`

Then run `dart tool/ffi_dlls.dart lists` — it checks every list above against
`rust/Cargo.toml` (CI runs the same check). The tool skips rlib-only members
(`time_base`, `time_tls`), so only crates declaring `crate-type = [..., "cdylib"]`
need entries in the seven manifest files. Missing an entry is how v1.2.0 shipped
a Windows installer with only 3 of 8 `xmc_*.dll`, breaking the marketplace with
"Rust http_client library not found".

Release builds also fail loudly on a missing FFI library (`windows/runner/check_rust_dlls.cmake`,
`linux/CMakeLists.txt`), and each packaging job re-checks the built bundle with
`dart tool/ffi_dlls.dart bundle <bundle dir> --ext .dll`. Note that `fastforge package`
runs `flutter clean` + rebuild, so manually copying libs into `build/` has no effect —
CMake / the Xcode build phase own that copy.

### Native plugin system

`plugin_host` (`xmc_plugin_host`) lets IriX load **precompiled native plugins** shipped
as zip packages; the UI is `lib/screens/plugins_screen.dart` (entry: "插件" tool tile on
the instance page), backed by `plugin_service.dart` → `plugin_ffi.dart`.

- **Package format**: `manifest.json` + `README.md` + `lib/<entry>.<platform>.<ext>`
  (e.g. `lib/plugin.windows-x64.dll`). `entry` defaults to `plugin`.
- **C ABI** (plugins must export): `plugin_init() -> i32`, `plugin_name()`,
  `plugin_version()`, `plugin_handle_event(type, payload) -> *const c_char`,
  `plugin_shutdown()`. All cross-boundary data is JSON strings — never structs.
- **String ownership**: plugins allocate returned strings with `libc::malloc`; the host
  frees them with `libc::free` (host-allocated strings returned to Dart use the usual
  `free_string`).
- **FFI exports**: `plg_init(base_dir, host_version)`, `plg_list`, `plg_detail`,
  `plg_readme`, `plg_install(zip_path)`, `plg_uninstall`, `plg_toggle(id, enabled)`,
  `plg_dispatch(event_type, payload)`, `plg_shutdown`.
- **Lifecycle**: a loaded native library is never safely unloadable, so *disable* only
  flags state (no more events); *uninstall* marks `pending_restart` and queues real file
  deletion for the next startup (`.pending-delete.json`).
- **Security**: `manifest.permissions` is checked by the host before dispatch; events map
  to required permissions in `registry.rs::event_required_permissions`. Native plugins run
  in-process with **no sandbox** — the install UI shows a risk confirmation. Plugin
  signatures are future work.
- **Isolation**: every plugin call is wrapped in `catch_unwind`; a panicking/erroring
  plugin is marked `crashed` and never called again, without affecting others.
- **Example plugin**: `plugins/example_plugin/` (standalone crate, not a workspace member
  since it is shipped as a zip rather than bundled as an FFI lib); package with
  `build_and_package.ps1`. FFI flow test: `test/plugin_ffi_test.dart`.

### Client device binding (irix-node v1.4.0+)

`device_auth` (`xmc_device_auth`) implements the client half of irix-node's
`docs/device-binding.md`: every install gets an ed25519 (or P-256) key pair whose
private half never leaves Rust (`dev_auth_request(op, args)`), Windows seals it with
DPAPI (`keyProtection=os-keychain`), other platforms use a 0600 file (`file`).

- **Dart layers**: `device_auth_ffi.dart` (FFI) → `device_auth.dart` (keys, sign,
  HMAC, binding records in settings `node_device_bindings`, TLS-fingerprint TOFU) →
  `device_auth_canonical.dart` (byte-exact canonical strings / descriptor) →
  `node_device_service.dart` (bind / unbind / revoke orchestration).
- **Login**: when a binding exists for the node, `NodeApiClient._login()` requests a
  `login` challenge, verifies `tlsFingerprint` **before** signing or sending the
  password, signs `irix-device-login-v1\n…`, and requires `deviceBound=true` in the
  response (no silent downgrade to password-only).
- **Per-request proof**: `deviceBound` sessions attach `X-Device-Id`,
  `X-Session-Timestamp`, `X-Session-Seq`, `X-Session-Proof`
  (`base64url(HMAC-SHA256(proofKey, "irix-proof-v1\nMETHOD\nrequestURI\nts\nseq"))`)
  to every request including the WebSocket handshake. `requestURI` must be the exact
  bytes sent — `Uri.replace(queryParameters: {})` produces a trailing `?` and breaks
  the MAC, so `_uri()` keeps bare paths bare.
- **Failure handling**: server texts (`设备绑定校验失败` / `必须使用已绑定设备`) become
  `NodeDeviceBindingException`; requests are never retried without proofs.
- **UI**: node card ⋮ → "设备管理" (`node_devices_dialog.dart`: list / revoke / bind) and
  a device section inside `node_credentials_dialog.dart` (bind / local unbind).
- **Tests**: `test/device_auth_ffi_test.dart` (keys, signatures, HMAC vs
  `package:cryptography`, DPAPI roundtrip) and `test/node_device_binding_test.dart`
  (local mock irix-node v1.4 server that verifies signatures, proof headers, seq
  window, TLS-fingerprint mismatch).

### Key UI conventions

- Dark theme only (`Brightness.dark`, green seed color, Material 3)
- `AppleButton` from `apple_widgets.dart` for primary actions — provides press-down scale animation
- Use `pushPage()` / `showAppDialog()` from `apple_widgets.dart` instead of raw `Navigator.push` / `showDialog`
- ID generation: `TimeService.instance.nowUnixMicros().toRadixString(36)` + random suffix — see `AppState._generateId()`

### Server instance lifecycle

`ServerInstance` model holds id, name, rootPath, coreFilePath, startCommand, coreType/Version. `ServerProcessManager` wraps a `Process` — owned by `AppState._managers` map keyed by instance id. Starting a server spawns the process; stdin/stdout/stderr are piped through the manager. Output is persisted to `logs/` under the instance root via `LogPersistence`.

### Database management pages

Two screens for remote DB:
- **`DatabaseScreen`** — connection list (CRUD + test). Connections stored in `db_connections` SQLite table via `RemoteDatabaseService`.
- **`DatabaseDetailScreen`** — browse databases → tables → data (paginated, editable), execute SQL, manage DB users. User management exists both as a top card and as a dialog (opened from the connection info card's "用户管理" button). Redis path is read-only key browsing.

### MCP server

`McpServer` runs a local HTTP server (`dart:io`) for external AI tools to inspect/control instances. Sensitive operations trigger a global permission dialog in `HomeScreen`. Test environments skip MCP startup (`FLUTTER_TEST=true`).

### Test conventions

- Pure Dart unit tests: `test/` root
- FFI integration tests: `test/*_ffi_test.dart` — need Rust libs pre-built and copied
- Full integration tests: `integration_test/`
- Tests use `package:http` only for local loopback servers started by the test itself
