// 配置文件编辑器界面
// 提供图形表单与原始文本两种编辑模式，支持 YAML 和 Properties 文件。
// 左侧为文件列表，右侧为编辑区域。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/config_annotation_service.dart';
import '../services/config_service.dart';
import '../utils/apple_widgets.dart';
import '../utils/code_highlight.dart';

/// 配置编辑器界面。
///
/// 接收实例根目录路径，扫描其中的配置文件并以图形表单或文本形式编辑。
class ConfigEditorScreen extends StatefulWidget {
  const ConfigEditorScreen({super.key, required this.rootPath, this.initialFilePath});

  /// 实例根目录路径。
  final String rootPath;

  /// 要初始打开的文件路径（可选）。
  final String? initialFilePath;

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  final ConfigService _service = ConfigService();

  /// 扫描到的配置文件列表。
  List<ConfigFileInfo> _files = [];

  /// 当前选中的文件索引。
  int _selectedIndex = 0;

  /// 当前文件的可变配置数据。
  Map<String, dynamic> _configData = {};

  /// 是否处于文本编辑模式。
  bool _textMode = false;

  /// 文本编辑控制器。
  final HighlightTextEditingController _textController =
      HighlightTextEditingController();

  /// 搜索框控制器。
  final TextEditingController _searchController = TextEditingController();

  /// 当前搜索关键词（小写），为空表示未搜索。
  String _searchQuery = '';

  /// 是否有未保存的修改。
  bool _dirty = false;

  final ScrollController _gutterScrollController = ScrollController();

  /// 文本编辑器的撤销栈。
  final List<String> _undoStack = [];

  /// 切换文件/模式前记录的上一个文本内容，用于撤销。
  String _previousText = '';

  /// 防止撤销操作本身再次入栈。
  bool _undoing = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _previousText = _textController.text;
  }

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    _gutterScrollController.dispose();
    super.dispose();
  }

  /// 扫描配置文件列表。
  void _loadFiles() {
    final initialPath = widget.initialFilePath;
    setState(() {
      _files = _service.scanConfigFiles(widget.rootPath);
      _selectedIndex = 0;
      _dirty = false;
    });
    if (_files.isNotEmpty) {
      int idx = 0;
      if (initialPath != null) {
        idx = _files.indexWhere((f) => f.path == initialPath);
        if (idx < 0) idx = 0;
      }
      _loadFile(idx);
    } else {
      setState(() {
        _configData = {};
      });
    }
  }

  /// 加载指定索引的配置文件。
  void _loadFile(int index) {
    if (index < 0 || index >= _files.length) return;
    final file = _files[index];
    try {
      final data = _service.readConfig(file.path);
      final raw = _service.readRaw(file.path);
      setState(() {
        _selectedIndex = index;
        _configData = data;
        _textController.fileName = file.name;
        _textController.text = raw;
        _textMode = false;
        _dirty = false;
        _undoStack.clear();
        _previousText = raw;
      });
      _resetGutterScroll();
    } catch (e) {
      // 解析失败时回退到文本模式。
      final raw = _service.readRaw(file.path);
      setState(() {
        _selectedIndex = index;
        _configData = {};
        _textController.fileName = file.name;
        _textController.text = raw;
        _textMode = true;
        _dirty = false;
        _undoStack.clear();
        _previousText = raw;
      });
      _resetGutterScroll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析失败，已切换到文本模式：$e')),
        );
      }
    }
  }

  /// 保存当前配置。
  void _save() {
    if (_files.isEmpty) return;
    final file = _files[_selectedIndex];
    try {
      if (_textMode) {
        _service.writeRaw(file.path, _textController.text);
      } else {
        _service.writeConfig(file.path, _configData);
      }
      setState(() => _dirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存 ${file.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  /// 标记数据已修改。
  void _markDirty() {
    setState(() => _dirty = true);
  }

  void _resetGutterScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gutterScrollController.hasClients) {
        _gutterScrollController.jumpTo(0);
      }
    });
  }

  /// 文本编辑器内容变更回调，同时记录撤销栈。
  void _onTextChanged(String newText) {
    if (_undoing) {
      _undoing = false;
      _markDirty();
      return;
    }
    if (_previousText != newText) {
      _undoStack.add(_previousText);
      _previousText = newText;
      _markDirty();
    }
  }

  /// 撤销上一次文本变更。
  void _undo() {
    if (_undoStack.isEmpty) return;
    _undoing = true;
    final oldText = _undoStack.removeLast();
    _textController.text = oldText;
    _textController.selection = TextSelection.collapsed(offset: oldText.length);
    _previousText = oldText;
    _undoStack.removeWhere((_) => false);
    setState(() => _dirty = true);
  }

  /// 导入 CSV 注释文件。
  ///
  /// CSV 格式：`key,description` (第一行可为表头)。
  /// 导入后覆盖硬编码注释，持久化到本地文件。
  Future<void> _importCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final content = await File(result.files.single.path!).readAsString();
      final count = await ConfigAnnotationService.instance.importCsv(content);
      if (!mounted) return;
      // 刷新表单以显示新注释
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $count 条注释')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  /// 切换文件时的未保存提示。
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('未保存的修改'),
        content: const Text('当前文件有未保存的修改，是否丢弃？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('丢弃'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '实例目录中暂无配置文件',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('启动服务器后会生成配置文件'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadFiles,
              icon: const Icon(Icons.refresh),
              label: const Text('重新扫描'),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // 左侧：文件列表
        SizedBox(
          width: 220,
          child: Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.folder, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '配置文件',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: '重新扫描',
                        onPressed: () async {
                          if (await _confirmDiscard()) _loadFiles();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.upload_file, size: 18),
                        tooltip: '导入CSV注释',
                        onPressed: _importCsv,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final selected = index == _selectedIndex;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: Icon(
                          file.type == ConfigFileType.yaml
                              ? Icons.description
                              : Icons.settings,
                          size: 20,
                        ),
                        title: Text(
                          file.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () async {
                          if (index == _selectedIndex) return;
                          if (await _confirmDiscard()) _loadFile(index);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // 右侧：编辑区域
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                // 工具栏
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        _files[_selectedIndex].name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      if (_dirty)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const Spacer(),
                      // 表单/文本切换
                      ToggleButtons(
                        isSelected: [!_textMode, _textMode],
                        constraints: const BoxConstraints(
                          minHeight: 32,
                          minWidth: 48,
                        ),
                        children: const [
                          Icon(Icons.list_alt, size: 18),
                          Icon(Icons.code, size: 18),
                        ],
                        onPressed: (index) {
                          setState(() => _textMode = index == 1);
                          if (_textMode) {
                            _textController.text =
                                _service.readRaw(_files[_selectedIndex].path);
                            _undoStack.clear();
                            _previousText = _textController.text;
                            _resetGutterScroll();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.undo, size: 20),
                        tooltip: '撤销',
                        onPressed:
                            _textMode && _undoStack.isNotEmpty ? _undo : null,
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _dirty ? _save : null,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('保存'),
                      ),
                    ],
                  ),
                ),
                // 搜索框（仅表单模式显示）
                if (!_textMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                        hintText: '搜索配置项（中英文均可）',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value.trim().toLowerCase());
                      },
                    ),
                  ),
                const Divider(height: 1),
                // 编辑区域
                Expanded(
                  child: _textMode
                      ? _buildTextEditor()
                      : _buildFormEditor(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 文本编辑模式。
  Widget _buildTextEditor() {
    final text = _textController.text;
    final lineCount = '\n'.allMatches(text).length + 1;
    const lineH = 19.5;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 48,
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: ListView.builder(
                  controller: _gutterScrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: lineCount,
                  itemExtent: lineH,
                  itemBuilder: (context, index) {
                    return Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFF6A737D),
                          height: 1.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (_gutterScrollController.hasClients) {
                  _gutterScrollController.jumpTo(
                    notification.metrics.pixels,
                  );
                }
                return false;
              },
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(8),
                ),
                onChanged: _onTextChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图形表单编辑模式。
  Widget _buildFormEditor() {
    if (_configData.isEmpty) {
      return const Center(
        child: Text('该文件为空或无法解析为表单，请切换到文本模式编辑'),
      );
    }
    // 搜索模式：递归收集匹配的叶节点，扁平化展示。
    if (_searchQuery.isNotEmpty) {
      final fileName = _files[_selectedIndex].name;
      final results = <_SearchResult>[];
      _collectSearchResults(
        data: _configData,
        keyPath: '',
        fileName: fileName,
        query: _searchQuery,
        results: results,
      );
      if (results.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text('未找到匹配「$_searchQuery」的配置项'),
            ],
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final r = results[index];
          return _ConfigField(
            key: ValueKey('search-${r.keyPath}'),
            fileName: fileName,
            keyPath: r.keyPath,
            fieldKey: r.keyPath,
            value: r.value,
            onChanged: r.onChanged,
          );
        },
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: _configData.entries.map((entry) {
        return _ConfigField(
          key: ValueKey('${_files[_selectedIndex].name}-${entry.key}'),
          fileName: _files[_selectedIndex].name,
          keyPath: entry.key,
          fieldKey: entry.key,
          value: entry.value,
          onChanged: (newValue) {
            _configData = Map<String, dynamic>.from(_configData)
              ..[entry.key] = newValue;
            _markDirty();
          },
        );
      }).toList(),
    );
  }

  /// 递归收集匹配搜索词的叶节点。
  ///
  /// 匹配规则：配置项路径（keyPath）或中文说明包含搜索词（不区分大小写）。
  /// Map/List 会被展开，只收集可直接编辑的叶节点（bool/int/double/string）。
  void _collectSearchResults({
    required dynamic data,
    required String keyPath,
    required String fileName,
    required String query,
    required List<_SearchResult> results,
  }) {
    // 修改值时通过 dot 路径写回 _configData 并标记脏。
    void updateValue(dynamic newValue) {
      _setNestedValue(_configData, keyPath, newValue);
      _markDirty();
    }

    if (data is Map) {
      data.forEach((k, v) {
        final childPath = keyPath.isEmpty
            ? k.toString()
            : '$keyPath.${k.toString()}';
        _collectSearchResults(
          data: v,
          keyPath: childPath,
          fileName: fileName,
          query: query,
          results: results,
        );
      });
      return;
    }
    if (data is List) {
      for (var i = 0; i < data.length; i++) {
        final childPath = '$keyPath[$i]';
        _collectSearchResults(
          data: data[i],
          keyPath: childPath,
          fileName: fileName,
          query: query,
          results: results,
        );
      }
      return;
    }
    // 叶节点：判断是否匹配
    final desc = ConfigAnnotationService.instance.get(fileName, keyPath) ?? '';
    if (keyPath.toLowerCase().contains(query) ||
        desc.toLowerCase().contains(query)) {
      results.add(_SearchResult(
        keyPath: keyPath,
        value: data,
        onChanged: updateValue,
      ));
    }
  }

  /// 根据 dot 路径设置嵌套 Map/List 中的值。
  ///
  /// 路径格式如 `a.b.c` 或 `a.b[0].c`。
  void _setNestedValue(dynamic root, String keyPath, dynamic newValue) {
    final segments = <String>[];
    final regex = RegExp(r'([^.\[\]]+)|\[(\d+)\]');
    for (final match in regex.allMatches(keyPath)) {
      segments.add(match.group(0)!);
    }
    if (segments.isEmpty) return;
    dynamic current = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      final idx = int.tryParse(seg.replaceAll(RegExp(r'[\[\]]'), ''));
      if (idx != null) {
        current = (current as List)[idx];
      } else {
        current = (current as Map)[seg] as dynamic;
      }
    }
    final last = segments.last;
    final lastIdx = int.tryParse(last.replaceAll(RegExp(r'[\[\]]'), ''));
    if (lastIdx != null) {
      (current as List)[lastIdx] = newValue;
    } else {
      (current as Map)[last] = newValue;
    }
  }
}

/// 搜索结果项。
class _SearchResult {
  final String keyPath;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  _SearchResult({
    required this.keyPath,
    required this.value,
    required this.onChanged,
  });
}

/// 单个配置字段的编辑控件。
///
/// 根据值类型自动选择合适的控件：
/// - bool → Switch
/// - int → 数字输入框
/// - double → 数字输入框
/// - String → 文本输入框
/// - Map → 可折叠的嵌套表单
/// - List → 列表展示
///
/// 使用 StatefulWidget 持有 TextEditingController，避免在 build 中
/// 创建新 controller 导致光标位置重置。
class _ConfigField extends StatefulWidget {
  const _ConfigField({
    super.key,
    required this.fileName,
    required this.keyPath,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });

  /// 配置文件名（用于查找中文说明）。
  final String fileName;

  /// 完整配置项路径（如 `anticheat.obfuscation.enabled`）。
  final String keyPath;

  /// 当前层级显示的键名。
  final String fieldKey;

  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_ConfigField> createState() => _ConfigFieldState();
}

class _ConfigFieldState extends State<_ConfigField> {
  /// 文本输入框的控制器，在 State 中持久化。
  late TextEditingController _controller;

  /// 焦点节点，用于判断是否正在编辑。
  final FocusNode _focusNode = FocusNode();

  /// 当前字段的中文说明 (含 CSV 导入的注释)。
  String? get description =>
      ConfigAnnotationService.instance.get(widget.fileName, widget.keyPath);

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _ConfigField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在外部值变更且字段未聚焦时同步文本，避免编辑时光标跳动。
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 构建中文说明文本（如果有）。
  Widget? _buildDescription() {
    if (description == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        description!,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    // bool → Switch
    if (value is bool) {
      return _buildSwitchRow(context, value);
    }
    // int → 数字输入
    if (value is int) {
      return _buildIntField(context);
    }
    // double → 数字输入
    if (value is double) {
      return _buildDoubleField(context);
    }
    // Map → 嵌套表单
    if (value is Map) {
      return _buildNestedForm(context, value);
    }
    // List → 简单列表展示
    if (value is List) {
      return _buildListField(context, value);
    }
    // 默认 → 文本输入
    return _buildStringField(context, value);
  }

  /// bool 字段：Switch 开关。
  Widget _buildSwitchRow(BuildContext context, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.fieldKey,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Switch(
                value: value,
                onChanged: (v) => widget.onChanged(v),
              ),
            ],
          ),
          if (_buildDescription() != null) _buildDescription()!,
        ],
      ),
    );
  }

  /// int 字段：数字输入框。
  Widget _buildIntField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: widget.fieldKey,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (text) {
              final parsed = int.tryParse(text);
              if (parsed != null) widget.onChanged(parsed);
            },
          ),
          if (_buildDescription() != null) _buildDescription()!,
        ],
      ),
    );
  }

  /// double 字段：数字输入框。
  Widget _buildDoubleField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: widget.fieldKey,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) widget.onChanged(parsed);
            },
          ),
          if (_buildDescription() != null) _buildDescription()!,
        ],
      ),
    );
  }

  /// String 字段：文本输入框。
  Widget _buildStringField(BuildContext context, dynamic value) {
    // 尝试识别 "true"/"false" 字符串，转为 Switch
    if (value == 'true' || value == 'false') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.fieldKey,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Switch(
                  value: value == 'true',
                  onChanged: (v) => widget.onChanged(v ? 'true' : 'false'),
                ),
              ],
            ),
            if (_buildDescription() != null) _buildDescription()!,
          ],
        ),
      );
    }
    // 普通字符串（含纯数字字符串）
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: widget.fieldKey,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            keyboardType: int.tryParse(value?.toString() ?? '') != null
                ? TextInputType.number
                : TextInputType.text,
            onChanged: (text) => widget.onChanged(text),
          ),
          if (_buildDescription() != null) _buildDescription()!,
        ],
      ),
    );
  }

  /// Map 字段：可折叠的嵌套表单。
  Widget _buildNestedForm(BuildContext context, Map map) {
    return ExpansionTile(
      dense: true,
      title: Text(
        widget.fieldKey,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: description != null
          ? Text(description!, style: TextStyle(fontSize: 12, color: Colors.grey[600]))
          : null,
      initiallyExpanded: false,
      childrenPadding: const EdgeInsets.only(left: 16),
      children: map.entries.map((entry) {
        return _ConfigField(
          key: ValueKey('${widget.keyPath}-${entry.key}'),
          fileName: widget.fileName,
          keyPath: '${widget.keyPath}.${entry.key}',
          fieldKey: entry.key.toString(),
          value: entry.value,
          onChanged: (newValue) {
            // 更新嵌套 Map 中的值
            final newMap = Map<String, dynamic>.from(map);
            newMap[entry.key.toString()] = newValue;
            widget.onChanged(newMap);
          },
        );
      }).toList(),
    );
  }

  /// List 字段：列表展示。
  Widget _buildListField(BuildContext context, List list) {
    return ExpansionTile(
      dense: true,
      title: Text(
        '${widget.fieldKey} (${list.length} 项)',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: description != null
          ? Text(description!, style: TextStyle(fontSize: 12, color: Colors.grey[600]))
          : null,
      initiallyExpanded: false,
      childrenPadding: const EdgeInsets.only(left: 16),
      children: list.asMap().entries.map((entry) {
        return _ConfigField(
          key: ValueKey('${widget.keyPath}-${entry.key}'),
          fileName: widget.fileName,
          keyPath: '${widget.keyPath}.${entry.key}',
          fieldKey: '${widget.fieldKey}[${entry.key}]',
          value: entry.value,
          onChanged: (newValue) {
            final newList = List<dynamic>.from(list);
            newList[entry.key] = newValue;
            widget.onChanged(newList);
          },
        );
      }).toList(),
    );
  }
}
