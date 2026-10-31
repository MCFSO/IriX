// 应用可见性状态（最小化 / 隐藏）
//
// 用途：窗口最小化时，UI 既不可见也不该继续干活。这里提供全局标记：
//   - [AppActivityGate] 根据生命周期写值；
//   - 各定时器（日志尾随、进程存活、Docker 轮询等）在 tick 里读值，
//     最小化时直接跳过本次工作，恢复后下一拍自动继续。
//
// 用轮询而不是「注册/注销任务」：定时器回调本来就在跑，读一个 bool 的成本
// 可以忽略；注册式需要在每个任务里维护暂停状态，容易漏恢复。

import 'package:flutter/foundation.dart';

/// 应用活动状态（单例）。
class AppActivity extends ChangeNotifier {
  AppActivity._();

  static final AppActivity instance = AppActivity._();

  bool _minimized = false;

  /// 应用当前是否处于不可见状态（窗口最小化 / 被系统隐藏）。
  bool get isMinimized => _minimized;

  /// 供定时器回调直接读取的快捷方式。
  static bool get minimized => instance._minimized;

  /// 由 [AppActivityGate] 调用；值变化时通知监听者。
  void setMinimized(bool value) {
    if (_minimized == value) return;
    _minimized = value;
    notifyListeners();
  }
}
