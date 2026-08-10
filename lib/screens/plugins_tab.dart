// 插件 / Mod 管理卡片页
// 扫描实例 /plugins/ 与 /mods/ 目录下的 .jar 文件，
// 从 jar 中提取名称与图标（Fabric / Forge / Bukkit 均兼容），
// 以卡片形式展示（一行约三个），点击进入该插件 / Mod 的配置目录，
// 复用配置编辑器进行管理，工具栏提供返回与保存。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/jar_metadata_service.dart';
import 'config_editor_screen.dart';

/// 插件 / Mod 管理卡片页。
///
/// 在实例详情页的第三个 Tab 中展示。
class PluginsTab extends StatefulWidget {
  const PluginsTab({super.key, required this.rootPath});

  final String rootPath;

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab> {
  /// 扫描到的所有条目（插件 + Mod + 孤立配置目录）。
  List<_PluginItem> _items = [];

  /// 是否正在加载（扫描 jar 元数据）。
  bool _loading = true;

  /// 当前选中的条目。非空时进入配置编辑详情视图。
  _PluginItem? _selected;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  /// 扫描插件与 Mod，异步读取 jar 元数据。
  Future<void> _scan() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final root = widget.rootPath;
    final items = <_PluginItem>[];

    // —— 插件 /plugins/*.jar ——
    final pluginsDir = Directory(p.join(root, 'plugins'));
    final pluginJarNames = <String>{};
    if (pluginsDir.existsSync()) {
      final jars = pluginsDir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.jar'))
          .toList();
      final metas = await Future.wait(
        jars.map((j) => JarMetadataService.read(j.path)),
      );
      for (var i = 0; i < jars.length; i++) {
        final jar = jars[i];
        final meta = metas[i];
        final rawName = p.basenameWithoutExtension(jar.path);
        final displayName = meta.name?.isNotEmpty == true
            ? meta.name!
            : rawName;
        pluginJarNames.add(displayName.toLowerCase());
        pluginJarNames.add(rawName.toLowerCase());
        final configDir = _resolvePluginConfigDir(root, rawName, meta.name);
        items.add(
          _PluginItem(
            kind: _ItemKind.plugin,
            displayName: displayName,
            rawName: rawName,
            jarPath: jar.path,
            meta: meta,
            configDir: configDir,
            hasConfig: configDir != null,
          ),
        );
      }
    }

    // —— Mod /mods/*.jar ——
    final modsDir = Directory(p.join(root, 'mods'));
    if (modsDir.existsSync()) {
      // mods 目录可能含子目录（如 1.20.1/），递归查找 .jar
      final jars = _listJarsRecursive(modsDir);
      final metas = await Future.wait(
        jars.map((j) => JarMetadataService.read(j.path)),
      );
      for (var i = 0; i < jars.length; i++) {
        final jar = jars[i];
        final meta = metas[i];
        final rawName = p.basenameWithoutExtension(jar.path);
        final displayName = meta.name?.isNotEmpty == true
            ? meta.name!
            : rawName;
        final modId = _extractModId(meta, rawName);
        final configDir = _resolveModConfigDir(root, modId, displayName);
        items.add(
          _PluginItem(
            kind: _ItemKind.mod,
            displayName: displayName,
            rawName: rawName,
            jarPath: jar.path,
            meta: meta,
            configDir: configDir?.dir,
            configFilter: configDir?.filter,
            hasConfig: configDir != null,
          ),
        );
      }
    }

    // —— 孤立插件配置目录（/plugins/ 下的子目录，无对应 jar）——
    if (pluginsDir.existsSync()) {
      for (final e in pluginsDir.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (name.toLowerCase().startsWith('.')) continue;
        if (pluginJarNames.contains(name.toLowerCase())) continue;
        items.add(
          _PluginItem(
            kind: _ItemKind.plugin,
            displayName: name,
            rawName: name,
            jarPath: null,
            meta: const JarMetadata(),
            configDir: e.path,
            hasConfig: true,
            orphan: true,
          ),
        );
      }
    }

    // 排序：插件在前，Mod 在后；同类按名称。
    items.sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      if (k != 0) return k;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 递归列出目录下所有 .jar 文件（mod 目录常含版本子目录）。
  List<File> _listJarsRecursive(Directory dir) {
    final result = <File>[];
    for (final e in dir.listSync(followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.jar')) {
        result.add(e);
      } else if (e is Directory) {
        result.addAll(_listJarsRecursive(e));
      }
    }
    return result;
  }

  /// 解析插件配置目录：优先匹配元数据名称，其次 jar 文件名。
  String? _resolvePluginConfigDir(
    String root,
    String rawName,
    String? metaName,
  ) {
    final candidates = <String>[];
    if (metaName != null && metaName.isNotEmpty) candidates.add(metaName);
    candidates.add(rawName);
    for (final name in candidates) {
      final dir = p.join(root, 'plugins', name);
      if (Directory(dir).existsSync()) return dir;
    }
    return null;
  }

  /// 从元数据或 jar 名中提取 mod 标识（小写，去掉版本后缀）。
  String _extractModId(JarMetadata meta, String rawName) {
    // Fabric 的 id 字段最准确，但 JarMetadata 未单独保存 id；
    // 此处用 name 去掉常见版本后缀作为近似 mod id。
    final base = meta.name?.isNotEmpty == true ? meta.name! : rawName;
    // 去掉形如 -1.20.1 / -fabric / -forge / -build.123 的后缀
    final cleaned = base
        .replaceAll(
          RegExp(r'[-_]\d+\.\d+(?:\.\d+)*.*$', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'[-_](fabric|forge|neoforge|quilt)$', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'[-_](client|server|common)$', caseSensitive: false),
          '',
        );
    return cleaned.isEmpty ? base : cleaned;
  }

  /// 解析 mod 配置目录：优先 `/config/<modId>/`，否则用 `/config/` + 文件名过滤。
  _ConfigRef? _resolveModConfigDir(
    String root,
    String modId,
    String displayName,
  ) {
    final configRoot = p.join(root, 'config');
    // 1. 专用目录 /config/<modId>/
    for (final name in [modId, displayName]) {
      final dir = p.join(configRoot, name);
      if (Directory(dir).existsSync()) {
        return _ConfigRef(dir: dir, filter: null);
      }
    }
    // 2. 散文件：在 /config/ 中搜索包含 modId 的文件
    if (Directory(configRoot).existsSync()) {
      final lowerId = modId.toLowerCase();
      try {
        final hasMatch = Directory(configRoot)
            .listSync(followLinks: false)
            .whereType<File>()
            .any((f) => p.basename(f.path).toLowerCase().contains(lowerId));
        if (hasMatch) {
          return _ConfigRef(dir: configRoot, filter: modId);
        }
      } catch (_) {
        // ignore
      }
    }
    return null;
  }

  /// 点击卡片：进入配置编辑详情。
  void _openItem(_PluginItem item) {
    if (!item.hasConfig) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${item.displayName} 暂无可管理的配置文件')));
      return;
    }
    setState(() => _selected = item);
  }

  /// 返回卡片列表视图。
  void _back() {
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 详情视图：配置编辑器（带返回按钮）
    if (_selected != null) {
      return ConfigEditorScreen(
        key: ValueKey('cfg-${_selected!.configDir}-${_selected!.configFilter}'),
        rootPath: _selected!.configDir!,
        onBack: _back,
        scanAll: true,
        nameFilter: _selected!.configFilter,
      );
    }

    // 列表视图：卡片网格
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('暂无插件 / Mod', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('将插件放入 plugins/、Mod 放入 mods/ 后重新扫描'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh),
              label: const Text('重新扫描'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (_pluginItems.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            sliver: SliverToBoxAdapter(
              child: _sectionHeader('插件', Icons.extension),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _pluginItems[index];
                return _PluginCard(item: item, onTap: () => _openItem(item));
              }, childCount: _pluginItems.length),
            ),
          ),
        ],
        if (_modItems.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            sliver: SliverToBoxAdapter(
              child: _sectionHeader('Mod', Icons.widgets),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _modItems[index];
                return _PluginCard(item: item, onTap: () => _openItem(item));
              }, childCount: _modItems.length),
            ),
          ),
        ],
      ],
    );
  }

  /// 分组标题。
  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  List<_PluginItem> get _pluginItems =>
      _items.where((e) => e.kind == _ItemKind.plugin).toList();
  List<_PluginItem> get _modItems =>
      _items.where((e) => e.kind == _ItemKind.mod).toList();
}

/// 配置目录引用（目录 + 可选文件名过滤词）。
class _ConfigRef {
  const _ConfigRef({required this.dir, this.filter});
  final String dir;
  final String? filter;
}

/// 条目类型。
enum _ItemKind { plugin, mod }

/// 插件 / Mod 卡片条目数据。
class _PluginItem {
  _PluginItem({
    required this.kind,
    required this.displayName,
    required this.rawName,
    required this.jarPath,
    required this.meta,
    required this.configDir,
    required this.hasConfig,
    this.configFilter,
    this.orphan = false,
  });

  final _ItemKind kind;
  final String displayName;
  final String rawName;
  final String? jarPath;
  final JarMetadata meta;
  final String? configDir;
  final String? configFilter;
  final bool hasConfig;

  /// 是否为孤立配置目录（无对应 jar）。
  final bool orphan;
}

/// 单个插件 / Mod 卡片。
class _PluginCard extends StatefulWidget {
  const _PluginCard({required this.item, required this.onTap});

  final _PluginItem item;
  final VoidCallback onTap;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final hasIcon = item.meta.iconBytes != null;
    final kindLabel = item.kind == _ItemKind.plugin ? '插件' : 'Mod';
    final kindColor = item.kind == _ItemKind.plugin
        ? Colors.blue
        : Colors.deepPurple;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 图标
                Expanded(
                  child: Center(
                    child: hasIcon
                        ? _JarIcon(bytes: item.meta.iconBytes!)
                        : Icon(
                            item.kind == _ItemKind.plugin
                                ? Icons.extension
                                : Icons.widgets,
                            size: 48,
                            color: kindColor.withValues(alpha: 0.8),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                // 名称
                Tooltip(
                  message: item.displayName,
                  child: Text(
                    item.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // 类型徽章 + 配置状态
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _KindBadge(label: kindLabel, color: kindColor),
                    if (!item.hasConfig) ...[
                      const SizedBox(width: 6),
                      _KindBadge(label: '无配置', color: Colors.grey),
                    ] else if (item.orphan) ...[
                      const SizedBox(width: 6),
                      _KindBadge(label: '仅配置', color: Colors.orange),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 从 jar 中读取的图标。
class _JarIcon extends StatelessWidget {
  const _JarIcon({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      width: 48,
      height: 48,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image, size: 48, color: Colors.grey),
    );
  }
}

/// 类型 / 状态小徽章。
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
