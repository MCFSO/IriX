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

Seven Rust crates compiled as separate `.dll`/`.so`/`.dylib` files. Dart FFI wrappers in `lib/services/`:

| Crate | Dart wrapper | Purpose |
|-------|-------------|---------|
| `backup` | `backup_ffi.dart` | ZIP parallel compress/decompress |
| `downloader` | `downloader.dart` | HTTP streaming/chunked download with resume |
| `http_client` | `http_ffi.dart` | General HTTP (GET/POST/PUT/PATCH/DELETE/HEAD) |
| `file_ops` | `file_ops_ffi.dart` | File scan, move, trash |
| `db_client` | `db_client_ffi.dart` | MySQL/MariaDB/PostgreSQL/Redis remote DB |
| `logger` | `logger_ffi.dart` | Rust-side logging |
| `vector_store` | `vector_store_ffi.dart` | Vector embeddings store (sqlite-vec) |

**All HTTP goes through Rust** — `HttpFfiService` for general requests, `Downloader.downloadFile` for large files. Do NOT add `package:http` in Dart. Exception: local loopback servers (OAuth callback, MCP server) use `dart:io HttpServer`.

**All remote DB goes through Rust** — `DbClientFfi.instance.request()` with op string. `RemoteDatabaseService` is the sole business-logic entry point for DB operations. Do NOT add Dart DB client packages.

### Adding a new Rust crate

When adding a crate, update ALL of these:
1. `rust/Cargo.toml` — workspace `members`
2. `build_rust.bat` and `build_rust.sh` — copy step
3. `linux/CMakeLists.txt` — install .so to bundle
4. `windows/runner/CMakeLists.txt` — copy .dll
5. `macos/Runner.xcodeproj/project.pbxproj` — dylib copy + code sign
6. `.github/workflows/build-and-test.yml` and `.github/workflows/package.yml`

### Key UI conventions

- Dark theme only (`Brightness.dark`, green seed color, Material 3)
- `AppleButton` from `apple_widgets.dart` for primary actions — provides press-down scale animation
- Use `pushPage()` / `showAppDialog()` from `apple_widgets.dart` instead of raw `Navigator.push` / `showDialog`
- ID generation: `DateTime.now().microsecondsSinceEpoch.toRadixString(36)` + random suffix — see `AppState._generateId()`

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
