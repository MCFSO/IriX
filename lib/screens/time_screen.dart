// 时间系统页面
//
// 展示 IriX 统一时间系统的实时状态：应用时钟、NTP 服务器、偏移/漂移、
// 不确定度、TSC 高精度插值，以及服务器列表与轮询配置的编辑入口。
//
// 时间系统是应用内所有时间戳（HTTPS 证书有效期、设备绑定签名、TOTP、
// 备份/日志/编排）的唯一权威；本页只读展示 + 触发同步，不直接改系统时间。

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/adb_bridge.dart';
import '../services/time_service.dart';
import '../utils/apple_widgets.dart';

class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key});

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  Timer? _statusTimer;
  Timer? _clockTimer;
  Map<String, dynamic>? _status;
  DateTime _now = TimeService.instance.nowLocal();
  bool _busy = false;
  List<dynamic>? _probeResults;
  Map<String, dynamic>? _accuracy;
  AdbReverseResult? _adb;
  bool _adbBusy = false;

  final TextEditingController _serversCtrl = TextEditingController();
  final TextEditingController _minPollCtrl = TextEditingController();
  final TextEditingController _maxPollCtrl = TextEditingController();
  final TextEditingController _samplesCtrl = TextEditingController();
  final TextEditingController _holdoverCtrl = TextEditingController();
  bool _precision = true;
  bool _formInitialized = false;

  @override
  void initState() {
    super.initState();
    _adb = AdbBridge.instance.result.value;
    AdbBridge.instance.result.addListener(_onAdbChanged);
    _refresh();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _clockTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _now = TimeService.instance.nowLocal());
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _clockTimer?.cancel();
    AdbBridge.instance.result.removeListener(_onAdbChanged);
    _serversCtrl.dispose();
    _minPollCtrl.dispose();
    _maxPollCtrl.dispose();
    _samplesCtrl.dispose();
    _holdoverCtrl.dispose();
    super.dispose();
  }

  void _onAdbChanged() {
    if (!mounted) return;
    setState(() => _adb = AdbBridge.instance.result.value);
  }

  Future<void> _applyAdb() async {
    if (_adbBusy) return;
    setState(() => _adbBusy = true);
    try {
      await AdbBridge.instance.applyReverse();
    } finally {
      if (mounted) setState(() => _adbBusy = false);
    }
  }

  Future<void> _refresh() async {
    final status = TimeService.instance.status();
    if (!mounted) return;
    setState(() {
      _status = status;
      _initForm(status);
    });
  }

  void _initForm(Map<String, dynamic> status) {
    if (_formInitialized) return;
    final config = status['config'];
    if (config is! Map<String, dynamic>) return;
    final servers = (config['servers'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .join('\n');
    _serversCtrl.text = servers;
    _minPollCtrl.text = '${config['min_poll_log2'] ?? 4}';
    _maxPollCtrl.text = '${config['max_poll_log2'] ?? 8}';
    _samplesCtrl.text = '${config['samples_per_poll'] ?? 2}';
    _holdoverCtrl.text = '${config['holdover_ppm'] ?? 15}';
    _precision = config['precision'] as bool? ?? true;
    _formInitialized = true;
  }

  Future<void> _forceReanchor() async {
    setState(() => _busy = true);
    try {
      final result = await TimeService.instance.forceReanchor();
      if (!mounted) return;
      setState(() => _status = result);
      _toast('已强制切到 NTP 共识时间');
    } catch (e) {
      if (mounted) _toast('强制重置失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final result = await TimeService.instance.syncNow();
      if (!mounted) return;
      setState(() => _status = result);
      _toast('同步完成：${_syncLabel(result)}');
    } catch (e) {
      if (mounted) _toast('同步失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _probe() async {
    setState(() => _busy = true);
    try {
      final results = await TimeService.instance.probe();
      if (!mounted) return;
      setState(() => _probeResults = results);
    } catch (e) {
      if (mounted) _toast('探测失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _measureAccuracy() async {
    setState(() => _busy = true);
    try {
      final report = await TimeService.instance.measureAccuracy();
      if (!mounted) return;
      setState(() => _accuracy = report);
      final median = (report['median_offset_ms'] as num? ?? 0).toDouble();
      final spread = (report['spread_ms'] as num? ?? 0).toDouble();
      _toast(
        '应用时钟 vs NTP：中位偏差 ${median.toStringAsFixed(2)} ms，'
        '服务器极差 ${spread.toStringAsFixed(2)} ms',
      );
    } catch (e) {
      if (mounted) _toast('测量失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveConfig() async {
    final servers = _serversCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final minPoll = int.tryParse(_minPollCtrl.text.trim()) ?? 4;
    final maxPoll = int.tryParse(_maxPollCtrl.text.trim()) ?? 8;
    final samples = int.tryParse(_samplesCtrl.text.trim()) ?? 2;
    final holdover = double.tryParse(_holdoverCtrl.text.trim()) ?? 15.0;
    if (servers.isEmpty) {
      _toast('至少保留一个 NTP 服务器');
      return;
    }
    setState(() => _busy = true);
    try {
      await TimeService.instance.configure({
        'servers': servers,
        'min_poll_log2': minPoll.clamp(0, 10),
        'max_poll_log2': maxPoll.clamp(0, 10),
        'samples_per_poll': samples.clamp(1, 5),
        'precision': _precision,
        'holdover_ppm': holdover.clamp(0.1, 1000.0),
      });
      _toast('配置已保存，正在重新同步');
      await _syncNow();
    } catch (e) {
      if (mounted) _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final available = status?['available'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('时间系统'),
        actions: [
          IconButton(
            tooltip: '立即同步',
            onPressed: _busy || !available ? null : _syncNow,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _clockCard(status),
          const SizedBox(height: 12),
          if (!available) _unavailableCard(status),
          if (available) ...[
            _statsCard(status),
            const SizedBox(height: 12),
            _actionsCard(),
            const SizedBox(height: 12),
            _serversCard(status),
            const SizedBox(height: 12),
            _gnssCard(status),
            const SizedBox(height: 12),
            _bridgeCard(status),
            if (_probeResults != null) ...[
              const SizedBox(height: 12),
              _probeCard(),
            ],
            if (_accuracy != null) ...[
              const SizedBox(height: 12),
              _accuracyCard(),
            ],
            const SizedBox(height: 12),
            _configCard(status),
            const SizedBox(height: 12),
            _precisionCard(status),
            const SizedBox(height: 12),
            _aboutCard(),
          ],
        ],
      ),
    );
  }

  Widget _clockCard(Map<String, dynamic>? status) {
    final clock = status?['clock'] as Map<String, dynamic>?;
    final sync = status?['sync'] as Map<String, dynamic>?;
    final synced = clock?['synced'] == true;
    final locked = clock?['locked'] == true;
    final source = clock?['source'] as String? ?? 'system';
    final badge = !synced
        ? ('未同步', Colors.orange)
        : locked
        ? ('已锁定', Colors.greenAccent)
        : ('保持模式', Colors.yellow);
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    final ms = _now.millisecond.toString().padLeft(3, '0');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 20),
              const SizedBox(width: 8),
              const Text(
                '应用时钟',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badge.$2.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badge.$2.withValues(alpha: 0.5)),
                ),
                child: Text(
                  badge.$1,
                  style: TextStyle(color: badge.$2, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _busy ? null : _forceReanchor,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  backgroundColor: Colors.red.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text(
                  '强制重置时间基准',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$hh:$mm:$ss.$ms',
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_now.year}-${_two(_now.month)}-${_two(_now.day)} '
            '${_weekday(_now.weekday)} · 来源：$source',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 10),
          Text(
            _syncDescription(sync),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _unavailableCard(Map<String, dynamic>? status) {
    final error = status?['error'] as String? ?? TimeService.instance.lastError;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('时间系统未启用', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '未找到 xmc_time 动态库，当前退回系统时间。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 8),
          const Text(
            '运行 build_rust.bat / ./build_rust.sh 后重启应用即可启用 NTP 校准、'
            '漂移补偿与 HTTPS 证书时间裁决。',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _statsCard(Map<String, dynamic>? status) {
    final sync = status?['sync'] as Map<String, dynamic>? ?? {};
    final clock = status?['clock'] as Map<String, dynamic>? ?? {};
    final offsetMs = (sync['offset_ns'] as num? ?? 0) / 1e6;
    final uncertaintyMs = (clock['uncertainty_ns'] as num? ?? 0) / 1e6;
    final freq = (sync['freq_ppm'] as num? ?? 0).toDouble();
    final poll = (sync['poll_s'] as num? ?? 0).toDouble();
    final stratum = sync['stratum'] ?? 16;
    final samples = status?['samples'] ?? 0;
    final nextPoll = (status?['next_poll_in_s'] as num? ?? 0).toDouble();
    final systemSkew = (status?['system_skew_ms'] as num? ?? 0).toDouble();
    final baseline = (status?['baseline_ppm'] as num? ?? 0).toDouble();
    return _card(
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        children: [
          _metric('上次偏移', '${offsetMs.toStringAsFixed(3)} ms'),
          _metric('不确定度', '±${uncertaintyMs.toStringAsFixed(3)} ms'),
          _metric('频率修正', '${freq.toStringAsFixed(3)} ppm'),
          _metric('轮询间隔', poll < 1 ? '${poll.toStringAsFixed(1)} s' : '${poll.toStringAsFixed(0)} s'),
          _metric('下次轮询', '${nextPoll.toStringAsFixed(1)} s'),
          _metric('层级 / 样本', '$stratum / $samples'),
          _metric('累计同步', '${status?['total_syncs'] ?? 0} 次'),
          _metric('运行时长', _duration((status?['uptime_s'] as num? ?? 0).toDouble())),
          _metric(
            '与系统时间偏差',
            '${systemSkew >= 0 ? '+' : ''}${systemSkew.toStringAsFixed(3)} ms',
          ),
          _metric('持久化频率基线', '${baseline.toStringAsFixed(3)} ppm'),
        ],
      ),
    );
  }

  Widget _actionsCard() {
    return _card(
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          AppleButton(
            onPressed: _busy ? null : _syncNow,
            child: const Text('立即同步 NTP'),
          ),
          AppleButton(
            onPressed: _busy ? null : _probe,
            child: const Text('探测服务器'),
          ),
          AppleButton(
            onPressed: _busy ? null : _measureAccuracy,
            child: const Text('测量精度'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _saveConfig,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存配置'),
          ),
        ],
      ),
    );
  }

  Widget _serversCard(Map<String, dynamic>? status) {
    final servers = (status?['servers'] as List<dynamic>? ?? const []);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NTP 服务器', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (servers.isEmpty)
            const Text('尚未配置服务器', style: TextStyle(color: Colors.white54))
          else
            ...servers.map((raw) {
              final s = raw as Map<String, dynamic>;
              final reachable = s['reachable'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      reachable ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: reachable ? Colors.greenAccent : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s['address'] ?? ''}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (s['last_error'] != null)
                            Text(
                              '${s['last_error']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.orangeAccent,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      reachable
                          ? '${((s['offset_ms'] as num? ?? 0)).toStringAsFixed(2)} ms · '
                                'RTT ${((s['delay_ms'] as num? ?? 0)).toStringAsFixed(1)} ms'
                          : '不可达',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _gnssCard(Map<String, dynamic>? status) {
    final g = status?['gnss'] as Map<String, dynamic>? ?? {};
    final samples = (g['samples'] as num? ?? 0).toInt();
    final accepted = (g['accepted_samples'] as num? ?? 0).toInt();
    final hasData = samples > 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.satellite_alt, size: 20),
              const SizedBox(width: 8),
              const Text(
                'GPS / 北斗',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                hasData
                    ? (g['accepted'] == true ? '已采纳' : '最近一帧未采纳')
                    : '未接入',
                style: TextStyle(
                  fontSize: 12,
                  color: g['accepted'] == true
                      ? Colors.greenAccent
                      : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasData)
            const Text(
              'Android 侧通过 time_request("gnss_sample", …) 注入 GPS/北斗时间样本；'
              '对齐方式与验收标准见 docs/android-gnss-time-calibration.md。',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            )
          else ...[
            _kv('来源 / 星座', '${g['source'] ?? ''} / ${g['constellation'] ?? ''}'),
            _kv('fix / 卫星数', '${g['fix'] ?? ''} / ${g['sv_count'] ?? 0}'),
            _kv(
              '样本不确定度',
              '±${((g['uncertainty_ns'] as num? ?? 0) / 1e6).toStringAsFixed(3)} ms',
            ),
            _kv('最近偏移', '${(g['offset_ms'] as num? ?? 0).toStringAsFixed(3)} ms'),
            _kv('样本数（采纳/总）', '$accepted / $samples'),
            if (g['last_error'] != null)
              Text(
                '最近拒绝原因：${g['last_error']}',
                style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
              ),
          ],
        ],
      ),
    );
  }

  Widget _bridgeCard(Map<String, dynamic>? status) {
    final b = status?['bridge'] as Map<String, dynamic>? ?? {};
    final running = b['running'] == true;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.usb, size: 20),
              const SizedBox(width: 8),
              const Text(
                'ADB reverse 时间桥',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                running ? '监听中' : '未启动',
                style: TextStyle(
                  fontSize: 12,
                  color: running ? Colors.greenAccent : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('地址', '${b['addr'] ?? '—'}'),
          _kv('手机连接数', '${b['clients'] ?? 0}'),
          _kv('接收样本', '${b['samples'] ?? 0}'),
          _kv('ping', '${b['pings'] ?? 0}'),
          if (b['last_error'] != null)
            Text(
              '最近错误：${b['last_error']}',
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          const Divider(height: 18),
          _kv('内置 ADB', _adb?.adbPath ?? '未检测'),
          _kv(
            'ADB 设备',
            _adb == null || _adb!.devices.isEmpty
                ? '未发现'
                : _adb!.devices
                      .map((d) => '${d.serial} (${d.state})')
                      .join('、'),
          ),
          if (_adb != null)
            Text(
              _adb!.message,
              style: TextStyle(
                fontSize: 11,
                color: _adb!.ok ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
          if (_adb != null && _adb!.errors.isNotEmpty)
            Text(
              _adb!.errors.join('\n'),
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _adbBusy ? null : _applyAdb,
            icon: const Icon(Icons.usb, size: 16),
            label: Text(_adbBusy ? '正在应用…' : '应用 ADB reverse'),
          ),
          const SizedBox(height: 6),
          const Text(
            '桌面启动时自动执行 adb reverse tcp:47820 tcp:47820；\n'
            '手机需开启 USB 调试并在弹窗中允许 RSA 指纹。',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _probeCard() {
    final results = _probeResults ?? const [];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('探测结果（不拨钟）', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...results.map((raw) {
            final r = raw as Map<String, dynamic>;
            final ok = r['ok'] == true;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                ok
                    ? '${r['address']}  ${(r['offset_ms'] as num? ?? 0).toStringAsFixed(2)} ms  '
                          'RTT ${(r['delay_ms'] as num? ?? 0).toStringAsFixed(1)} ms  '
                          'stratum ${r['stratum']}'
                    : '${r['address']}  失败：${r['error']}',
                style: TextStyle(
                  fontSize: 12,
                  color: ok ? Colors.white70 : Colors.orangeAccent,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _accuracyCard() {
    final report = _accuracy!;
    final median = (report['median_offset_ms'] as num? ?? 0).toDouble();
    final mean = (report['mean_offset_ms'] as num? ?? 0).toDouble();
    final spread = (report['spread_ms'] as num? ?? 0).toDouble();
    final skew = (report['system_skew_ms'] as num? ?? 0).toDouble();
    final uncertainty = (report['uncertainty_ms'] as num? ?? 0).toDouble();
    final servers = (report['servers'] as List<dynamic>? ?? const []);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('精度测量', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                report['synced'] == true ? '已同步' : '未同步',
                style: TextStyle(
                  fontSize: 12,
                  color: report['synced'] == true
                      ? Colors.greenAccent
                      : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('应用时钟 vs NTP 中位偏差', '${median.toStringAsFixed(3)} ms'),
          _kv('平均偏差', '${mean.toStringAsFixed(3)} ms'),
          _kv('服务器间极差', '${spread.toStringAsFixed(3)} ms'),
          _kv(
            '应用时钟 - 系统时钟',
            '${skew >= 0 ? '+' : ''}${skew.toStringAsFixed(3)} ms',
          ),
          _kv('当前不确定度', '±${uncertainty.toStringAsFixed(3)} ms'),
          const SizedBox(height: 6),
          ...servers.map((raw) {
            final s = raw as Map<String, dynamic>;
            final ok = s['ok'] == true;
            return Text(
              ok
                  ? '${s['address']}  ${(s['offset_ms'] as num? ?? 0).toStringAsFixed(2)} ms  '
                        'RTT ${(s['delay_ms'] as num? ?? 0).toStringAsFixed(1)} ms'
                  : '${s['address']}  失败：${s['error']}',
              style: TextStyle(
                fontSize: 11,
                color: ok ? Colors.white54 : Colors.orangeAccent,
              ),
            );
          }),
          const SizedBox(height: 6),
          const Text(
            '这是“应用时钟相对多个 NTP 服务器共识”的偏差；系统时钟没有时间服务时，'
            '“应用时钟 - 系统时钟”就是本系统修正掉的误差。',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _configCard(Map<String, dynamic>? status) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('配置', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _serversCtrl,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'NTP 服务器（每行一个，可带端口）',
              hintText: 'ntp.aliyun.com\nntp.tencent.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _smallField(_minPollCtrl, '最小轮询 log2（4=16s）')),
              const SizedBox(width: 10),
              Expanded(child: _smallField(_maxPollCtrl, '最大轮询 log2（8=256s）')),
              const SizedBox(width: 10),
              Expanded(child: _smallField(_samplesCtrl, '每轮样本数')),
            ],
          ),
          const SizedBox(height: 10),
          _smallField(
            _holdoverCtrl,
            '断网保持漂移 ppm（默认 15；24h ≈ 1.3s）',
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _precision,
            onChanged: (v) => setState(() => _precision = v),
            title: const Text('TSC 高精度插值'),
            subtitle: const Text(
              'x86_64 下用 high_precision_clock 在单调时钟采样之间插值，提升 NTP 时间戳精度',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ),
          if (status?['sync']?['last_error'] != null)
            Text(
              '最近错误：${status!['sync']['last_error']}',
              style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
            ),
        ],
      ),
    );
  }

  Widget _precisionCard(Map<String, dynamic>? status) {
    final p = status?['precision'] as Map<String, dynamic>? ?? {};
    final k = status?['kalman'] as Map<String, dynamic>? ?? {};
    final t = status?['trend'] as Map<String, dynamic>? ?? {};
    final available = p['available'] == true;
    final ratio = (p['ratio'] as num? ?? 1.0).toDouble();
    final ppm = (ratio - 1.0) * 1e6;
    final temp = k['temp_c'];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('精度提升', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _kv('引擎', '${p['engine'] ?? 'zeitstempel'}'),
          _kv('TSC 可用', available ? (p['used'] == true ? '是' : '初始化中') : '否（非 x86_64 或 TSC 不稳定）'),
          _kv('TSC/单调时钟比例偏差', '${ppm.toStringAsFixed(3)} ppm'),
          _kv('拟合样本', '${p['samples'] ?? 0}'),
          _kv('拟合误差', '${p['error_ns'] ?? 0} ns'),
          _kv('重置次数', '${p['resets'] ?? 0}'),
          const Divider(height: 18),
          _kv(
            '温度 / 参考温度',
            temp == null
                ? '无传感器（可由 FFI 注入）'
                : '${(temp as num).toStringAsFixed(1)} °C / '
                      '${(k['temp_ref_c'] as num? ?? 25).toStringAsFixed(1)} °C',
          ),
          _kv(
            '日老化率',
            '${(k['aging_ppm_day'] as num? ?? 0).toStringAsFixed(4)} ppm/day '
                '（±${(k['aging_sd_ppm_day'] as num? ?? 0).toStringAsFixed(4)}）',
          ),
          _kv(
            '温度系数',
            '${(k['temp_coeff_ppm_per_c'] as num? ?? 0).toStringAsFixed(3)} ppm/°C '
                '（±${(k['temp_coeff_sd'] as num? ?? 0).toStringAsFixed(3)}）',
          ),
          _kv(
            'KF 频率不确定度',
            '±${(k['freq_sd_ppm'] as num? ?? 0).toStringAsFixed(4)} ppm',
          ),
          _kv(
            'KF 偏移不确定度',
            '±${(k['offset_sd_ms'] as num? ?? 0).toStringAsFixed(3)} ms',
          ),
          _kv(
            '长期学习',
            '${t['points'] ?? 0} 点 / 跨度 '
                '${((t['span_s'] as num? ?? 0) / 3600).toStringAsFixed(1)} h / 温差 '
                '${(t['temp_span_c'] as num? ?? 0).toStringAsFixed(1)} °C',
          ),
          _kv(
            '老化收敛',
            t['aging_ok'] == true ? '已收敛' : '学习中（需 ≥6h 且标准误 ≤5ppm/day）',
          ),
          _kv(
            '温度系数收敛',
            t['temp_ok'] == true ? '已收敛' : '学习中（需 ≥1°C 温差）',
          ),
          const SizedBox(height: 6),
          const Text(
            '证书有效期、逐请求签名等时间敏感操作使用同一时钟；'
            '即使操作系统时间被改错，只要 NTP 已同步，HTTPS 仍按真实时间校验。',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _aboutCard() {
    return _card(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('关于这套时间系统', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            '· 单调时钟：zeitstempel（跨线程一致、包含挂起时间）\n'
            '· NTP 客户端：rusty_time-core（NTPv4 编解码 + 回归滤波 + 纪律环）\n'
            '· 漂移补偿：回归斜率直接测频，临时 drain 有预算、不过冲\n'
            '· 精度提升：high_precision_clock 的 TSC 亚百纳秒插值\n'
            '· 多源选择：falseticker 区间投票，单一服务器故障不带偏时间\n'
            '· 保持模式：断网后按 15ppm 漂移预算给出不确定度\n'
            '· HTTPS：rustls TimeProvider 用本时钟裁决证书 notBefore/notAfter',
            style: TextStyle(fontSize: 12, height: 1.7, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _smallField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }

  Widget _metric(String label, String value) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              key,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _syncDescription(Map<String, dynamic>? sync) {
    if (sync == null) return '等待 Rust 时间服务返回状态…';
    final synced = sync['synced'] == true;
    final source = sync['source'] ?? 'system';
    final stratum = sync['stratum'] ?? 16;
    final age = (sync['last_sync_unix_ns'] as num? ?? 0) / 1e9;
    if (!synced) {
      return '尚未取得可信时间（来源 $source）；联网后会自动尝试 NTP。';
    }
    final ageText = age <= 0
        ? '刚刚'
        : '${(TimeService.instance.nowUnixMs() / 1000 - age).clamp(0, 1e9).toStringAsFixed(0)} 秒前';
    return '来源 $source · stratum $stratum · 上次同步 $ageText · 自动轮询已开启';
  }

  static String _syncLabel(Map<String, dynamic> status) {
    final clock = status['clock'] as Map<String, dynamic>?;
    final synced = clock?['synced'] == true;
    final uncertainty = (clock?['uncertainty_ns'] as num? ?? 0) / 1e6;
    return synced ? '已同步，不确定度 ±${uncertainty.toStringAsFixed(2)} ms' : '仍未同步';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _weekday(int weekday) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

  static String _duration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(0)} s';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(1)} min';
    return '${(seconds / 3600).toStringAsFixed(1)} h';
  }
}
