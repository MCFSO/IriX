// Docker 设置可见性规则
// 决定"实例管理的 Docker 配置 / Docker 环境管理"是否显示：
//
// - 客户端为 Windows：仅当节点平台不是 Windows（Linux / macOS 等）时显示；
//   节点平台未知时按不显示处理
// - 客户端为 Linux / macOS 等其他平台：永久显示
//
// 与节点类型（MCSM 面板子节点 / 本地 Go 节点）无关，仅看客户端与节点平台。

import 'dart:io';

/// 判断是否显示 Docker 相关设置。
///
/// [nodePlatform] 来自节点概览的 system.platform（win32 / linux / darwin 等）。
/// [clientIsWindows] 仅用于测试注入，默认取当前运行平台。
bool shouldShowDockerSettings({
  required String? nodePlatform,
  bool? clientIsWindows,
}) {
  final clientWin = clientIsWindows ?? Platform.isWindows;
  if (!clientWin) return true;
  if (nodePlatform == null || nodePlatform.isEmpty) return false;
  final platform = nodePlatform.toLowerCase();
  return !(platform.startsWith('win') || platform == 'win32');
}
