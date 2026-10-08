# 示例插件 (IriX Native Plugin)

这是一个演示 IriX **原生插件系统** 的示例插件。它展示了：

- 通过 **C ABI** 与 IriX 宿主通信（宿主不依赖 Rust 具体 ABI）。
- 导出约定的函数：`plugin_init`、`plugin_name`、`plugin_version`、`plugin_handle_event`、`plugin_shutdown`。
- 宿主向插件派发事件（如 `instance.started`、`backup.completed`）时，插件返回 JSON 结果。
- 所有跨边界数据用 **JSON 字符串** 传递。

## 构建

在 `plugins/example_plugin/` 目录执行：

```bash
cargo build --release
```

然后运行打包脚本将产物改名为插件包约定文件名并打成 zip：

- Windows: `.\build_and_package.ps1`
- Linux/macOS: `./build_and_package.sh`

## 插件包结构

打包后得到的 `irix-example-plugin.zip` 结构如下：

```
irix-example-plugin.zip
├── README.md
├── manifest.json
└── lib/
    └── plugin.windows-x64.dll   # 平台对应
```

插件清单中 `entry` 字段为 `plugin`，宿主据此在当前平台下寻找 `lib/plugin.<platform>.<ext>`。

## 行为

当宿主派发 `instance.started` 等事件时，插件会返回类似：

```json
{
  "plugin": "irix-example-plugin",
  "handled_event": "instance.started",
  "received_payload": { "instance_id": "..." },
  "timestamp_ms": 1710000000000
}
```
