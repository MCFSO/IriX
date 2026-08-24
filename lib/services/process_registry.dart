// 服务器进程 PID 登记表
// 每次启动服务器时记录其 PID、镜像名与启动时间（SQLite settings 表），
// 启动器重启后据此检测进程是否仍存活，存活则「接管」该实例：
// 恢复运行状态并继续尾随其日志文件（终端接管）。
// 进程退出 / 实例删除时清除登记，避免 PID 复用误判。

import 'dart:convert';
import 'dart:io';

import 'database_manager.dart';

/// 一次服务器运行的登记信息。
class RunningProcessRecord {
  /// 服务器进程 PID。
  final int pid;

  /// 进程镜像名（如 `java.exe`），用于防 PID 复用误判。
  final String imageName;

  /// 进程启动时间（ISO-8601，来自启动器记录时刻）。
  final String startedAt;

  const RunningProcessRecord({
    required this.pid,
    required this.imageName,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
    'pid': pid,
    'imageName': imageName,
    'startedAt': startedAt,
  };

  factory RunningProcessRecord.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return RunningProcessRecord(
      pid: (map['pid'] as num?)?.toInt() ?? -1,
      imageName: map['imageName'] as String? ?? '',
      startedAt: map['startedAt'] as String? ?? '',
    );
  }
}

/// 运行中进程的登记与存活检测。
///
/// 数据存于 SQLite `settings` 表（键：`server_pid_<instanceId>`）。
/// 存活检测：Windows 用 `tasklist` 查询 PID 并比对镜像名；
/// Linux 检查 `/proc/<pid>`；macOS 用 `kill -0`。
class ProcessRegistry {
  ProcessRegistry._();

  static String _key(String instanceId) => 'server_pid_$instanceId';

  /// 记录实例对应的服务器进程。
  static Future<void> record(
    String instanceId,
    RunningProcessRecord record,
  ) async {
    await DatabaseManager.instance.setSetting(
      _key(instanceId),
      jsonEncode(record.toJson()),
    );
  }

  /// 读取实例登记的进程信息；无登记或数据损坏时返回 null。
  static Future<RunningProcessRecord?> read(String instanceId) async {
    final raw = await DatabaseManager.instance.getSetting(_key(instanceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return RunningProcessRecord.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// 清除实例的进程登记。
  static Future<void> clear(String instanceId) async {
    await DatabaseManager.instance.deleteSetting(_key(instanceId));
  }

  /// 检测 PID 是否仍存活。
  ///
  /// [imageName] 非空时（Windows）同时校验镜像名一致，降低 PID 复用误判。
  /// 检测渠道不可用时保守返回 true（视为存活），避免实例被误判为已停止。
  static Future<bool> isAlive(int pid, {String? imageName}) async {
    if (pid <= 0) return false;
    if (Platform.isWindows) {
      return _isAliveWindows(pid, imageName);
    }
    if (Platform.isLinux) {
      try {
        return Directory('/proc/$pid').existsSync();
      } catch (_) {
        return true;
      }
    }
    // macOS 及其他 POSIX：kill -0 探测（不发送实际信号）。
    try {
      final result = await Process.run('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return true;
    }
  }

  /// Windows：`tasklist /FI "PID eq <pid>" /FO CSV /NH` 查询。
  ///
  /// 输出形如 `"java.exe","1234","Console","1","123,456 K"`；
  /// 无匹配时仅输出本地化提示（不含 CSV 行），按无结果处理。
  static Future<bool> _isAliveWindows(int pid, String? imageName) async {
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      final stdout = (result.stdout as String? ?? '');
      for (final line in stdout.split('\n')) {
        final fields = line.split('","');
        if (fields.length < 2) continue;
        final image = fields.first.replaceAll('"', '').trim();
        final pidField = fields[1].replaceAll('"', '').trim();
        if (pidField != '$pid') continue;
        final expected = imageName?.trim().toLowerCase() ?? '';
        if (expected.isEmpty) return true;
        return image.toLowerCase() == expected;
      }
      return false;
    } catch (_) {
      return true;
    }
  }
}
