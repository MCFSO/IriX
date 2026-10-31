// 插件 / Mod 管理页
// 扫描实例 /plugins/ 与 /mods/ 目录下的 .jar 文件，
// 从 jar 中提取名称与图标（Fabric / Forge / Bukkit 均兼容）。
//
// 展示为「图标 + 名称 + 类型」的自适应多列条目，并做懒加载：
// 每次渲染一批（默认 10 条，可在 设置 → 插件 调整），滚到底部自动追加下一批，
// 新出现的条目带淡入动画。点击条目进入其配置目录，复用配置编辑器管理。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/jar_metadata_service.dart';
import '../services/plugin_view_settings.dart';
import '../utils/flow_packer.dart';
import 'config_editor_screen.dart';
import '../state/app_activity.dart';

/// 插件 / Mod 管理卡片页。
///
/// 在实例详情页的第三个 Tab 中展示。
class PluginsTab extends StatefulWidget {
  const PluginsTab({super.key, required this.rootPath});

  final String rootPath;

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab>
    with AutomaticKeepAliveClientMixin {
  /// 扫描到的所有条目（插件 + Mod + 孤立配置目录）。
  List<_PluginItem> _items = [];

  /// 分组后的插件 / Mod 列表（扫描完成时算好，滚动回调里 O(1) 取长度）。
  List<_PluginItem> _pluginItems = const [];
  List<_PluginItem> _modItems = const [];

  /// 是否正在加载（扫描 jar 元数据）。
  bool _loading = true;

  /// 当前选中的条目。非空时进入配置编辑详情视图。
  _PluginItem? _selected;

  /// 每次请求的条数（持久化在全局设置，默认 10）。
  int _batchSize = PluginViewSettings.defaultBatchSize;

  /// 目标条数：滚动触发后一次性提高，真正渲染由 [_trickle] 逐条喂给界面。
  int _targetPlugins = PluginViewSettings.defaultBatchSize;
  int _targetMods = PluginViewSettings.defaultBatchSize;

  /// 已展示条数（逐条递增，避免一批 10 个在一帧内同时出现造成卡顿）。
  int _revealedPlugins = 0;
  int _revealedMods = 0;

  /// 逐条展示的节拍器。
  Timer? _trickle;

  /// 每条的间隔：默认 45ms（约 22 条/秒），保证每帧只新增 1 个条目。
  static const Duration _trickleInterval = Duration(milliseconds: 45);

  final ScrollController _scroll = ScrollController();

  /// 条目宽度缓存（key 含文本缩放比例），避免每帧重新测量文字。
  final Map<String, double> _widthCache = {};

  /// 防止重复排入「填充视口」检查。
  bool _fillCheckScheduled = false;

  /// 扫描序号：避免连续刷新时旧结果覆盖新结果。
  int _scanToken = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    PluginViewSettings.getBatchSize().then((value) {
      if (!mounted) return;
      setState(() {
        _batchSize = value;
        _targetPlugins = value;
        _targetMods = value;
      });
      _scan();
    });
  }

  @override
  void dispose() {
    _trickle?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// 滚动接近底部时把目标再提高一批（不直接渲染，交给节拍器逐条喂）。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter > 320) return;
    _requestMore();
  }

  /// 是否还有尚未纳入目标的条目。
  bool get _hasMoreTargets =>
      _targetPlugins < _pluginItems.length || _targetMods < _modItems.length;

  /// 是否还有已请求但尚未展示的条目。
  bool get _hasPendingReveal =>
      _revealedPlugins < _targetPlugins || _revealedMods < _targetMods;

  /// 提高目标条数（每次一批），并启动逐条展示。
  ///
  /// 上一批还没展示完就不再追加：滚动再快也只能十个十个地往前推，
  /// 既不会一次性把上千条塞进目标，也不会让节拍器越追越远。
  void _requestMore() {
    if (_hasPendingReveal) return;
    if (!_hasMoreTargets) return;
    setState(() {
      if (_targetPlugins < _pluginItems.length) {
        _targetPlugins = (_targetPlugins + _batchSize).clamp(
          0,
          _pluginItems.length,
        );
      }
      if (_targetMods < _modItems.length) {
        _targetMods = (_targetMods + _batchSize).clamp(0, _modItems.length);
      }
    });
    _startTrickle();
  }

  /// 启动节拍器：每个 tick 只让插件/Mod 各多显示一个条目。
  ///
  /// 这样即使目标是几百条，单帧新增的 Widget 也只有一个，
  /// 不会出现「一批同时插入」的掉帧。
  void _startTrickle() {
    if (_trickle?.isActive ?? false) return;
    if (!_hasPendingReveal) return;
    _trickle = Timer.periodic(_trickleInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // 最小化时不推进展示：45ms 一拍会让后台持续触发重建。
      if (AppActivity.minimized) return;
      var changed = false;
      if (_revealedPlugins < _targetPlugins) {
        _revealedPlugins++;
        changed = true;
      }
      if (_revealedMods < _targetMods) {
        _revealedMods++;
        changed = true;
      }
      if (changed) setState(() {});
      if (_hasPendingReveal) return;

      timer.cancel();
      // 展示完一批后若仍贴着底部，继续推进下一批：
      // 滚动事件在内容增长后不会自动再触发，这里补上，形成连续的下拉流。
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 320 &&
          _hasMoreTargets) {
        _requestMore();
      }
    });
  }

  /// 内容不足以撑出滚动条时，继续请求，避免「没有滚动条就永远加载不到」。
  void _scheduleFillCheck() {
    if (_fillCheckScheduled) return;
    _fillCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillCheckScheduled = false;
      if (!mounted) return;
      final scrollable =
          _scroll.hasClients && _scroll.position.maxScrollExtent > 0;
      if (!scrollable && _hasMoreTargets) _requestMore();
    });
  }

  /// 扫描插件与 Mod。
  ///
  /// 目录枚举在 UI isolate（很快），jar 解压与元数据解析交给 Rust
  /// （`JarMetadataService.readAllInBackground`，后台 isolate + FFI），
  /// 因此切到本页不会阻塞帧。
  Future<void> _scan() async {
    if (!mounted) return;
    final token = ++_scanToken;
    setState(() => _loading = true);

    final root = widget.rootPath;

    // —— 枚举 jar（只做目录遍历，不读内容）——
    final pluginsDir = Directory(p.join(root, 'plugins'));
    final pluginJars = <File>[];
    if (pluginsDir.existsSync()) {
      pluginJars.addAll(
        pluginsDir
            .listSync(followLinks: false)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jar')),
      );
    }

    final modsDir = Directory(p.join(root, 'mods'));
    final modJars = modsDir.existsSync()
        ? _listJarsRecursive(modsDir)
        : <File>[];

    // —— 一次调用解析全部元数据（Rust，后台 isolate）——
    final metas = await JarMetadataService.readAllInBackground([
      for (final f in pluginJars) f.path,
      for (final f in modJars) f.path,
    ]);
    if (!mounted || token != _scanToken) return;

    final items = <_PluginItem>[];
    final pluginJarNames = <String>{};

    for (var i = 0; i < pluginJars.length; i++) {
      final jar = pluginJars[i];
      final meta = i < metas.length ? metas[i] : const JarMetadata();
      final rawName = p.basenameWithoutExtension(jar.path);
      final displayName = meta.name?.isNotEmpty == true ? meta.name! : rawName;
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

    for (var i = 0; i < modJars.length; i++) {
      final jar = modJars[i];
      final metaIndex = pluginJars.length + i;
      final meta = metaIndex < metas.length
          ? metas[metaIndex]
          : const JarMetadata();
      final rawName = p.basenameWithoutExtension(jar.path);
      final displayName = meta.name?.isNotEmpty == true ? meta.name! : rawName;
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

    if (!mounted || token != _scanToken) return;
    _trickle?.cancel();
    _widthCache.clear();
    setState(() {
      _items = items;
      _pluginItems = items.where((e) => e.kind == _ItemKind.plugin).toList();
      _modItems = items.where((e) => e.kind == _ItemKind.mod).toList();
      _loading = false;
      _targetPlugins = _batchSize.clamp(0, _pluginItems.length);
      _targetMods = _batchSize.clamp(0, _modItems.length);
      _revealedPlugins = 0;
      _revealedMods = 0;
    });
    _startTrickle();
    _scheduleFillCheck();
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
    final l = AppLocalizations.of(context);
    if (!item.hasConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.pluginsUI_noConfigFiles(item.displayName))),
      );
      return;
    }
    setState(() => _selected = item);
  }

  /// 返回卡片列表视图。
  void _back() {
    setState(() => _selected = null);
  }

  /// 切到其它页签再回来时不重建、不重新扫描。
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
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
            Text(
              l.pluginsUI_empty,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.pluginsUI_emptyHint),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh),
              label: Text(l.common_refresh),
            ),
          ],
        ),
      );
    }

    _scheduleFillCheck();

    // 行级虚拟化：先把已展示条目按宽度装箱成「行」，再交给 SliverList。
    // 只有视口内的行会被构建，插件上千也不会一次性创建上千个 Widget。
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth - 24; // 左右各 12 内边距
        final scaler = MediaQuery.textScalerOf(context);

        final pluginItems = _pluginItems.take(_revealedPlugins).toList();
        final pluginWidths = <double>[
          for (final item in pluginItems) _measureWidth(item, scaler),
        ];
        final pluginRows = FlowPacker.pack(
          pluginWidths,
          maxWidth: contentWidth,
          spacing: 8,
        );

        final modItems = _modItems.take(_revealedMods).toList();
        final modWidths = <double>[
          for (final item in modItems) _measureWidth(item, scaler),
        ];
        final modRows = FlowPacker.pack(
          modWidths,
          maxWidth: contentWidth,
          spacing: 8,
        );

        return CustomScrollView(
          controller: _scroll,
          slivers: [
            if (_pluginItems.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                sliver: SliverToBoxAdapter(
                  child: _sectionHeader(
                    l.pluginsUI_sectionPlugins,
                    Icons.extension,
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: pluginRows.length,
                itemBuilder: (context, index) =>
                    _buildRow(pluginItems, pluginWidths, pluginRows[index]),
              ),
            ],
            if (_modItems.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                sliver: SliverToBoxAdapter(
                  child: _sectionHeader(l.pluginsUI_sectionMods, Icons.widgets),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 12),
                sliver: SliverList.builder(
                  itemCount: modRows.length,
                  itemBuilder: (context, index) =>
                      _buildRow(modItems, modWidths, modRows[index]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 构建一行条目：宽度取测量值，保证与实际渲染一致，不会溢出。
  Widget _buildRow(
    List<_PluginItem> items,
    List<double> widths,
    List<int> row,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (var i = 0; i < row.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(width: widths[row[i]], child: _fadeItem(items[row[i]])),
          ],
        ],
      ),
    );
  }

  /// 给条目套上淡入动画。
  ///
  /// 条目是逐条出现的（[_trickle]），所以不需要错峰；
  /// key 绑定条目自身路径，已渲染的条目不会因 setState 重播动画。
  Widget _fadeItem(_PluginItem item) {
    return _FadeInItem(
      key: ValueKey(
        '${item.kind.name}-${item.jarPath ?? item.configDir ?? item.displayName}',
      ),
      child: _PluginRow(item: item, onTap: () => _openItem(item)),
    );
  }

  /// 测量条目宽度：图标 + 名称 + 类型徽章 + 内边距。
  ///
  /// 结果按「条目 + 文本缩放」缓存，滚动与逐条展示时不会重复排版文字。
  double _measureWidth(_PluginItem item, TextScaler scaler) {
    final cacheKey =
        '${item.kind.name}|${item.displayName}|${item.hasConfig}|'
        '${item.orphan}|${scaler.scale(10)}';
    final cached = _widthCache[cacheKey];
    if (cached != null) return cached;

    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final nameStyle = theme.textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w500,
    );
    const badgeStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);

    final nameWidth = _textWidth(item.displayName, nameStyle, scaler, 180);
    final kindWidth = _textWidth(
      item.kind == _ItemKind.plugin ? l.pluginsUI_kindPlugin : 'Mod',
      badgeStyle,
      scaler,
      double.infinity,
    );
    var width = 10 + 28 + 8 + nameWidth + 8 + (kindWidth + 14) + 10;

    if (!item.hasConfig) {
      width +=
          4 +
          _textWidth(
            l.pluginsUI_noConfig,
            badgeStyle,
            scaler,
            double.infinity,
          ) +
          14;
    } else if (item.orphan) {
      width +=
          4 +
          _textWidth(
            l.pluginsUI_configOnly,
            badgeStyle,
            scaler,
            double.infinity,
          ) +
          14;
    }

    final result = width.ceilToDouble();
    _widthCache[cacheKey] = result;
    return result;
  }

  /// 单行文本宽度（与渲染使用同一 style / textScaler）。
  double _textWidth(
    String text,
    TextStyle style,
    TextScaler scaler,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    final width = painter.width;
    painter.dispose();
    return width;
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
/// 淡入动画包装：条目首次出现时从透明渐显。
///
/// 条目由节拍器逐条加入（约 45ms 一条），这里不再做错峰延迟，
/// 每条各自淡入即可获得连续的流式观感。
class _FadeInItem extends StatefulWidget {
  const _FadeInItem({super.key, required this.child});

  final Widget child;

  @override
  State<_FadeInItem> createState() => _FadeInItemState();
}

class _FadeInItemState extends State<_FadeInItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// 单个插件/Mod 条目：图标 + 名称 + 类型徽章，宽度随内容自适应。
///
/// 放在 [Wrap] 里使用：每项宽度 = 图标 + 名称 + 类型，一行放不下自动换行，
/// 不再被拉伸成整行宽的长条。名称超过 [_nameMaxWidth] 时省略并给 Tooltip。
class _PluginRow extends StatelessWidget {
  const _PluginRow({required this.item, required this.onTap});

  final _PluginItem item;
  final VoidCallback onTap;

  static const double _iconSize = 28;

  /// 名称最长显示宽度（衬线中文约 12-13 个字），超出省略。
  static const double _nameMaxWidth = 180;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final hasIcon = item.meta.iconBytes != null;
    final kindLabel = item.kind == _ItemKind.plugin
        ? l.pluginsUI_kindPlugin
        : 'Mod';
    final kindColor = item.kind == _ItemKind.plugin
        ? Colors.blue
        : Colors.deepPurple;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _iconSize,
                height: _iconSize,
                child: hasIcon
                    ? _JarIcon(bytes: item.meta.iconBytes!, size: _iconSize)
                    : Icon(
                        item.kind == _ItemKind.plugin
                            ? Icons.extension
                            : Icons.widgets,
                        size: 20,
                        color: kindColor.withValues(alpha: 0.85),
                      ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _nameMaxWidth),
                child: Tooltip(
                  message: item.displayName,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _KindBadge(label: kindLabel, color: kindColor),
              if (!item.hasConfig) ...[
                const SizedBox(width: 4),
                _KindBadge(label: l.pluginsUI_noConfig, color: Colors.grey),
              ] else if (item.orphan) ...[
                const SizedBox(width: 4),
                _KindBadge(label: l.pluginsUI_configOnly, color: Colors.orange),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 从 jar 中读取的图标。
class _JarIcon extends StatelessWidget {
  const _JarIcon({required this.bytes, this.size = 48});

  final Uint8List bytes;

  /// 显示边长（列表行内用 28，详情/旧卡片用 48）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.broken_image, size: size, color: Colors.grey),
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
