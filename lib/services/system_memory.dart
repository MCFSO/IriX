// 系统物理内存探测
//
// Dart 标准库不提供物理内存信息，故按平台读取：
//   Linux  —— /proc/meminfo（MemTotal / MemAvailable）
//   macOS  —— sysctl hw.memsize + vm_stat（free + inactive + speculative）
//   Windows—— PowerShell CIM 查询（Win32_OperatingSystem），
//             失败回退 wmic（部分新系统已移除 wmic）
//
// 结果按进程生命周期缓存：内存总量在运行期几乎不变，重复探测只会拖慢
// 设置页与实例创建。探测失败时返回保守的兜底值（8 GiB 总量 / 4 GiB 可用），
// 保证自动分配仍能给出可用的堆大小，而不是直接报错。

import 'dart:async';
import 'dart:io';

/// 一次物理内存探测结果。
class SystemMemoryInfo {
  const SystemMemoryInfo({
    required this.totalBytes,
    required this.availableBytes,
    required this.source,
  });

  /// 物理内存总量。
  final int totalBytes;

  /// 当前可用内存（Windows 为 FreePhysicalMemory，Linux 为 MemAvailable，
  /// macOS 为 free + inactive + speculative）。
  final int availableBytes;

  /// 数据来源（`proc-meminfo` / `sysctl` / `powershell` / `wmic` / `fallback`）。
  final String source;

  int get totalMb => totalBytes ~/ (1024 * 1024);

  int get availableMb => availableBytes ~/ (1024 * 1024);
}

/// 物理内存探测入口（带缓存）。
class SystemMemory {
  SystemMemory._();

  static SystemMemoryInfo? _cached;

  /// 探测失败时的兜底值（保守估计，避免把堆开得比真实内存还大）。
  static const SystemMemoryInfo fallback = SystemMemoryInfo(
    totalBytes: 8 * 1024 * 1024 * 1024,
    availableBytes: 4 * 1024 * 1024 * 1024,
    source: 'fallback',
  );

  /// 读取系统内存信息；同一进程内只真正探测一次。
  static Future<SystemMemoryInfo> detect({bool refresh = false}) async {
    if (!refresh && _cached != null) return _cached!;
    SystemMemoryInfo? info;
    try {
      if (Platform.isLinux) {
        info = await _readProcMeminfo();
      } else if (Platform.isMacOS) {
        info = await _readMacOs();
      } else if (Platform.isWindows) {
        info = await _readWindows();
      }
    } catch (_) {
      info = null;
    }
    _cached = info ?? fallback;
    return _cached!;
  }

  /// 测试用：注入探测结果，避免真实读机器信息。
  static void debugSetCache(SystemMemoryInfo? info) => _cached = info;

  // === Linux ===

  static Future<SystemMemoryInfo?> _readProcMeminfo() async {
    final file = File('/proc/meminfo');
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    final total = _meminfoValue(text, 'MemTotal');
    final available =
        _meminfoValue(text, 'MemAvailable') ?? _meminfoValue(text, 'MemFree');
    if (total == null) return null;
    return SystemMemoryInfo(
      totalBytes: total,
      availableBytes: available ?? total,
      source: 'proc-meminfo',
    );
  }

  /// 解析 `/proc/meminfo` 的 `Key:  12345 kB` 行，返回字节数。
  static int? _meminfoValue(String text, String key) {
    final match = RegExp(
      '^$key:\\s+(\\d+)\\s*kB',
      multiLine: true,
    ).firstMatch(text);
    if (match == null) return null;
    final kb = int.tryParse(match.group(1)!);
    return kb == null ? null : kb * 1024;
  }

  // === macOS ===

  static Future<SystemMemoryInfo?> _readMacOs() async {
    final sizeResult = await Process.run('sysctl', ['-n', 'hw.memsize']);
    if (sizeResult.exitCode != 0) return null;
    final total = int.tryParse('${sizeResult.stdout}'.trim());
    if (total == null || total <= 0) return null;

    // vm_stat 每页大小在首行给出（"page size of 16384 bytes"）。
    final vmResult = await Process.run('vm_stat', []);
    var available = 0;
    if (vmResult.exitCode == 0) {
      final text = '${vmResult.stdout}';
      final pageSize =
          int.tryParse(
            RegExp(r'page size of (\d+) bytes').firstMatch(text)?.group(1) ??
                '',
          ) ??
          4096;
      var pages = 0;
      for (final key in ['Pages free', 'Pages inactive', 'Pages speculative']) {
        final m = RegExp('$key:\\s+(\\d+)').firstMatch(text);
        if (m != null) pages += int.tryParse(m.group(1)!) ?? 0;
      }
      available = pages * pageSize;
    }

    return SystemMemoryInfo(
      totalBytes: total,
      availableBytes: available > 0 ? available : total,
      source: 'sysctl',
    );
  }

  // === Windows ===

  static Future<SystemMemoryInfo?> _readWindows() async {
    // 优先 PowerShell（wmic 在 Windows 11 24H2 起默认不再安装）。
    final ps = await _run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'$os = Get-CimInstance Win32_OperatingSystem; '
          r'"$($os.TotalVisibleMemorySize) $($os.FreePhysicalMemory)"',
    ]);
    final parsed = _parseWindowsPair(ps, 'powershell');
    if (parsed != null) return parsed;

    final wmic = await _run('wmic', [
      'OS',
      'get',
      'TotalVisibleMemorySize,FreePhysicalMemory',
      '/value',
    ]);
    return _parseWindowsPair(wmic, 'wmic');
  }

  /// 解析 `Total Free`（kB，空格分隔）或 wmic 的 `Key=Value` 行。
  static SystemMemoryInfo? _parseWindowsPair(
    ProcessResult? result,
    String source,
  ) {
    if (result == null || result.exitCode != 0) return null;
    final text = '${result.stdout}';

    final pair = RegExp(
      r'^(\d+)\s+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(text);
    int? totalKb;
    int? freeKb;
    if (pair != null) {
      totalKb = int.tryParse(pair.group(1)!);
      freeKb = int.tryParse(pair.group(2)!);
    } else {
      totalKb = int.tryParse(
        RegExp(r'TotalVisibleMemorySize=(\d+)').firstMatch(text)?.group(1) ??
            '',
      );
      freeKb = int.tryParse(
        RegExp(r'FreePhysicalMemory=(\d+)').firstMatch(text)?.group(1) ?? '',
      );
    }
    if (totalKb == null || totalKb <= 0) return null;

    return SystemMemoryInfo(
      totalBytes: totalKb * 1024,
      availableBytes: (freeKb ?? totalKb) * 1024,
      source: source,
    );
  }

  /// 执行外部命令，超时或异常返回 null（探测失败不应影响启动流程）。
  static Future<ProcessResult?> _run(String exe, List<String> args) async {
    try {
      return await Process.run(exe, args).timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }
}
