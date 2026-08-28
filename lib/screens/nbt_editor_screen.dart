// NBT 编辑器（复刻 AnkiNBT 编辑能力）
//
// 在 IriX 内独立运行的 NBT 编辑工具（IriX 无 Minecraft 运行时，故数据来源为
// 文件/粘贴 NBT 与连运行中的服务器 RCON，而非"玩家手持物品"）。
//
// 顶部领域切换：通用树 / 物品 / 实体 / 村民交易（每个领域含"高级模式"完整 NBT 树
// 与"简易模式"常见字段表单）；另含"连服务器(RCON)"面板用于下发命令。
//
// 导入/导出：.nbt 二进制（gzip，与原 mod 互导）+ SNBT 文本。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/nbt_service.dart';

/// NBT 编辑器主界面。
///
/// [initialBytes] 可选：从外部（如文件管理器打开 .nbt）传入的初始二进制内容。
/// [initialFileName] 可选：导出时建议的文件名。
class NbtEditorScreen extends StatefulWidget {
  final Uint8List? initialBytes;
  final String? initialFileName;

  const NbtEditorScreen({this.initialBytes, this.initialFileName, super.key});

  @override
  State<NbtEditorScreen> createState() => _NbtEditorScreenState();
}

enum _Domain { tree, item, entity, villager, rcon }

extension _DomainMeta on _Domain {
  String get label {
    switch (this) {
      case _Domain.tree:
        return '通用树';
      case _Domain.item:
        return '物品';
      case _Domain.entity:
        return '实体';
      case _Domain.villager:
        return '村民交易';
      case _Domain.rcon:
        return '连服务器';
    }
  }
}

class _NbtEditorScreenState extends State<NbtEditorScreen> {
  NbtNode _root = NbtNode(type: NbtType.compound, children: []);
  String _fileName = 'untitled.nbt';
  bool _loading = true;
  bool _error = false;
  String _errorMsg = '';
  _Domain _domain = _Domain.tree;
  bool _simpleMode = false;

  @override
  void initState() {
    super.initState();
    _fileName = widget.initialFileName ?? 'untitled.nbt';
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      if (widget.initialBytes != null) {
        _root = await NbtService.instance.parseBinaryToTree(widget.initialBytes!);
      } else {
        // 默认空白根 Compound。
        _root = NbtNode(type: NbtType.compound, children: []);
      }
    } catch (e) {
      _error = true;
      _errorMsg = '加载失败：$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // === 导入/导出 ===

  Future<void> _importNbtFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['nbt'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final node = await NbtService.instance.parseBinaryToTree(bytes);
      setState(() {
        _root = node;
        _fileName = result.files.single.name;
        _error = false;
      });
      if (mounted) _toast('已导入 ${result.files.single.name}');
    } catch (e) {
      if (mounted) _toast('导入失败：$e', error: true);
    }
  }

  Future<void> _importSnbt() async {
    final text = await _showSnbtDialog(title: '粘贴 SNBT', multiLine: true);
    if (text == null || text.trim().isEmpty) return;
    try {
      final node = await NbtService.instance.toTree(text.trim());
      setState(() {
        _root = node;
        _error = false;
      });
      if (mounted) _toast('已解析 SNBT');
    } catch (e) {
      if (mounted) _toast('解析失败：$e', error: true);
    }
  }

  Future<void> _exportNbt() async {
    try {
      final bytes = await NbtService.instance.treeToBinary(_root, gzip: true);
      final savePath = await FilePicker.platform.saveFile(
        fileName: _fileName,
        type: FileType.custom,
        allowedExtensions: ['nbt'],
      );
      if (savePath == null) return;
      final path = savePath.endsWith('.nbt') ? savePath : '$savePath.nbt';
      await File(path).writeAsBytes(bytes);
      if (mounted) _toast('已导出 $path');
    } catch (e) {
      if (mounted) _toast('导出失败：$e', error: true);
    }
  }

  Future<void> _viewSnbt() async {
    try {
      final snbt = await NbtService.instance.fromTree(_root);
      await _showSnbtDialog(title: '当前 SNBT', initial: snbt, readOnly: true);
    } catch (e) {
      if (mounted) _toast('生成 SNBT 失败：$e', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null),
    );
  }

  // === 简易模式字段读写 ===

  /// 读取根 Compound 下某路径的标量值（缺省回退 [fallback]）。
  String _field(String path, String fallback) {
    // 简易路径：仅支持 a.b.c / a[index]。
    final node = _find(_root, path);
    if (node == null) return fallback;
    if (node.isContainer) return fallback;
    return node.value?.toString() ?? fallback;
  }

  void _setField(String path, String value) {
    final parts = path.split('.');
    var parent = _root;
    for (var i = 0; i < parts.length - 1; i++) {
      final seg = parts[i];
      var child = parent.children.where((c) => c.name == seg).firstOrNull;
      if (child == null) {
        child = NbtNode(type: NbtType.compound, name: seg, children: []);
        parent.children.add(child);
      }
      parent = child;
    }
    final key = parts.last;
    final existing = parent.children.where((c) => c.name == key).firstOrNull;
    if (existing != null && !existing.isContainer) {
      existing.value = value;
    } else {
      parent.children
          .add(NbtNode(type: NbtType.string, name: key, value: value));
    }
  }

  NbtNode? _find(NbtNode node, String path) {
    return _resolve(node, path.split('/'));
  }

  NbtNode? _resolve(NbtNode node, List<String> parts) {
    var cur = node;
    for (final seg in parts) {
      final (key, idx) = _splitSeg(seg);
      if (cur.type == NbtType.compound) {
        final child = cur.children.where((c) => c.name == key).firstOrNull;
        if (child == null) return null;
        cur = child;
      } else if (cur.type == NbtType.list && idx != null) {
        if (idx < 0 || idx >= cur.children.length) return null;
        cur = cur.children[idx];
      } else {
        return null;
      }
    }
    return cur;
  }

  (String, int?) _splitSeg(String seg) {
    final open = seg.indexOf('[');
    if (open >= 0 && seg.endsWith(']')) {
      final idx = int.tryParse(seg.substring(open + 1, seg.length - 1));
      return (seg.substring(0, open), idx);
    }
    return (seg, null);
  }

  void _rebuildFromTree() => setState(() {});

  // === 构建 ===

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('NBT 编辑器 · $_fileName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: '导入 .nbt',
            onPressed: _importNbtFile,
          ),
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: '粘贴 SNBT',
            onPressed: _importSnbt,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '导出 .nbt',
            onPressed: _exportNbt,
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: '导出/查看 SNBT',
            onPressed: _viewSnbt,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildTabBar(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(child: Text(_errorMsg))
              : _buildBody(),
    );
  }

  Widget _buildTabBar() {
    final domains = _Domain.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in domains)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(d.label),
                selected: _domain == d,
                onSelected: (_) => setState(() => _domain = d),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_domain == _Domain.rcon) {
      return const _RconPanel();
    }
    return Column(
      children: [
        // 模式切换（通用树/物品/实体/村民交易 均有高级+简易）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Text('模式：'),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('高级树')),
                  ButtonSegment(value: true, label: Text('简易模式')),
                ],
                selected: {_simpleMode},
                onSelectionChanged: (s) => setState(() => _simpleMode = s.first),
              ),
              const Spacer(),
              if (!_simpleMode)
                _SearchButton(onSearch: (q) => _search(q)),
            ],
          ),
        ),
        Expanded(
          child: _simpleMode
              ? _buildSimpleForm()
              : _buildAdvancedTree(),
        ),
      ],
    );
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final snbt = await NbtService.instance.fromTree(_root);
      final hits = await NbtService.instance.search(snbt, query, limit: 50);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('搜索结果（${hits.length}）'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final h in hits) ListTile(dense: true, title: Text(h)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      _toast('搜索失败：$e', error: true);
    }
  }

  Widget _buildAdvancedTree() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _TreeNodeWidget(
          node: _root,
          path: '',
          depth: 0,
          onChanged: _rebuildFromTree,
          root: _root,
        ),
      ),
    );
  }

  Widget _buildSimpleForm() {
    switch (_domain) {
      case _Domain.item:
        return _ItemSimpleForm(get: _field, set: _setField, onChanged: _rebuildFromTree);
      case _Domain.entity:
        return _EntitySimpleForm(get: _field, set: _setField, onChanged: _rebuildFromTree);
      case _Domain.villager:
        return _VillagerSimpleForm(get: _field, set: _setField, onChanged: _rebuildFromTree);
      default:
        return const Center(child: Text('通用树模式仅提供高级树编辑。'));
    }
  }

  // === SNBT 弹窗 ===

  Future<String?> _showSnbtDialog({
    required String title,
    String? initial,
    bool multiLine = false,
    bool readOnly = false,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    if (readOnly && initial != null) {
      // 只读展示。
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            readOnly: readOnly || (!multiLine && false),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '{id:"minecraft:diamond",Count:1b}',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 辅助：返回 null（用于 _find 中的早退）。
NbtNode? returnNull() => null;

/// 类型配色（与 AnkiNBT 风格一致）。
Color typeColor(String type) {
  switch (type) {
    case NbtType.byte:
      return const Color(0xFF8B5CF6);
    case NbtType.short:
      return const Color(0xFF6366F1);
    case NbtType.int_:
      return const Color(0xFF3B82F6);
    case NbtType.long:
      return const Color(0xFF0EA5E9);
    case NbtType.float:
      return const Color(0xFF14B8A6);
    case NbtType.double_:
      return const Color(0xFF10B981);
    case NbtType.string:
      return const Color(0xFFF59E0B);
    case NbtType.compound:
      return const Color(0xFFE2E8F0);
    case NbtType.list:
      return const Color(0xFF94A3B8);
    case NbtType.byteArray:
      return const Color(0xFFA78BFA);
    case NbtType.intArray:
      return const Color(0xFF60A5FA);
    case NbtType.longArray:
      return const Color(0xFF38BDF8);
    default:
      return const Color(0xFFCCCCCC);
  }
}

/// 递归渲染 NBT 树节点（展开/折叠、类型着色、增删改）。
class _TreeNodeWidget extends StatefulWidget {
  final NbtNode node;
  final String path;
  final int depth;
  final NbtNode root;
  final VoidCallback onChanged;

  const _TreeNodeWidget({
    required this.node,
    required this.path,
    required this.depth,
    required this.root,
    required this.onChanged,
  });

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> {
  bool _expanded = true;

  NbtNode get _node => widget.node;

  @override
  Widget build(BuildContext context) {
    final color = typeColor(_node.type);
    final hasChildren = _node.isContainer && _node.children.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: widget.depth == 0 ? 0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_node.isContainer)
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(maxWidth: 24),
                  onPressed: () => setState(() => _expanded = !_expanded),
                )
              else
                const SizedBox(width: 24),
              // 名称。
              if (_node.name.isNotEmpty)
                Expanded(
                  child: Text(
                    _node.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Expanded(child: Text('(root)', style: TextStyle(color: Colors.grey))),
              // 类型标签。
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _node.type,
                  style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 6),
              // 操作。
              _actions(),
            ],
          ),
          if (_node.isContainer && _expanded)
            if (hasChildren)
              ..._node.children.map(
                (c) => _TreeNodeWidget(
                  node: c,
                  path: _childPath(c),
                  depth: widget.depth + 1,
                  root: widget.root,
                  onChanged: widget.onChanged,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Text(
                  _node.type == NbtType.list ? '(空列表)' : '(空 Compound)',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }

  String _childPath(NbtNode c) {
    if (_node.type == NbtType.list) {
      final idx = _node.children.indexOf(c);
      return '${widget.path}[$idx]';
    }
    return widget.path.isEmpty ? c.name : '${widget.path}/${c.name}';
  }

  Widget _actions() {
    // 编辑标量值 / 数组。
    if (_node.isScalar || _node.isArray) {
      return IconButton(
        icon: const Icon(Icons.edit, size: 16),
        tooltip: '编辑值',
        onPressed: () => _editValue(context),
      );
    }
    // 容器：添加子节点。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          tooltip: '添加子节点',
          onPressed: () => _addChild(context),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 16),
          tooltip: '删除',
          onPressed: () => _delete(context),
        ),
      ],
    );
  }

  Future<void> _editValue(BuildContext context) async {
    final current = _node.value?.toString() ?? '';
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: current);
        return AlertDialog(
          title: Text('编辑值（${_node.type}）'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (edited == null) return;
    _node.value = edited;
    widget.onChanged();
  }

  Future<void> _addChild(BuildContext context) async {
    // 收集类型与（Compound 所需）键名：合并到单个对话框，避免多次 await 后使用 context。
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) {
        String? type;
        final nameCtl = TextEditingController();
        return StatefulBuilder(
          builder: (stx, setInner) => AlertDialog(
            title: const Text('添加子节点'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('类型'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final t in NbtType.all)
                        ChoiceChip(
                          label: Text(t),
                          selected: type == t,
                          onSelected: (_) => setInner(() => type = t),
                        ),
                    ],
                  ),
                  if (_node.type == NbtType.compound) ...[
                    const SizedBox(height: 12),
                    const Text('键名'),
                    TextField(
                      controller: nameCtl,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, (type ?? NbtType.compound, nameCtl.text.trim())),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    if (!mounted) return;
    final (type, name) = result;
    if (_node.type == NbtType.compound) {
      if (name.isEmpty) return;
      _node.children.add(NbtService.createDefault(type, name: name));
    } else {
      _node.children.add(NbtService.createDefault(type));
    }
    setState(() {});
    widget.onChanged();
  }


  void _delete(BuildContext context) {
    // 从父容器移除自身（根不允许删除）。
    if (_node == widget.root) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('根节点不可删除')),
      );
      return;
    }
    // 在 root 中递归查找父并移除。
    _removeFrom(widget.root, _node);
    widget.onChanged();
  }

  bool _removeFrom(NbtNode parent, NbtNode target) {
    if (parent.children.contains(target)) {
      parent.children.remove(target);
      return true;
    }
    for (final c in parent.children) {
      if (_removeFrom(c, target)) return true;
    }
    return false;
  }
}

// ======================== 简易模式表单 ========================

class _SearchButton extends StatelessWidget {
  final Function(String) onSearch;
  const _SearchButton({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return SizedBox(
      width: 200,
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          hintText: '搜索路径…',
          isDense: true,
          suffixIcon: IconButton(
            icon: const Icon(Icons.search, size: 18),
            onPressed: () => onSearch(c.text),
          ),
        ),
        onSubmitted: onSearch,
      ),
    );
  }
}

/// 简易字段表单：渲染一组常见字段文本/数值/开关输入。
class _SimpleForm extends StatelessWidget {
  final List<Widget> fields;
  const _SimpleForm({required this.fields});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: fields),
      );
}

typedef _GetField = String Function(String path, String fallback);
typedef _SetField = void Function(String path, String value);

Widget _textField(String label, String path, _GetField get, _SetField set, VoidCallback onChanged) {
  final c = TextEditingController(text: get(path, ''));
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (v) {
        set(path, v);
        onChanged();
      },
    ),
  );
}

Widget _boolField(String label, String path, _GetField get, _SetField set, VoidCallback onChanged) {
  final v = get(path, 'false') == 'true';
  return SwitchListTile(
    title: Text(label),
    value: v,
    onChanged: (val) {
      set(path, val ? 'true' : 'false');
      onChanged();
    },
  );
}

class _ItemSimpleForm extends StatelessWidget {
  final _GetField get;
  final _SetField set;
  final VoidCallback onChanged;
  const _ItemSimpleForm({required this.get, required this.set, required this.onChanged});

  @override
  Widget build(BuildContext context) => _SimpleForm(fields: [
        _textField('物品 ID', 'id', get, set, onChanged),
        _textField('数量 Count', 'Count', get, set, onChanged),
        _textField('自定义名称 custom_name', 'components/custom_name', get, set, onChanged),
        _textField(' Lore（逗号分隔）', 'components/lore', get, set, onChanged),
        _boolField('是否损坏 Unbreakable', 'components/unbreakable', get, set, onChanged),
        _boolField('防火 Fire-resistant', 'components/fire_resistant', get, set, onChanged),
        _textField('附魔（JSON 数组）', 'components/enchantments', get, set, onChanged),
        _textField('伤害值 damage', 'components/damage', get, set, onChanged),
      ]);
}

class _EntitySimpleForm extends StatelessWidget {
  final _GetField get;
  final _SetField set;
  final VoidCallback onChanged;
  const _EntitySimpleForm({required this.get, required this.set, required this.onChanged});

  @override
  Widget build(BuildContext context) => _SimpleForm(fields: [
        _textField('自定义名称 CustomName', 'CustomName', get, set, onChanged),
        _textField('生命值 Health', 'Health', get, set, onChanged),
        _boolField('静音 Silent', 'Silent', get, set, onChanged),
        _boolField('发光 Glowing', 'Glowing', get, set, onChanged),
        _boolField('无重力 NoGravity', 'NoGravity', get, set, onChanged),
        _boolField('无敌 Invulnerable', 'Invulnerable', get, set, onChanged),
        _textField('已捕获 Poicounted', 'Poicounted', get, set, onChanged),
      ]);
}

class _VillagerSimpleForm extends StatelessWidget {
  final _GetField get;
  final _SetField set;
  final VoidCallback onChanged;
  const _VillagerSimpleForm({required this.get, required this.set, required this.onChanged});

  @override
  Widget build(BuildContext context) => _SimpleForm(fields: [
        _textField('职业 profession', 'profession', get, set, onChanged),
        _textField('等级 level（经验）', 'level', get, set, onChanged),
        _textField('村民类型 type', 'type', get, set, onChanged),
        _textField('交易数量 Offers（JSON）', 'Offers', get, set, onChanged),
      ]);
}

// ======================== RCON 面板（阶段 3 占位） ========================

class _RconPanel extends StatelessWidget {
  const _RconPanel();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '连服务器（RCON）面板将在阶段 3 接入：\n'
            '在此输入 host/port/password 连接开启了 RCON 的服务器，\n'
            '并把当前编辑的 NBT 经 /give、/data merge 等命令下发。',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
