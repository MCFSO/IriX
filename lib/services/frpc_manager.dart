// frpc 本地进程管理器
//
// 负责下载 OpenFrp 官方 frpc（Windows amd64 zip），
// 支持两种启动方式：
// - 简易启动：`frpc -u <token> -p <隧道ID>`（OpenFrp 专属）；
// - 配置启动：`frpc -c <config.toml>`（自建 frps 等通用场景）。
// 进程与输出缓冲均为全局状态（单例 + ChangeNotifier），
// 切换页面不会中断已启动的隧道。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/ofrp_service.dart';

/// frpc 进程管理器（单例）。
class FrpcManager extends ChangeNotifier {
  static final FrpcManager instance = FrpcManager._();
  FrpcManager._();

  String? _frpcPath;
  bool _downloading = false;

  /// 按隧道 key（如 'ofrp-123' / 'custom-my'）记录的运行进程。
  final Map<String, Process> _processes = {};

  /// 按隧道 key 记录的输出缓冲（stdout+stderr）。
  final Map<String, String> _outputs = {};

  /// 是否正在下载 frpc。
  bool get downloading => _downloading;

  /// 指定隧道是否在运行。
  bool isRunning(String key) => _processes.containsKey(key);

  /// 指定隧道的输出（最近 4000 字符）。
  String? outputFor(String key) => _outputs[key];

  /// 运行中的隧道 key 列表。
  List<String> get runningKeys => _processes.keys.toList();

  /// 确保 frpc 可执行文件存在，不存在时下载最新版并解压。
  Future<String> ensureFrpc() async {
    if (_frpcPath != null && File(_frpcPath!).existsSync()) {
      return _frpcPath!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final frpcDir = Directory(p.join(appDir.path, 'ofrp', 'frpc'));
    final exe = File(p.join(frpcDir.path, 'frpc.exe'));
    if (exe.existsSync()) {
      _frpcPath = exe.path;
      return exe.path;
    }

    _downloading = true;
    notifyListeners();
    try {
      final info = await OfrpService.instance.getSoftwareInfo();
      if (info.latestFull.isEmpty || info.sources.isEmpty) {
        throw Exception('无法获取 frpc 下载信息');
      }
      var ok = false;
      for (final source in info.sources) {
        final url = '$source/${info.latestFull}/frpc_windows_amd64.zip';
        try {
          await _downloadAndExtract(url, frpcDir);
          ok = true;
          break;
        } catch (e) {
          debugPrint('frpc download failed ($source): $e');
        }
      }
      if (!ok) throw Exception('frpc 下载失败，请检查网络后重试');
      final frpcExe = _findFrpcExe(frpcDir);
      if (frpcExe == null) {
        throw Exception('解压后未找到 frpc 可执行文件');
      }
      if (frpcExe.path != exe.path) {
        await frpcExe.rename(exe.path);
      }
      _frpcPath = exe.path;
      return exe.path;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// 在解压目录中递归查找 frpc 可执行文件（新版命名为
  /// frpc_windows_amd64.exe，旧版为 frpc.exe，均可能带版本目录前缀）。
  File? _findFrpcExe(Directory dir) {
    for (final entry in dir.listSync(recursive: true)) {
      if (entry is! File) continue;
      final name = p.basename(entry.path).toLowerCase();
      if (name.startsWith('frpc') && name.endsWith('.exe')) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _downloadAndExtract(String url, Directory targetDir) async {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);
    final archive = ZipDecoder().decodeBytes(res.bodyBytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final outPath = p.join(targetDir.path, file.name);
      Directory(p.dirname(outPath)).createSync(recursive: true);
      File(outPath).writeAsBytesSync(file.content as List<int>);
    }
  }

  /// OpenFrp 简易启动：frpc -u token -p proxyId。
  Future<void> startOpenFrp(String token, String proxyId) =>
      _spawn('ofrp-$proxyId', (path) async {
        return Process.start(path, [
          '-u',
          token,
          '-p',
          proxyId,
        ], workingDirectory: p.dirname(path));
      });

  /// 通用配置启动：写入 TOML 配置后以 frpc -c 运行。
  Future<void> startWithConfig(String configContent, String key) =>
      _spawn(key, (path) async {
        final appDir = await getApplicationDocumentsDirectory();
        final configDir = Directory(p.join(appDir.path, 'ofrp', 'configs'));
        if (!configDir.existsSync()) {
          configDir.createSync(recursive: true);
        }
        final configFile = File(p.join(configDir.path, '$key.toml'));
        await configFile.writeAsString(configContent);
        return Process.start(path, [
          '-c',
          configFile.path,
        ], workingDirectory: p.dirname(path));
      });

  Future<void> _spawn(
    String key,
    Future<Process> Function(String frpcPath) starter,
  ) async {
    if (_processes.containsKey(key)) return;
    final path = await ensureFrpc();
    if (_downloading) return;
    final process = await starter(path);
    _processes[key] = process;
    _outputs[key] = '';

    void onOutput(String chunk) {
      _outputs[key] = (_outputs[key] ?? '') + chunk;
      if (_outputs[key]!.length > 8000) {
        _outputs[key] = _outputs[key]!.substring(_outputs[key]!.length - 8000);
      }
      notifyListeners();
    }

    process.stdout.transform(utf8.decoder).listen(onOutput);
    process.stderr.transform(utf8.decoder).listen(onOutput);
    unawaited(
      process.exitCode.then((_) {
        _processes.remove(key);
        notifyListeners();
      }),
    );
    notifyListeners();
  }

  /// 停止指定隧道。
  Future<void> stop(String key) async {
    final process = _processes.remove(key);
    if (process == null) return;
    process.kill(ProcessSignal.sigkill);
    notifyListeners();
  }

  /// 停止全部隧道。
  Future<void> stopAll() async {
    for (final key in _processes.keys.toList()) {
      _processes[key]?.kill(ProcessSignal.sigkill);
    }
    _processes.clear();
    notifyListeners();
  }
}
