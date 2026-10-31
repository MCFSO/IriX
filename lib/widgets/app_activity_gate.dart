// 最小化时暂停 UI 的门闸
//
// 挂在 MaterialApp.builder 上（包裹 Navigator），窗口最小化时：
//   - Offstage：停止绘制、命中测试与语义树，不再占用 GPU；
//   - TickerMode(false)：停掉所有 AnimationController，避免继续按帧调度；
//   - AppActivity.minimized = true：各定时器（日志尾随、存活轮询、
//     Docker 状态同步等）据此跳过本次 tick。
//
// 注意：子树一直留在树上（不销毁），因此导航栈、滚动位置、输入内容都不会丢；
// 窗口恢复时下一帧即可原样补回，不需要重新加载页面。
//
// 检测方式：Flutter 在桌面端最小化窗口时上报 AppLifecycleState.hidden
// （移动端/后台为 paused），恢复时回到 resumed。

import 'package:flutter/material.dart';

import '../state/app_activity.dart';

/// 包裹应用根节点，最小化时暂停渲染与动画。
class AppActivityGate extends StatefulWidget {
  const AppActivityGate({super.key, required this.child});

  /// 应用内容（通常是 MaterialApp 的 Navigator）。
  final Widget child;

  /// 该生命周期状态是否意味着「不可见」。
  static bool isHiddenState(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden || state == AppLifecycleState.paused;

  @override
  State<AppActivityGate> createState() => _AppActivityGateState();
}

class _AppActivityGateState extends State<AppActivityGate>
    with WidgetsBindingObserver {
  late bool _minimized;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _minimized = AppActivityGate.isHiddenState(
      WidgetsBinding.instance.lifecycleState,
    );
    AppActivity.instance.setMinimized(_minimized);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppActivity.instance.setMinimized(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final minimized = AppActivityGate.isHiddenState(state);
    // 无论 widget 是否需要重建，都要先更新全局标记，让定时器立刻停下。
    AppActivity.instance.setMinimized(minimized);
    if (minimized == _minimized) return;
    setState(() => _minimized = minimized);
  }

  @override
  Widget build(BuildContext context) {
    // 结构固定为 TickerMode > Offstage > child，只切换参数：
    // 若在这里换成不同 Widget，会导致整棵子树重新创建、导航栈丢失。
    return TickerMode(
      enabled: !_minimized,
      child: Offstage(
        // 固定 key：便于测试与调试定位（树里还有其它 Offstage）。
        key: const ValueKey('app-activity-offstage'),
        offstage: _minimized,
        child: widget.child,
      ),
    );
  }
}
