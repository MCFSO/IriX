// frpc 本地进程管理器
//
// 负责下载 OpenFrp 官方 frpc（按平台选择 Windows zip / Linux、macOS tar.gz），
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
///
/// 支持两种 frpc 变体（flavor）：
/// - 'openfrp'：OpenFrp 官方 frpc（新版本，仅支持 TOML 配置，下载 zip/tar.gz）；
/// - 'chmlfrp'：ChmlFrp 官方 frpc（0.51.x 分支，仅支持 INI 配置，直接下载可执行文件）。
class FrpcManager extends ChangeNotifier {
  static final FrpcManager instance = FrpcManager._();
  FrpcManager._();

  /// flavor -> frpc 可执行文件路径。
  final Map<String, String> _frpcPaths = {};
  bool _downloading = false;

  /// 按隧道 key（如 'ofrp-123' / 'custom-my'）记录的运行进程。
  final Map<String, Process> _processes = {};

  /// 按隧道 key 记录的输出缓冲（stdout+stderr）。
  final Map<String, String> _outputs = {};

  /// 是否正在下载 frpc。
  bool get downloading => _downloading;

  /// 指定隧道是否在运行。
  bool isRunning(String key) => _processes.containsKey(key);

  /// 指定隧道的输出（内存保留最近 [maxOutputChars] 字符）。
  String? outputFor(String key) => _outputs[key];

  /// 清空指定隧道的内存日志（不影响已持久化的日志文件）。
  void clearOutput(String key) {
    if (!_outputs.containsKey(key)) return;
    _outputs[key] = '';
    notifyListeners();
  }

  /// 内存中保留的日志上限（约 200KB），超出后丢弃最旧内容。
  static const int maxOutputChars = 200 * 1024;

  /// 日志持久化目录（APP 根目录/logs）。
  String? _logsDir;

  Future<String> _ensureLogsDir() async {
    if (_logsDir != null) return _logsDir!;
    final appRoot = p.dirname(Platform.resolvedExecutable);
    final dir = Directory(p.join(appRoot, 'logs'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return _logsDir = dir.path;
  }

  /// 运行中的隧道 key 列表。
  List<String> get runningKeys => _processes.keys.toList();

  /// 当前平台对应的 frpc 下载文件名（如 frpc_windows_amd64.zip）。
  ///
  /// macOS 官方命名沿用了文档中的 drawin 拼写。
  String get _downloadFileName {
    final arch = _archName;
    return switch (Platform.operatingSystem) {
      'windows' => 'frpc_windows_$arch.zip',
      'linux' => 'frpc_linux_$arch.tar.gz',
      'macos' => 'frpc_drawin_$arch.tar.gz',
      final os => throw Exception('不支持的平台: $os'),
    };
  }

  /// 当前设备架构（amd64 / 386 / arm64 / arm）。
  String get _archName {
    if (Platform.isWindows) {
      final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64')
          .toUpperCase();
      return switch (arch) {
        'AMD64' => 'amd64',
        'X86' => '386',
        'ARM64' => 'arm64',
        'ARM' => 'arm',
        _ => 'amd64',
      };
    }
    try {
      final out = (Process.runSync('uname', ['-m']).stdout as String)
          .trim()
          .toLowerCase();
      if (out == 'x86_64' || out == 'amd64') return 'amd64';
      if (out.startsWith('i3') ||
          out.startsWith('i4') ||
          out.startsWith('i5') ||
          out.startsWith('i6')) {
        return '386';
      }
      if (out == 'aarch64' || out == 'arm64') return 'arm64';
      if (out.startsWith('arm')) return 'arm';
    } catch (_) {
      // 忽略，退回 amd64。
    }
    return 'amd64';
  }

  /// 解压后的可执行文件名（Windows 带 .exe 后缀）。
  String get _binaryName => Platform.isWindows ? 'frpc.exe' : 'frpc';

  /// 确保指定 flavor 的 frpc 可执行文件存在，不存在时下载。
  Future<String> ensureFrpc([String flavor = 'openfrp']) async {
    final cached = _frpcPaths[flavor];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final frpcDir = Directory(
      p.join(appDir.path, 'ofrp', flavor == 'chmlfrp' ? 'frpc-chml' : 'frpc'),
    );
    final exe = File(p.join(frpcDir.path, _binaryName));
    if (exe.existsSync()) {
      _frpcPaths[flavor] = exe.path;
      return exe.path;
    }

    _downloading = true;
    notifyListeners();
    try {
      if (flavor == 'chmlfrp') {
        await _downloadChmlFrpc(frpcDir, exe);
      } else {
        await _downloadOpenFrpFrpc(frpcDir, exe);
      }
      _frpcPaths[flavor] = exe.path;
      return exe.path;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  /// 下载 OpenFrp 官方 frpc（zip/tar.gz）。
  Future<void> _downloadOpenFrpFrpc(Directory frpcDir, File exe) async {
    final info = await OfrpService.instance.getSoftwareInfo();
    if (info.latestFull.isEmpty || info.sources.isEmpty) {
      throw Exception('无法获取 frpc 下载信息');
    }
    var ok = false;
    for (final source in info.sources) {
      final url = '$source/${info.latestFull}/$_downloadFileName';
      try {
        await _downloadAndExtract(url, frpcDir);
        ok = true;
        break;
      } catch (e) {
        debugPrint('frpc download failed ($source): $e');
      }
    }
    if (!ok) throw Exception('frpc 下载失败，请检查网络后重试');
    final frpcBin = _findFrpcBinary(frpcDir);
    if (frpcBin == null) {
      throw Exception('解压后未找到 frpc 可执行文件');
    }
    if (frpcBin.path != exe.path) {
      await frpcBin.rename(exe.path);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', exe.path]);
    }
  }

  /// 下载 ChmlFrp 官方 frpc（INI 兼容版本，直接下载可执行文件）。
  Future<void> _downloadChmlFrpc(Directory frpcDir, File exe) async {
    final infoUrl = 'https://cf-v1.uapis.cn/download/frpc/frpc_info.json';
    final res = await http
        .get(Uri.parse(infoUrl))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('获取 ChmlFrp frpc 信息失败 HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('获取 ChmlFrp frpc 信息失败：服务器返回空响应');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final downloads = ((json['data'] ?? const {}) as Map)['downloads'];
    if (downloads is! List) {
      throw Exception('ChmlFrp frpc 信息格式错误');
    }
    final platform = _chmlPlatform();
    Map<String, dynamic>? match;
    for (final entry in downloads) {
      if (entry is! Map) continue;
      final os = (entry['os'] ?? '').toString();
      final arch = (entry['arch'] ?? '').toString();
      if (os == platform.$1 && arch == platform.$2) {
        match = entry.cast<String, dynamic>();
        break;
      }
    }
    final link = match?['link']?.toString();
    if (link == null || link.isEmpty) {
      throw Exception('ChmlFrp 不支持当前平台 (${platform.$1}/${platform.$2})');
    }
    if (frpcDir.existsSync()) {
      frpcDir.deleteSync(recursive: true);
    }
    frpcDir.createSync(recursive: true);
    final bin = await http
        .get(Uri.parse(link))
        .timeout(const Duration(seconds: 120));
    if (bin.statusCode != 200) {
      throw Exception('下载 ChmlFrp frpc 失败 HTTP ${bin.statusCode}');
    }
    await exe.writeAsBytes(bin.bodyBytes);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', exe.path]);
    }
  }

  /// ChmlFrp frpc_info.json 中的 (os, arch) 组合。
  ({String $1, String $2}) _chmlPlatform() {
    final arch = switch (_archName) {
      'amd64' => 'x86_64',
      '386' => 'x86',
      'arm64' => 'aarch64',
      'arm' => 'arm',
      final a => a,
    };
    return (
      $1: Platform.operatingSystem,
      $2: arch,
    );
  }

  /// 下载并解压（zip 或 tar.gz 由 URL 扩展名决定）。
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
    final archive = _decodeArchive(url, res.bodyBytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final outPath = p.join(targetDir.path, file.name);
      Directory(p.dirname(outPath)).createSync(recursive: true);
      File(outPath).writeAsBytesSync(file.content as List<int>);
    }
  }

  Archive _decodeArchive(String url, List<int> bytes) {
    if (url.endsWith('.tar.gz') || url.endsWith('.tgz')) {
      return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    }
    return ZipDecoder().decodeBytes(bytes);
  }

  /// 在解压目录中递归查找 frpc 可执行文件（新版命名为
  /// frpc_windows_amd64.exe / frpc_linux_amd64，旧版为 frpc.exe / frpc，
  /// 均可能带版本目录前缀）。
  File? _findFrpcBinary(Directory dir) {
    final isWindows = Platform.isWindows;
    for (final entry in dir.listSync(recursive: true)) {
      if (entry is! File) continue;
      final name = p.basename(entry.path).toLowerCase();
      if (!name.startsWith('frpc')) continue;
      if (isWindows && !name.endsWith('.exe')) continue;
      if (!isWindows && name.endsWith('.exe')) continue;
      return entry;
    }
    return null;
  }

  /// OpenFrp 简易启动：frpc -u token -p proxyId。
  Future<void> startOpenFrp(String token, String proxyId) =>
      _spawn('ofrp-$proxyId', 'openfrp', (path) async {
        return Process.start(path, [
          '-u',
          token,
          '-p',
          proxyId,
        ], workingDirectory: p.dirname(path));
      });

  /// 通用配置启动：写入配置文件后以 frpc -c 运行。
  ///
  /// [flavor] 选择 frpc 变体：'openfrp'（TOML）/ 'chmlfrp'（INI）。
  Future<void> startWithConfig(
    String configContent,
    String key, {
    String flavor = 'openfrp',
  }) =>
      _spawn(key, flavor, (path) async {
        final appDir = await getApplicationDocumentsDirectory();
        final configDir = Directory(p.join(appDir.path, 'ofrp', 'configs'));
        if (!configDir.existsSync()) {
          configDir.createSync(recursive: true);
        }
        final ext = flavor == 'chmlfrp' ? 'ini' : 'toml';
        final configFile = File(p.join(configDir.path, '$key.$ext'));
        await configFile.writeAsString(configContent);
        return Process.start(path, [
          '-c',
          configFile.path,
        ], workingDirectory: p.dirname(path));
      });

  Future<void> _spawn(
    String key,
    String flavor,
    Future<Process> Function(String frpcPath) starter,
  ) async {
    if (_processes.containsKey(key)) return;
    final path = await ensureFrpc(flavor);
    if (_downloading) return;
    final process = await starter(path);
    _processes[key] = process;
    _outputs[key] = '';

    // 持久化日志：追加写入 APP 根目录/logs/frpc-<key>.log（跨会话保留）。
    IOSink? logSink;
    try {
      final logsDir = await _ensureLogsDir();
      logSink = File(p.join(logsDir, 'frpc-$key.log')).openWrite(
        mode: FileMode.append,
      );
      logSink.writeln(
        '===== ${DateTime.now().toIso8601String()} frpc 启动 (flavor: $flavor) =====',
      );
    } catch (e) {
      debugPrint('frpc log file open failed: $e');
    }

    void onOutput(String chunk) {
      _outputs[key] = (_outputs[key] ?? '') + chunk;
      if (_outputs[key]!.length > maxOutputChars) {
        _outputs[key] = _outputs[key]!
            .substring(_outputs[key]!.length - maxOutputChars);
      }
      logSink?.write(chunk);
      notifyListeners();
    }

    process.stdout.transform(utf8.decoder).listen(onOutput);
    process.stderr.transform(utf8.decoder).listen(onOutput);
    unawaited(
      process.exitCode.then((code) async {
        try {
          logSink?.writeln(
            '\n===== ${DateTime.now().toIso8601String()} frpc 退出 (code: $code) =====\n',
          );
          await logSink?.close();
        } catch (_) {}
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
