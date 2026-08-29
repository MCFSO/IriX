// 首次启动线性引导向导（全屏遮罩）
//
// 结构：其余界面变暗 30% 且不可点击（AbsorbPointer），中央卡片按线性步骤引导：
//   1~4. 安装 JDK 8 / 17 / 21 / 25（已安装自动跳过，下载进度实时展示）
//   5.   创建第一个实例（复用 NewInstanceScreen）
// 创建完成后检测 NAT 类型，询问是否需要 FRP 内网穿透，需要则通知外层跳转 FRP 页。
// 左上角「跳过」按钮（50% 不透明度）随时退出；跳过/完成由外层持久化。

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/jdk_installer.dart';
import '../services/nat_detector.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';
import '../screens/new_instance_screen.dart';

/// 引导向导覆盖层。
class FirstRunWizardOverlay extends StatefulWidget {
  const FirstRunWizardOverlay({
    super.key,
    required this.onSkip,
    required this.onFinish,
  });

  /// 点击「跳过」。
  final VoidCallback onSkip;

  /// 向导结束；[goFrp] 为 true 时外层应跳转到 FRP 页面。
  final void Function(bool goFrp) onFinish;

  @override
  State<FirstRunWizardOverlay> createState() => _FirstRunWizardOverlayState();
}

/// JDK 步骤状态。
enum _JdkStatus { pending, installing, installed, failed }

class _FirstRunWizardOverlayState extends State<FirstRunWizardOverlay> {
  static const _jdkSteps = [
    (version: '8', title: 'JDK 8'),
    (version: '17', title: 'JDK 17'),
    (version: '21', title: 'JDK 21'),
    (version: '25', title: 'JDK 25'),
  ];

  int _step = 0;

  /// 各 JDK 步骤状态。
  final Map<String, _JdkStatus> _statuses = {};

  /// 下载进度（0~1）。
  final Map<String, double> _progress = {};

  /// 安装错误信息。
  final Map<String, String?> _errors = {};

  /// 当前阶段：wizard → natDetecting → natResult。
  String _phase = 'wizard';

  /// NAT 检测结果。
  NatDetectionResult? _natResult;

  @override
  void initState() {
    super.initState();
    _initJdkStatuses();
  }

  Future<void> _initJdkStatuses() async {
    for (final step in _jdkSteps) {
      _statuses[step.version] = _JdkStatus.pending;
      final installed = await JdkInstaller.instance.isInstalled(step.version);
      if (!mounted) return;
      setState(() {
        _statuses[step.version] = installed
            ? _JdkStatus.installed
            : _JdkStatus.pending;
      });
    }
    if (!mounted) return;
    // 全部 JDK 已装 → 直接进入创建实例步骤
    if (_jdkSteps.every((s) => _statuses[s.version] == _JdkStatus.installed)) {
      setState(() => _step = _jdkSteps.length);
    }
  }

  /// 安装指定 JDK。
  Future<void> _installJdk(String version) async {
    setState(() {
      _statuses[version] = _JdkStatus.installing;
      _progress[version] = 0;
      _errors[version] = null;
    });
    try {
      await JdkInstaller.instance.install(
        version,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress[version] = progress);
        },
      );
      if (!mounted) return;
      setState(() => _statuses[version] = _JdkStatus.installed);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _step = _step + 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statuses[version] = _JdkStatus.failed;
        _errors[version] = e.toString();
      });
    }
  }

  /// 创建实例步骤：进入新建实例流程，返回后检查是否已创建。
  Future<void> _createInstance() async {
    await pushPage(context, (_) => const NewInstanceScreen());
    if (!mounted) return;
    final created = context.read<AppState>().instances.isNotEmpty;
    if (!created) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.wizard_noInstanceCreated)));
      return;
    }
    await _startNatDetection();
  }

  /// NAT 检测。
  Future<void> _startNatDetection() async {
    setState(() => _phase = 'natDetecting');
    NatDetectionResult result;
    try {
      result = await Isolate.run(() => NatDetector().detect());
    } catch (_) {
      result = const NatDetectionResult(
        type: NatType.blocked,
        mappedAddress: null,
      );
    }
    if (!mounted) return;
    setState(() {
      _natResult = result;
      _phase = 'natResult';
    });
  }

  // ======================== UI ========================

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        // 变暗 30% + 阻断点击
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: true,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
          ),
        ),
        // 中央向导卡片
        Center(child: _buildCard(context)),
        // 左上角「跳过」（50% 不透明度；置于卡片之上，任何窗口尺寸都可点击）
        Positioned(
          left: 16,
          top: 12,
          child: Opacity(
            opacity: 0.5,
            child: TextButton.icon(
              onPressed: widget.onSkip,
              icon: const Icon(Icons.skip_next, size: 18),
              label: Text(l.common_skip),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // 小窗口适配：按可用空间限制卡片尺寸，内容可滚动，避免纵向溢出
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight =
            (constraints.maxHeight - 64).clamp(0.0, double.infinity);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 860,
              maxHeight: maxHeight > 0 ? maxHeight : double.infinity,
            ),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: switch (_phase) {
                  'natDetecting' => _Centered(
                    icon: Icons.network_check,
                    title: l.wizard_detectingNat,
                    child: Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  'natResult' => _buildNatResult(theme),
                  _ => _buildWizard(theme),
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 引导主界面：左侧步骤列表 + 右侧步骤内容。
  Widget _buildWizard(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧线性步骤列表
        SizedBox(
          width: 230,
          // 小窗口时可滚动，避免纵向溢出
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.wizard_title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  l.wizard_totalSteps(_jdkSteps.length + 1),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _jdkSteps.length + 1; i++)
                  _StepRow(
                    index: i,
                    title: i < _jdkSteps.length
                        ? l.wizard_installJdk(_jdkSteps[i].title)
                        : l.wizard_createFirstInstance,
                    state: i < _jdkSteps.length
                        ? switch (_statuses[_jdkSteps[i].version]) {
                            _JdkStatus.installed => _StepState.done,
                            _JdkStatus.installing => _StepState.active,
                            _JdkStatus.failed => _StepState.failed,
                            _JdkStatus.pending => _StepState.pending,
                            null => _StepState.pending,
                          }
                        : (_step > _jdkSteps.length
                              ? _StepState.done
                              : _step == _jdkSteps.length
                                  ? _StepState.active
                                  : _StepState.pending),
                  ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 32),
        // 右侧步骤内容
        // 步骤内容可纵向滚动，小窗口/长错误信息时不溢出
        Expanded(
          child: SingleChildScrollView(child: _buildStepContent(theme)),
        ),
      ],
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    if (_step < _jdkSteps.length) {
      return _buildJdkStep(theme, _jdkSteps[_step]);
    }
    return _buildInstanceStep(theme);
  }

  /// JDK 步骤内容。
  Widget _buildJdkStep(
    ThemeData theme,
    ({String version, String title}) step,
  ) {
    final l = AppLocalizations.of(context);
    final status = _statuses[step.version] ?? _JdkStatus.pending;
    final progress = _progress[step.version] ?? 0.0;
    final error = _errors[step.version];
    final note = switch (step.version) {
      '8' => l.wizard_jdk8Note,
      '17' => l.wizard_jdk17Note,
      '21' => l.wizard_jdk21Note,
      '25' => l.wizard_jdk25Note,
      _ => '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.wizard_stepInstallJdk(_step + 1, step.title),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          note,
          style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        switch (status) {
          _JdkStatus.pending => FilledButton.icon(
            onPressed: () => _installJdk(step.version),
            icon: const Icon(Icons.download),
            label: Text(l.wizard_startInstall(step.title)),
          ),
          _JdkStatus.installing => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.wizard_downloading(
                  step.title,
                  (progress * 100).toStringAsFixed(0),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress > 0 ? progress : null),
              const SizedBox(height: 8),
              Text(
                l.wizard_adoptiumSource,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          _JdkStatus.installed => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    l.wizard_jdkInstalled(step.title),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => setState(() => _step = _step + 1),
                child: Text(l.addNode_nextStep),
              ),
            ],
          ),
          _JdkStatus.failed => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.wizard_installFailed(error ?? l.wizard_unknownError),
                style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _installJdk(step.version),
                    icon: const Icon(Icons.refresh),
                    label: Text(l.common_retry),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _step = _step + 1),
                    child: Text(l.wizard_skipThisStep),
                  ),
                ],
              ),
            ],
          ),
        },
        const SizedBox(height: 12),
        Text(
          l.wizard_skipHint,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    );
  }

  /// 创建实例步骤内容。
  Widget _buildInstanceStep(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.wizard_stepCreateInstance, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l.wizard_createInstanceDesc,
          style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _createInstance,
          icon: const Icon(Icons.add_box),
          label: Text(l.wizard_createFirstInstance),
        ),
      ],
    );
  }

  /// NAT 检测结果 + FRP 询问。
  Widget _buildNatResult(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final result = _natResult!;
    final color = result.type == NatType.openInternet
        ? Colors.green
        : Colors.orange;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.wizard_done, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.network_check, color: color),
            const SizedBox(width: 8),
            Text(
              '${l.wizard_natType(result.type.label)}'
              '${result.mappedAddress != null ? l.wizard_natMapped(result.mappedAddress!) : ''}'
              '${result.uncertain ? l.wizard_natUncertain : ''}',
              style: TextStyle(fontSize: 14, color: color),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          result.needsFrp
              ? l.wizard_frpNeeded
              : l.wizard_frpNotNeeded,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            if (result.needsFrp)
              FilledButton.icon(
                onPressed: () => widget.onFinish(true),
                icon: const Icon(Icons.swap_horiz),
                label: Text(l.wizard_configureFrp),
              ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => widget.onFinish(false),
              child: Text(l.wizard_notNow),
            ),
          ],
        ),
      ],
    );
  }
}

/// 左侧步骤行。
enum _StepState { pending, active, done, failed }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.title,
    required this.state,
  });

  final int index;
  final String title;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final (color, icon) = switch (state) {
      _StepState.done => (Colors.green, Icons.check_circle),
      _StepState.active => (
        theme.colorScheme.primary,
        Icons.radio_button_checked,
      ),
      _StepState.failed => (theme.colorScheme.error, Icons.error),
      _StepState.pending => (Colors.grey, Icons.radio_button_unchecked),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.wizard_stepNumber(index + 1, title),
              style: TextStyle(
                fontSize: 13,
                color: state == _StepState.pending ? Colors.grey : null,
                fontWeight: state == _StepState.active
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 居中提示组件（NAT 检测中）。
class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, this.child});

  final IconData icon;
  final String title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.titleMedium),
        ?child,
      ],
    );
  }
}
