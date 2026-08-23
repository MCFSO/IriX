// Jail 详情页（Bastille）
// 单个 jail 的深度管理界面，覆盖六项能力：
// - 运行：将节点上的实例目录挂载进 jail（bastille mount，默认 /data），
//   并在 jail 内运行实例（bastille cmd 后台会话，工作目录切到 /data），
//   附带实时会话控制台（输出 + stdin）与「进程退出即停止 Jail」看门狗开关；
//   启动命令 / 运行目录 / 挂载路径会记忆到本地（下次进入自动回填）。
// - 文件：jail 内文件管理（列表 / 上传 / 下载 / 文本编辑 / 新建 / 删除），
//   挂载点快捷入口（挂载进 /data 的文件在这里直接可见）。
// - 控制台：jail 系统控制台日志（bastille console 视角）+ 一键命令执行。
// - 软件包：bastille pkg 管理（安装 Java 环境等）+ 检测 Java + 挂载 /proc。
// - 挂载：nullfs / procfs 挂载列表与增删（fstab 持久化可选）。
// - 设置：jail.conf 配置项查看 / 编辑 / 删除（bastille config）。
//
// 全部能力经远程 irix-node 的 /api/bastille/* 端点暴露（NodeBastilleBackend）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide ImageInfo;

import '../models/remote.dart';
import '../services/container/container_backend.dart';
import '../services/database_manager.dart';
import '../services/font_settings.dart';
import '../services/node_api_client.dart';
import '../utils/ansi_color.dart';
import '../utils/apple_widgets.dart';

/// Jail 详情页。
class JailDetailScreen extends StatefulWidget {
  const JailDetailScreen({
    super.key,
    required this.backend,
    required this.jailName,
    this.nodeClient,
    this.daemonId,
    this.initialContainer,
  });

  /// 容器后端（Bastille）。
  final ContainerBackend backend;

  /// Jail 名。
  final String jailName;

  /// 节点 API 客户端（用于加载节点实例列表，填充挂载路径与启动命令）。
  final NodeApiClient? nodeClient;

  /// 守护进程 id（配合 [nodeClient] 使用）。
  final String? daemonId;

  /// 进入页面时的 jail 信息（列表缓存）。
  final ContainerInfo? initialContainer;

  @override
  State<JailDetailScreen> createState() => _JailDetailScreenState();
}

class _JailDetailScreenState extends State<JailDetailScreen> {
  static const Duration _sessionPollInterval = Duration(milliseconds: 1500);
  static const Duration _consolePollInterval = Duration(seconds: 2);

  // ==================== 共享状态 ====================

  ContainerInfo? _container;
  String? _error;
  bool _busy = false;

  // ==================== 运行 Tab ====================

  /// 节点实例列表（供选择填充路径/命令）。
  List<RemoteInstance> _instances = [];
  bool _instancesLoading = false;
  String? _selectedInstanceUuid;
  late final TextEditingController _hostPath;
  late final TextEditingController _jailPath;
  late final TextEditingController _startCommand;
  late final TextEditingController _workdir;
  bool _watch = false; // 看门狗：进程退出后自动停止 Jail

  /// 运行会话。
  String? _sessionId;
  bool _sessionRunning = false;
  String _sessionLog = '';
  int _logOffset = 0;
  Timer? _sessionTimer;
  final ScrollController _sessionScroll = ScrollController();
  late final TextEditingController _sessionInput;

  // ==================== 控制台 Tab ====================

  String _consoleLog = '';
  String _consoleCmdOut = '';
  Timer? _consoleTimer;
  final ScrollController _consoleScroll = ScrollController();
  late final TextEditingController _consoleCmd;

  // ==================== 文件 Tab ====================

  /// 当前浏览的 jail 内目录。
  String _filesPath = '/data';
  final TextEditingController _filesPathInput = TextEditingController(
    text: '/data',
  );
  List<JailFileEntry> _files = [];
  bool _filesLoading = false;
  bool _filesBusy = false;

  // ==================== 软件包 Tab ====================

  String _pkgAction = 'install';
  late final TextEditingController _pkgNames;
  bool _pkgBusy = false;
  String _pkgOutput = '';

  // ==================== 挂载 Tab ====================

  List<JailMount> _mounts = [];
  bool _mountsLoading = false;

  // ==================== 设置 Tab ====================

  Map<String, String> _config = {};
  final Map<String, TextEditingController> _configControllers = {};
  bool _configLoading = false;

  /// 常见 jail.conf 配置项提示（key → 说明）。
  static const Map<String, String> _configHints = {
    'ip4.addr': 'IPv4 地址（如 192.168.1.50/24）',
    'ip6.addr': 'IPv6 地址',
    'hostname': 'jail 主机名',
    'exec.start': '启动时执行的命令',
    'exec.stop': '停止时执行的命令',
    'exec.consolelog': '控制台日志路径',
    'autostart': '开机自启（yes/no）',
    'allow.mount': '允许 jail 内挂载',
    'allow.mount.procfs': '允许挂载 procfs',
    'vnet': 'VNET 网络模式',
    'interface': '网络接口',
    'securelevel': '安全级别',
  };

  /// 运行记忆（settings 表）前缀；按「节点地址 + jail 名」区分。
  static const String _runMemoryPrefix = 'bastille_run_memory_v1';

  String get _runMemoryKey =>
      '$_runMemoryPrefix:${widget.nodeClient?.baseUrl ?? 'local'}:$_name';

  String get _name => widget.jailName;

  @override
  void initState() {
    super.initState();
    _hostPath = TextEditingController();
    _jailPath = TextEditingController(text: '/data');
    _startCommand = TextEditingController();
    _workdir = TextEditingController(text: '/data');
    _sessionInput = TextEditingController();
    _consoleCmd = TextEditingController();
    _pkgNames = TextEditingController();
    _container = widget.initialContainer;
    unawaited(_refreshContainer());
    if (widget.nodeClient != null) unawaited(_loadInstances());
    unawaited(_refreshMounts());
    unawaited(_refreshConfig());
    unawaited(_refreshConsoleLog());
    unawaited(_loadRunMemory());
    unawaited(_refreshFiles());
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _consoleTimer?.cancel();
    _sessionScroll.dispose();
    _consoleScroll.dispose();
    _hostPath.dispose();
    _jailPath.dispose();
    _startCommand.dispose();
    _workdir.dispose();
    _sessionInput.dispose();
    _consoleCmd.dispose();
    _pkgNames.dispose();
    _filesPathInput.dispose();
    for (final c in _configControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _refreshContainer() async {
    try {
      final list = await widget.backend.listContainers();
      if (!mounted) return;
      setState(() {
        _container = list.where((c) => c.name == _name).firstOrNull;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadInstances() async {
    final client = widget.nodeClient;
    final daemonId = widget.daemonId;
    if (client == null || daemonId == null || daemonId.isEmpty) return;
    setState(() => _instancesLoading = true);
    try {
      final list = await client.listInstances(daemonId: daemonId);
      if (!mounted) return;
      setState(() => _instances = list);
    } catch (_) {
      // 节点不支持时静默降级为手动填写路径。
    } finally {
      if (mounted) setState(() => _instancesLoading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 统一错误提示：容器后端异常直接展示消息；其余（如旧节点 404）展示原始错误。
  void _snackError(Object error, {String prefix = '操作失败'}) {
    _snack(
      error is ContainerBackendException ? error.message : '$prefix：$error',
    );
  }

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  // ==================== 运行记忆（settings 表）====================

  /// 读取上次的启动命令 / 运行目录 / 挂载路径，回填表单。
  Future<void> _loadRunMemory() async {
    final raw = await DatabaseManager.instance.getSetting(_runMemoryKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _startCommand.text = map['command'] as String? ?? _startCommand.text;
        _workdir.text = map['workdir'] as String? ?? _workdir.text;
        _hostPath.text = map['hostPath'] as String? ?? _hostPath.text;
        _jailPath.text = map['jailPath'] as String? ?? _jailPath.text;
        _watch = map['watch'] as bool? ?? _watch;
      });
    } catch (_) {
      // 记忆损坏时忽略，按默认空表单。
    }
  }

  /// 保存启动命令 / 运行目录 / 挂载路径（下次进入自动回填）。
  Future<void> _saveRunMemory() async {
    await DatabaseManager.instance.setSetting(
      _runMemoryKey,
      jsonEncode({
        'command': _startCommand.text.trim(),
        'workdir': _workdir.text.trim(),
        'hostPath': _hostPath.text.trim(),
        'jailPath': _jailPath.text.trim(),
        'watch': _watch,
      }),
    );
  }

  // ==================== 运行 Tab ====================

  bool get _jailRunning => _container?.isRunning ?? false;

  /// 选择节点实例后填充路径与启动命令。
  void _applyInstance(RemoteInstance instance) {
    final cfg = instance.config;
    setState(() {
      _hostPath.text = cfg.cwd;
      if (cfg.startCommand.isNotEmpty) {
        _startCommand.text = cfg.startCommand;
      }
      _jailPath.text = '/data';
      _workdir.text = '/data';
    });
  }

  Future<void> _mountInstance() async {
    final hostPath = _hostPath.text.trim();
    final jailPath = _jailPath.text.trim().isEmpty
        ? '/data'
        : _jailPath.text.trim();
    if (hostPath.isEmpty) {
      _snack('请填写实例目录（节点上的宿主机路径）');
      return;
    }
    _setBusy(true);
    try {
      await widget.backend.addJailMount(
        _name,
        src: hostPath,
        dst: jailPath,
        fstype: 'nullfs',
        options: 'rw',
        permanent: true, // 写入 fstab：jail 重启后挂载不丢失
      );
      _snack('已挂载 $hostPath → $jailPath（fstab 持久化，重启不丢失）');
      await _refreshMounts();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _unmountInstance() async {
    final jailPath = _jailPath.text.trim().isEmpty
        ? '/data'
        : _jailPath.text.trim();
    _setBusy(true);
    try {
      await widget.backend.removeJailMount(_name, jailPath);
      _snack('已卸载 $jailPath');
      await _refreshMounts();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  bool _isMounted(String jailPath) => _mounts.any((m) => m.dst == jailPath);

  /// 启动运行会话（看门狗开关经 watch 下发；进程退出后停止 Jail）。
  Future<void> _startRun() async {
    if (!_jailRunning) {
      _snack('Jail 未运行，请先在顶部启动 Jail');
      return;
    }
    final command = _startCommand.text.trim();
    if (command.isEmpty) {
      _snack('请填写启动命令（如 java -Xmx2G -jar server.jar nogui）');
      return;
    }
    final hostPath = _hostPath.text.trim();
    final jailPath = _jailPath.text.trim().isEmpty
        ? '/data'
        : _jailPath.text.trim();
    final workdir = _workdir.text.trim().isEmpty
        ? '/data'
        : _workdir.text.trim();

    // 未挂载时自动挂载实例目录（默认 /data）。
    if (hostPath.isNotEmpty && !_isMounted(jailPath)) {
      try {
        await widget.backend.addJailMount(
          _name,
          src: hostPath,
          dst: jailPath,
          fstype: 'nullfs',
          options: 'rw',
          permanent: true,
        );
        await _refreshMounts();
      } catch (e) {
        _snackError(e, prefix: '实例目录挂载失败');
        return;
      }
    }

    _setBusy(true);
    try {
      final session = await widget.backend.startJailRun(
        _name,
        command: command,
        cwd: workdir,
        watch: _watch,
      );
      if (!mounted) return;
      if (session.isEmpty) {
        _snack('节点未返回会话 id：可能节点版本过旧，缺少运行会话接口');
        return;
      }
      setState(() {
        _sessionId = session;
        _sessionRunning = true;
        _sessionLog = '';
        _logOffset = 0;
      });
      _startSessionPolling();
      unawaited(_saveRunMemory());
      _snack('已在 Jail 内启动${_watch ? '（看门狗开启：进程退出后自动停止 Jail）' : ''}');
    } catch (e) {
      _snackError(e, prefix: '启动失败');
    } finally {
      _setBusy(false);
    }
  }

  void _startSessionPolling() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(_sessionPollInterval, (_) {
      unawaited(_pollSession());
    });
  }

  Future<void> _pollSession() async {
    final session = _sessionId;
    if (session == null) return;
    try {
      final status = await widget.backend.jailRunStatus(
        _name,
        session,
        since: _logOffset,
      );
      if (!mounted) return;
      setState(() {
        _sessionLog += status.log;
        _logOffset = status.offset;
        _sessionRunning = status.running;
      });
      _scrollSessionToBottom();
      if (!status.running) {
        _sessionTimer?.cancel();
        if (_watch) unawaited(_stopJailAfterExit(status.exitCode));
        _snack(
          '容器内进程已退出（exit ${status.exitCode ?? '?'}）'
          '${_watch ? '，Jail 已停止' : ''}',
        );
      }
    } catch (_) {
      // 会话可能已过期或节点重启，停止轮询。
      _sessionTimer?.cancel();
    }
  }

  /// 看门狗：进程退出后停止 Jail（客户端兜底；节点 watch 同样会停）。
  Future<void> _stopJailAfterExit(int? exitCode) async {
    try {
      await widget.backend.stopContainer(_name);
    } catch (_) {
      // 节点 watch 已停或 jail 已停止，忽略。
    }
    await _refreshContainer();
  }

  Future<void> _sendSessionCommand() async {
    final session = _sessionId;
    if (session == null || !_sessionRunning) {
      _snack('没有运行中的会话');
      return;
    }
    final input = _sessionInput.text;
    if (input.trim().isEmpty) return;
    _sessionInput.clear();
    try {
      await widget.backend.jailRunStdin(_name, session, '$input\n');
    } catch (e) {
      _snackError(e, prefix: '发送失败');
    }
  }

  Future<void> _stopSession() async {
    final session = _sessionId;
    if (session == null) return;
    _setBusy(true);
    try {
      await widget.backend.stopJailRun(_name, session);
    } catch (e) {
      _snackError(e, prefix: '停止失败');
    } finally {
      _setBusy(false);
    }
  }

  void _scrollSessionToBottom() {
    if (_sessionScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sessionScroll.hasClients) {
          _sessionScroll.jumpTo(_sessionScroll.position.maxScrollExtent);
        }
      });
    }
  }

  // ==================== 控制台 Tab ====================

  Future<void> _refreshConsoleLog() async {
    _consoleTimer?.cancel();
    if (!_jailRunning) {
      if (mounted) setState(() => _consoleLog = '（Jail 未运行，无控制台日志）');
      return;
    }
    try {
      final log = await widget.backend.containerLogs(_name, tail: 300);
      if (!mounted) return;
      setState(() => _consoleLog = log);
    } catch (_) {
      // 静默：轮询失败下一轮重试。
    }
    // 仅 jail 运行期间持续轮询（等效 bastille console 持续查看）。
    _consoleTimer = Timer(_consolePollInterval, () {
      unawaited(_refreshConsoleLog());
    });
  }

  Future<void> _runConsoleCommand() async {
    final cmd = _consoleCmd.text.trim();
    if (cmd.isEmpty) return;
    _consoleCmd.clear();
    try {
      final out = await widget.backend.execOutput(_name, cmd);
      if (!mounted) return;
      setState(() {
        _consoleCmdOut += '\n\$ $cmd\n${out.trim().isEmpty ? '（无输出）' : out}';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_consoleScroll.hasClients) {
          _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      _snackError(e, prefix: '执行失败');
    }
  }

  // ==================== 软件包 Tab ====================

  static const List<(String, String)> _pkgActions = [
    ('install', '安装（install）'),
    ('delete', '删除（delete）'),
    ('update', '更新索引（update）'),
    ('upgrade', '升级全部（upgrade）'),
    ('autoremove', '清理无用依赖（autoremove）'),
  ];

  /// 常用 Java 包快捷安装。
  static const List<String> _javaPackages = [
    'openjdk8-jre',
    'openjdk11-jre',
    'openjdk17-jre',
    'openjdk21-jre',
    'openjdk23-jre',
    'ca_root_nss',
  ];

  Future<void> _runPkg() async {
    final names = _pkgNames.text
        .split(RegExp(r'[\s,，]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if ((_pkgAction == 'install' || _pkgAction == 'delete') && names.isEmpty) {
      _snack('请填写包名（如 openjdk17-jre）');
      return;
    }
    setState(() {
      _pkgBusy = true;
      _pkgOutput = '';
    });
    try {
      final out = await widget.backend.runPkg(_name, _pkgAction, names);
      if (!mounted) return;
      setState(() => _pkgOutput = out);
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _pkgOutput = e is ContainerBackendException ? e.message : '执行失败：$e',
      );
    } finally {
      if (mounted) setState(() => _pkgBusy = false);
    }
  }

  Future<void> _detectJava() async {
    setState(() => _pkgBusy = true);
    try {
      final out = await widget.backend.execOutput(
        _name,
        'java -version 2>&1; echo ---; command -v java 2>&1 || echo 未找到 java',
      );
      if (!mounted) return;
      setState(() => _pkgOutput = out);
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _pkgOutput = e is ContainerBackendException ? e.message : '检测失败：$e',
      );
    } finally {
      if (mounted) setState(() => _pkgBusy = false);
    }
  }

  /// 挂载 /proc（部分 Java 版本 / JVM 特性需要）。
  Future<void> _mountProc() async {
    _setBusy(true);
    try {
      if (_isMounted('/proc')) {
        _snack('/proc 已挂载');
        return;
      }
      await widget.backend.addJailMount(
        _name,
        dst: '/proc',
        fstype: 'procfs',
        options: 'rw',
      );
      _snack('已挂载 procfs → /proc');
      await _refreshMounts();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  // ==================== 挂载 Tab ====================

  Future<void> _refreshMounts() async {
    setState(() => _mountsLoading = true);
    try {
      final list = await widget.backend.listJailMounts(_name);
      if (!mounted) return;
      setState(() => _mounts = list);
    } catch (e) {
      _snackError(e);
    }
    if (!mounted) return;
    setState(() => _mountsLoading = false);
  }

  Future<void> _openAddMountDialog() async {
    final result =
        await showAppDialog<
          ({
            String? src,
            String dst,
            String fstype,
            String options,
            bool permanent,
          })
        >(context, (_) => const _AddMountDialog());
    if (result == null || !mounted) return;
    _setBusy(true);
    try {
      await widget.backend.addJailMount(
        _name,
        src: result.src,
        dst: result.dst,
        fstype: result.fstype,
        options: result.options,
        permanent: result.permanent,
      );
      _snack(
        result.permanent ? '挂载已添加（fstab 持久化，重启自动挂载）' : '挂载已添加（仅当前挂载，重启后需重新挂载）',
      );
      await _refreshMounts();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _removeMount(JailMount mount) async {
    final ok = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: const Text('卸载挂载'),
        content: Text('确定卸载 ${mount.display} 吗？\n（fstab 条目也会一并移除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _setBusy(true);
    try {
      await widget.backend.removeJailMount(_name, mount.dst);
      _snack('已卸载 ${mount.dst}');
      await _refreshMounts();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  /// 挂载点「打开目录」：切到文件 Tab 并浏览挂载的 jail 内路径。
  void _openMountInFiles(JailMount mount) {
    DefaultTabController.of(context).animateTo(1);
    _gotoFilesPath(mount.dst);
  }

  // ==================== 文件 Tab ====================

  /// 刷新当前目录列表。
  Future<void> _refreshFiles() async {
    setState(() => _filesLoading = true);
    try {
      final list = await widget.backend.listJailFiles(_name, path: _filesPath);
      if (!mounted) return;
      setState(() => _files = list.items);
    } catch (e) {
      _snackError(e, prefix: '加载文件列表失败');
    }
    if (!mounted) return;
    setState(() => _filesLoading = false);
  }

  /// 跳转目录（规范化路径后刷新）。
  void _gotoFilesPath(String path) {
    final normalized = _normalizeJailPath(path);
    if (normalized != _filesPath) {
      setState(() {
        _filesPath = normalized;
        _filesPathInput.text = normalized;
      });
    }
    unawaited(_refreshFiles());
  }

  /// 规范化 jail 内路径：补前导 `/`、去掉末尾 `/`、空 → `/`。
  static String _normalizeJailPath(String path) {
    var p = path.trim();
    if (p.isEmpty) return '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  String get _parentJailPath {
    final parts = _filesPath.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '/';
    parts.removeLast();
    return parts.isEmpty ? '/' : '/${parts.join('/')}';
  }

  void _enterJailDir(JailFileEntry entry) {
    if (!entry.isDir) return;
    _gotoFilesPath(entry.path);
  }

  Future<void> _jailMkdir() async {
    final name = await _promptJailFileName('新建目录', '目录名称');
    if (name == null || !mounted) return;
    setState(() => _filesBusy = true);
    try {
      await widget.backend.jailMkdir(_name, _joinJailPath(name));
      await _refreshFiles();
    } catch (e) {
      _snackError(e);
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  Future<void> _jailTouch() async {
    final name = await _promptJailFileName('新建文件', '文件名称');
    if (name == null || !mounted) return;
    setState(() => _filesBusy = true);
    try {
      await widget.backend.jailTouch(_name, _joinJailPath(name));
      await _refreshFiles();
    } catch (e) {
      _snackError(e);
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  String _joinJailPath(String name) {
    final base = _filesPath == '/' ? '' : _filesPath;
    return '$base/${name.trim().replaceAll(RegExp(r'[\\/]'), '')}';
  }

  /// 名称输入对话框（返回 null 表示取消）。
  Future<String?> _promptJailFileName(String title, String label) {
    final controller = TextEditingController();
    return showAppDialog<String>(
      context,
      (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: '位于 $_filesPath',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadJailFiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要上传到 $_filesPath 的文件',
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    setState(() => _filesBusy = true);
    try {
      for (final file in result.files) {
        final path = file.path;
        if (path == null) continue;
        await widget.backend.uploadJailFile(_name, _filesPath, path);
      }
      _snack('已上传 ${result.files.length} 个文件到 $_filesPath');
      await _refreshFiles();
    } catch (e) {
      _snackError(e, prefix: '上传失败');
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  Future<void> _downloadJailFile(JailFileEntry entry) async {
    setState(() => _filesBusy = true);
    try {
      final bytes = await widget.backend.downloadJailFile(_name, entry.path);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: entry.name,
      );
      if (savePath != null) {
        await File(savePath).writeAsBytes(bytes, flush: true);
        if (mounted) _snack('已下载到 $savePath');
      }
    } catch (e) {
      _snackError(e, prefix: '下载失败');
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  Future<void> _editJailFile(JailFileEntry entry) async {
    if (entry.size > 2 * 1024 * 1024) {
      _snack('文件过大（>2MB），请下载后编辑');
      return;
    }
    setState(() => _filesBusy = true);
    String content;
    try {
      content = await widget.backend.readJailFile(_name, entry.path);
    } catch (e) {
      _snackError(e, prefix: '读取文件失败');
      if (mounted) setState(() => _filesBusy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _filesBusy = false);
    final controller = TextEditingController(text: content);
    final saved = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('编辑 ${entry.name}'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: TextStyle(
              fontFamily: FontSettings.instance.terminalFamily,
              fontSize: 12.5,
            ),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    setState(() => _filesBusy = true);
    try {
      await widget.backend.writeJailFile(_name, entry.path, controller.text);
      _snack('已保存 ${entry.name}');
      await _refreshFiles();
    } catch (e) {
      _snackError(e, prefix: '保存失败');
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  Future<void> _deleteJailFile(JailFileEntry entry) async {
    final ok = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除 ${entry.isDir ? '目录' : '文件'}？'),
        content: Text(
          '确定删除 ${entry.path} 吗？\n${entry.isDir ? '目录将递归删除，不可恢复。' : '删除后不可恢复。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _filesBusy = true);
    try {
      await widget.backend.deleteJailFile(_name, entry.path);
      _snack('已删除 ${entry.path}');
      await _refreshFiles();
    } catch (e) {
      _snackError(e, prefix: '删除失败');
    } finally {
      if (mounted) setState(() => _filesBusy = false);
    }
  }

  /// 文件条目操作菜单。
  Future<void> _showJailFileActions(JailFileEntry entry) async {
    if (entry.isDir) {
      _enterJailDir(entry);
      return;
    }
    final action = await showAppDialog<String>(
      context,
      (_) => SimpleDialog(
        title: Text(entry.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Row(
              children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 10),
                Text('编辑（文本）'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'download'),
            child: const Row(
              children: [
                Icon(Icons.download_outlined, size: 18),
                SizedBox(width: 10),
                Text('下载到本地'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Row(
              children: [
                Icon(Icons.delete_outline, size: 18),
                SizedBox(width: 10),
                Text('删除'),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editJailFile(entry);
      case 'download':
        await _downloadJailFile(entry);
      case 'delete':
        await _deleteJailFile(entry);
    }
  }

  // ==================== 设置 Tab ====================

  Future<void> _refreshConfig() async {
    setState(() => _configLoading = true);
    try {
      final config = await widget.backend.getJailConfig(_name);
      if (!mounted) return;
      setState(() {
        _config = config;
        for (final c in _configControllers.values) {
          c.dispose();
        }
        _configControllers.clear();
        for (final entry in config.entries) {
          _configControllers[entry.key] = TextEditingController(
            text: entry.value,
          );
        }
      });
    } catch (e) {
      _snackError(e);
    }
    if (!mounted) return;
    setState(() => _configLoading = false);
  }

  Future<void> _saveConfig(String key) async {
    final controller = _configControllers[key];
    if (controller == null) return;
    final value = controller.text;
    _setBusy(true);
    try {
      await widget.backend.setJailConfig(_name, key, value);
      _snack('已保存 $key');
      await _refreshConfig();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _removeConfig(String key) async {
    final ok = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除配置项 $key？'),
        content: const Text('从 jail.conf 中移除该参数（下次启动生效）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _setBusy(true);
    try {
      await widget.backend.removeJailConfig(_name, key);
      _snack('已删除 $key');
      await _refreshConfig();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _openAddConfigDialog() async {
    final result = await showAppDialog<({String key, String value})>(
      context,
      (_) => const _AddConfigDialog(hints: _configHints),
    );
    if (result == null || !mounted) return;
    _setBusy(true);
    try {
      await widget.backend.setJailConfig(_name, result.key, result.value);
      _snack('已添加 ${result.key}');
      await _refreshConfig();
    } catch (e) {
      _snackError(e);
    } finally {
      _setBusy(false);
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () {
                unawaited(_refreshContainer());
                unawaited(_refreshMounts());
                unawaited(_refreshConfig());
                unawaited(_refreshConsoleLog());
                unawaited(_refreshFiles());
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            _buildHeader(theme),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.play_circle_outline), text: '运行'),
                Tab(icon: Icon(Icons.folder_outlined), text: '文件'),
                Tab(icon: Icon(Icons.terminal), text: '控制台'),
                Tab(icon: Icon(Icons.inventory_outlined), text: '软件包'),
                Tab(icon: Icon(Icons.link), text: '挂载'),
                Tab(icon: Icon(Icons.tune), text: '设置'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildRunTab(theme),
                  _buildFilesTab(theme),
                  _buildConsoleTab(theme),
                  _buildPkgTab(theme),
                  _buildMountsTab(theme),
                  _buildConfigTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部：状态 + 启停控制。
  Widget _buildHeader(ThemeData theme) {
    final running = _jailRunning;
    final container = _container;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2,
                size: 18,
                color: running ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                running ? '运行中' : '已停止',
                style: TextStyle(
                  fontSize: 13,
                  color: running ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              if (container != null && container.image.isNotEmpty)
                Expanded(
                  child: Text(
                    '发行版 ${container.image}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (container != null && container.ports.isNotEmpty)
                Expanded(
                  child: Text(
                    '转发 ${container.ports.join('，')}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: running || _busy
                    ? null
                    : () async {
                        _setBusy(true);
                        try {
                          await widget.backend.startContainer(_name);
                          await _refreshContainer();
                          unawaited(_refreshConsoleLog());
                        } catch (e) {
                          _snackError(e);
                        } finally {
                          _setBusy(false);
                        }
                      },
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('启动'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: !running || _busy
                    ? null
                    : () async {
                        _setBusy(true);
                        try {
                          await widget.backend.stopContainer(_name);
                          await _refreshContainer();
                        } catch (e) {
                          _snackError(e);
                        } finally {
                          _setBusy(false);
                        }
                      },
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('停止'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: !running || _busy
                    ? null
                    : () async {
                        _setBusy(true);
                        try {
                          await widget.backend.restartContainer(_name);
                          await _refreshContainer();
                          unawaited(_refreshConsoleLog());
                        } catch (e) {
                          _snackError(e);
                        } finally {
                          _setBusy(false);
                        }
                      },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重启'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 运行 Tab ====================

  Widget _buildRunTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: '实例挂载（bastille mount）',
          children: [
            if (widget.nodeClient != null) ...[
              DropdownButtonFormField<String?>(
                initialValue: _selectedInstanceUuid,
                decoration: InputDecoration(
                  labelText: '选择节点实例（自动填充路径与命令）',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: _instancesLoading ? '正在加载实例列表…' : null,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('手动填写（不选择实例）'),
                  ),
                  for (final instance in _instances)
                    DropdownMenuItem<String?>(
                      value: instance.uuid,
                      child: Text(
                        '${instance.config.nickname}（${instance.config.cwd}）',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (uuid) {
                  setState(() => _selectedInstanceUuid = uuid);
                  if (uuid != null) {
                    final instance = _instances
                        .where((i) => i.uuid == uuid)
                        .firstOrNull;
                    if (instance != null) _applyInstance(instance);
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _hostPath,
              decoration: const InputDecoration(
                labelText: '实例目录（节点上的宿主机路径）',
                hintText: '如 /usr/local/irix-node/instances/mc-survival',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jailPath,
                    decoration: const InputDecoration(
                      labelText: 'Jail 内路径（默认 /data）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: Icon(
                    _isMounted(
                          _jailPath.text.trim().isEmpty
                              ? '/data'
                              : _jailPath.text.trim(),
                        )
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _isMounted(
                          _jailPath.text.trim().isEmpty
                              ? '/data'
                              : _jailPath.text.trim(),
                        )
                        ? '已挂载'
                        : '未挂载',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _mountInstance,
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('挂载'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _unmountInstance,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('卸载'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: '在 Jail 内运行实例（bastille cmd）',
          children: [
            TextField(
              controller: _startCommand,
              decoration: const InputDecoration(
                labelText: '启动命令',
                hintText: '如 java -Xmx2G -jar server.jar nogui',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workdir,
              decoration: const InputDecoration(
                labelText: '运行目录（容器内工作目录，默认 /data）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            SwitchListTile(
              title: const Text('看门狗：进程退出后自动停止 Jail'),
              subtitle: const Text(
                '容器内进程（如 MC 服务端）停止运行后，自动执行 bastille stop',
                style: TextStyle(fontSize: 12),
              ),
              value: _watch,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _watch = v),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy || !_jailRunning || _sessionRunning
                      ? null
                      : _startRun,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('启动运行'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy || !_sessionRunning ? null : _stopSession,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止进程'),
                ),
                const SizedBox(width: 8),
                if (_sessionId != null)
                  Chip(
                    avatar: _sessionRunning
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.grey,
                          ),
                    label: Text(
                      _sessionRunning ? '会话运行中' : '会话已结束',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            if (_sessionId == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '提示：未挂载实例目录时，启动运行会自动挂载（默认 /data）。'
                  '查看输出 / 发送命令请在下方控制台进行。',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _ConsolePanel(
          title: '运行会话控制台',
          log: _sessionLog.isEmpty ? '（尚未启动运行，输出将显示在这里）' : _sessionLog,
          inputController: _sessionInput,
          inputEnabled: _sessionRunning,
          inputHint: '输入命令（如 say hello），回车发送',
          scrollController: _sessionScroll,
          onSend: _sendSessionCommand,
          onClear: () => setState(() => _sessionLog = ''),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ==================== 文件 Tab ====================

  Widget _buildFilesTab(ThemeData theme) {
    final mountDirs = _mounts
        .where((m) => m.dst.isNotEmpty && m.dst != '/proc')
        .map((m) => m.dst)
        .toSet()
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 路径栏：面包屑 + 刷新 + 上级。
              // 注意：Wrap 不支持 flex 子项（Spacer/Expanded 在 Wrap 内会
              // 在挂载时抛 ParentDataWidget 异常，导致整个 Tab 白屏），
              // 因此右侧按钮必须放在 Wrap 之外的 Row 中。
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.home, size: 14),
                          label: const Text('/', style: TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _gotoFilesPath('/'),
                        ),
                        for (final part
                            in _filesPath
                                .split('/')
                                .where((e) => e.isNotEmpty)
                                .toList()) ...[
                          const Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: Colors.grey,
                          ),
                          ActionChip(
                            label: Text(
                              part,
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final parts = _filesPath
                                  .split('/')
                                  .where((e) => e.isNotEmpty)
                                  .toList();
                              final idx = parts.indexOf(part);
                              if (idx >= 0) {
                                _gotoFilesPath(
                                  '/${parts.sublist(0, idx + 1).join('/')}',
                                );
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '刷新',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refreshFiles,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    tooltip: '返回上级',
                    visualDensity: VisualDensity.compact,
                    onPressed: _filesPath == '/'
                        ? null
                        : () => _gotoFilesPath(_parentJailPath),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 路径输入 + 跳转
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _filesPathInput,
                      decoration: const InputDecoration(
                        labelText: 'Jail 内路径',
                        hintText: '如 /data 或 /usr/local/bin',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (v) => _gotoFilesPath(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _gotoFilesPath(_filesPathInput.text),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('跳转'),
                  ),
                ],
              ),
              // 挂载点快捷入口
              if (mountDirs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '挂载点：',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    for (final dir in mountDirs)
                      ActionChip(
                        avatar: const Icon(Icons.link, size: 14),
                        label: Text(dir, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _gotoFilesPath(dir),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // 操作行
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _filesBusy ? null : _uploadJailFiles,
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('上传'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _filesBusy ? null : _jailMkdir,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 16,
                    ),
                    label: const Text('新建目录'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _filesBusy ? null : _jailTouch,
                    icon: const Icon(Icons.note_add_outlined, size: 16),
                    label: const Text('新建文件'),
                  ),
                  if (_filesBusy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: _filesLoading
              ? const Center(child: CircularProgressIndicator())
              : _files.isEmpty
              ? Center(
                  child: Text(
                    '$_filesPath 为空\n挂载实例目录后，文件会出现在这里',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final entry = _files[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        entry.isDir
                            ? Icons.folder
                            : Icons.insert_drive_file_outlined,
                        size: 20,
                        color: entry.isDir
                            ? Colors.amber
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        entry.name,
                        style: const TextStyle(fontSize: 13.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: entry.isDir
                          ? null
                          : Text(
                              '${entry.sizeDisplay}'
                              '${entry.mtime != null ? ' · ${_formatMtime(entry.mtime!)}' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                      onTap: () => _showJailFileActions(entry),
                      trailing: entry.isDir
                          ? IconButton(
                              icon: const Icon(Icons.chevron_right, size: 18),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _enterJailDir(entry),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.download, size: 18),
                                  tooltip: '下载',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _filesBusy
                                      ? null
                                      : () => _downloadJailFile(entry),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  tooltip: '删除',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _filesBusy
                                      ? null
                                      : () => _deleteJailFile(entry),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _formatMtime(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  // ==================== 控制台 Tab ====================

  Widget _buildConsoleTab(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Jail 系统控制台日志（bastille console 视角）· '
                  '下方命令在 jail 内执行（sh 语义）',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                controller: _consoleScroll,
                child: SelectableText.rich(
                  TextSpan(
                    children: (_consoleLog.isEmpty && _consoleCmdOut.isEmpty)
                        ? const [TextSpan(text: '（暂无日志输出）')]
                        : ansiSpans(
                            '$_consoleLog$_consoleCmdOut',
                            TextStyle(
                              fontFamily: FontSettings.instance.terminalFamily,
                              fontSize: 12,
                              color: Colors.greenAccent,
                            ),
                          ),
                  ),
                  style: TextStyle(
                    fontFamily: FontSettings.instance.terminalFamily,
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _consoleCmd,
                  decoration: InputDecoration(
                    hintText: 'jail 内执行命令（如 ls /data、java -version）',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _runConsoleCommand(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                tooltip: '执行命令',
                onPressed: _runConsoleCommand,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新日志',
                onPressed: () {
                  setState(() => _consoleCmdOut = '');
                  unawaited(_refreshConsoleLog());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 软件包 Tab ====================

  Widget _buildPkgTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: '软件包管理（bastille pkg）',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _pkgAction,
              decoration: const InputDecoration(
                labelText: '操作',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final (value, label) in _pkgActions)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _pkgAction = v ?? 'install'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pkgNames,
              decoration: const InputDecoration(
                labelText: '包名（逗号 / 空格分隔）',
                hintText: '如 openjdk17-jre openjdk21-jre',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pkg in _javaPackages)
                  ActionChip(
                    label: Text(pkg, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      final current = _pkgNames.text.trim();
                      _pkgNames.text = current.isEmpty ? pkg : '$current $pkg';
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _pkgBusy ? null : _runPkg,
                  icon: _pkgBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download, size: 16),
                  label: Text(_pkgBusy ? '执行中…' : '执行'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pkgBusy ? null : _detectJava,
                  icon: const Icon(Icons.memory, size: 16),
                  label: const Text('检测 Java'),
                ),
              ],
            ),
            if (_pkgOutput.isNotEmpty) ...[
              const SizedBox(height: 12),
              _OutputBox(text: _pkgOutput),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Java 环境',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory),
              title: const Text('挂载 /proc（procfs）'),
              subtitle: const Text(
                '部分 Java 版本 / JVM 特性（GC 日志等）需要 jail 内有 /proc；'
                '仅需执行一次，写入 fstab 后重启自动生效。',
                style: TextStyle(fontSize: 12),
              ),
              trailing: FilledButton.tonalIcon(
                onPressed: _busy ? null : _mountProc,
                icon: const Icon(Icons.link, size: 16),
                label: Text(_isMounted('/proc') ? '已挂载' : '挂载'),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.developer_mode),
              title: const Text('安装 Java 运行环境'),
              subtitle: const Text(
                '在「操作」选择安装，包名填写 openjdk17-jre 等（见上方快捷包），'
                '然后点击「执行」。安装完成后可用「检测 Java」验证。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ==================== 挂载 Tab ====================

  Widget _buildMountsTab(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Text(
                '挂载列表（bastille mount / fstab）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshMounts,
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _mountProc,
                icon: const Icon(Icons.memory, size: 16),
                label: const Text('挂载 /proc'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _openAddMountDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加挂载'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _mountsLoading
              ? const Center(child: CircularProgressIndicator())
              : _mounts.isEmpty
              ? const Center(child: Text('暂无挂载，点击「添加挂载」'))
              : ListView.builder(
                  itemCount: _mounts.length,
                  itemBuilder: (context, index) {
                    final mount = _mounts[index];
                    final isProc = mount.fstype == 'procfs';
                    return ListTile(
                      leading: Icon(
                        isProc ? Icons.memory : Icons.folder,
                        color: isProc
                            ? Colors.orangeAccent
                            : theme.colorScheme.primary,
                      ),
                      title: Text(mount.display),
                      subtitle: Text(
                        [
                          if (mount.options != null &&
                              mount.options!.isNotEmpty)
                            '选项 ${mount.options}',
                          if (mount.permanent)
                            'fstab 持久化（重启自动挂载）'
                          else if (!isProc)
                            '仅当前挂载（重启后需重新挂载）',
                        ].join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isProc && mount.dst.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.folder_open, size: 18),
                              tooltip: '打开目录（文件 Tab）',
                              onPressed: () => _openMountInFiles(mount),
                            ),
                          IconButton(
                            icon: const Icon(Icons.link_off),
                            tooltip: '卸载',
                            onPressed: () => _removeMount(mount),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==================== 设置 Tab ====================

  Widget _buildConfigTab(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Text(
                'Jail 配置（bastille config）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshConfig,
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _openAddConfigDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加配置项'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _configLoading
              ? const Center(child: CircularProgressIndicator())
              : _config.isEmpty
              ? const Center(child: Text('暂无配置项，点击「添加配置项」'))
              : ListView.builder(
                  itemCount: _config.length,
                  itemBuilder: (context, index) {
                    final key = _config.keys.elementAt(index);
                    final controller = _configControllers[key];
                    return ListTile(
                      title: Text(
                        key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_configHints[key] != null)
                            Text(
                              _configHints[key]!,
                              style: const TextStyle(fontSize: 11),
                            ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.save_outlined),
                            tooltip: '保存',
                            onPressed: _busy ? null : () => _saveConfig(key),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除配置项',
                            onPressed: _busy ? null : () => _removeConfig(key),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ==================== 通用小组件 ====================

/// 分节卡片。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 等宽输出框（软件包输出等）。
class _OutputBox extends StatelessWidget {
  const _OutputBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily: FontSettings.instance.terminalFamily,
            fontSize: 12,
            color: Colors.greenAccent,
          ),
        ),
      ),
    );
  }
}

/// 终端控制台面板（运行会话 / 通用输出）。
class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({
    required this.title,
    required this.log,
    required this.inputController,
    required this.inputEnabled,
    required this.inputHint,
    required this.scrollController,
    required this.onSend,
    required this.onClear,
  });

  final String title;
  final String log;
  final TextEditingController inputController;
  final bool inputEnabled;
  final String inputHint;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: '清空输出',
                  onPressed: onClear,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 260,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: SelectableText.rich(
                  TextSpan(
                    children: ansiSpans(
                      log,
                      TextStyle(
                        fontFamily: FontSettings.instance.terminalFamily,
                        fontSize: 12,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: FontSettings.instance.terminalFamily,
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    enabled: inputEnabled,
                    decoration: InputDecoration(
                      hintText: inputEnabled ? inputHint : '（无运行中的会话）',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: '发送',
                  onPressed: inputEnabled ? onSend : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 对话框 ====================

/// 添加挂载对话框。
class _AddMountDialog extends StatefulWidget {
  const _AddMountDialog();

  @override
  State<_AddMountDialog> createState() => _AddMountDialogState();
}

class _AddMountDialogState extends State<_AddMountDialog> {
  String _fstype = 'nullfs';
  bool _permanent = true; // fstab 持久化：jail 重启后挂载不丢失
  final _src = TextEditingController();
  final _dst = TextEditingController(text: '/data');
  final _options = TextEditingController(text: 'rw');

  @override
  void dispose() {
    _src.dispose();
    _dst.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加挂载'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _fstype,
                decoration: const InputDecoration(
                  labelText: '文件系统类型',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'nullfs',
                    child: Text('nullfs（宿主机目录）'),
                  ),
                  DropdownMenuItem(
                    value: 'procfs',
                    child: Text('procfs（/proc，Java 需要）'),
                  ),
                ],
                onChanged: (v) => setState(() => _fstype = v ?? 'nullfs'),
              ),
              const SizedBox(height: 12),
              if (_fstype == 'nullfs') ...[
                TextField(
                  controller: _src,
                  decoration: const InputDecoration(
                    labelText: '宿主机源路径',
                    hintText: '如 /usr/local/irix-node/instances/mc-survival',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _dst,
                decoration: const InputDecoration(
                  labelText: 'Jail 内目标路径',
                  hintText: '如 /data 或 /proc',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _options,
                decoration: const InputDecoration(
                  labelText: '挂载选项（默认 rw）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_fstype == 'nullfs') ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  title: const Text(
                    'fstab 持久化',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    '写入 fstab：jail 启动时自动挂载，重启不丢失（推荐）',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _permanent,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _permanent = v),
                ),
                const SizedBox(height: 4),
                Text(
                  '提示：nullfs 实时挂载需要 jail 运行中；jail 未运行时'
                  '只能写入 fstab（下次启动生效）。挂载后可在「文件」Tab 查看目录内容。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final dst = _dst.text.trim();
            if (dst.isEmpty) return;
            if (_fstype == 'nullfs' && _src.text.trim().isEmpty) return;
            Navigator.pop(context, (
              src: _fstype == 'nullfs' ? _src.text.trim() : null,
              dst: dst,
              fstype: _fstype,
              options: _options.text.trim().isEmpty
                  ? 'rw'
                  : _options.text.trim(),
              permanent: _fstype == 'nullfs' ? _permanent : false,
            ));
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

/// 添加配置项对话框。
class _AddConfigDialog extends StatefulWidget {
  const _AddConfigDialog({required this.hints});

  final Map<String, String> hints;

  @override
  State<_AddConfigDialog> createState() => _AddConfigDialogState();
}

class _AddConfigDialogState extends State<_AddConfigDialog> {
  String? _key;

  /// Autocomplete 输入框 controller（由框架创建，fieldViewBuilder 中捕获）。
  TextEditingController? _keyField;
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加配置项'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  final input = textEditingValue.text.toLowerCase();
                  return widget.hints.keys
                      .where((k) => k.contains(input))
                      .toList();
                },
                onSelected: (value) => setState(() => _key = value),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  _keyField = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: '配置键（如 ip4.addr、hostname）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                decoration: const InputDecoration(
                  labelText: '配置值',
                  hintText: '如 192.168.1.51/24、yes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in widget.hints.entries)
                    ActionChip(
                      label: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 11),
                      ),
                      tooltip: entry.value,
                      onPressed: () => setState(() => _key = entry.key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final key = (_key ?? _keyField?.text.trim() ?? '').trim();
            if (key.isEmpty) return;
            Navigator.pop(context, (key: key, value: _value.text.trim()));
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
