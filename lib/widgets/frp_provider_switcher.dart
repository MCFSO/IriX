// FRP 提供商切换下拉栏（内嵌在 AppBar 标题右侧的圆角胶囊）。
//
// 实现要点（修「鼠标悬浮时高亮铺不满」）：
// 1. 背景色必须由 Material 承载——InkWell 的悬浮高亮/水波纹画在最近一层
//    Material 的墨迹层上，若用 Container/DecoratedBox 自己的背景色，高亮会被
//    背景盖在下面（或只能透过半透明背景看到，明显偏暗）；
// 2. 左右内边距必须交给 DropdownButton 自己的 `padding`，因为 InkWell 包在
//    padding 外层（见 SDK dropdown.dart），这样点击/高亮区域才正好等于整块
//    圆角胶囊；若在外层套 Padding，高亮区域会比胶囊窄一圈，左右各留出未点亮的
//    缝隙；
// 3. 圆角半径同时交给 Material（裁剪）与 DropdownButton（InkWell 高亮形状），
//    避免高亮方角溢出圆角背景。

import 'package:flutter/material.dart';

import '../services/frp_provider.dart';

/// FRP 提供商切换胶囊。
class FrpProviderSwitcher extends StatelessWidget {
  const FrpProviderSwitcher({
    super.key,
    required this.providerId,
    required this.onChanged,
  });

  /// 当前选中的提供商 id（[FrpProviderKind.id]）。
  final String providerId;

  /// 切换提供商回调，参数为新的提供商 id。
  final ValueChanged<String> onChanged;

  /// 胶囊圆角半径：背景、裁剪与高亮形状保持一致。
  static const double radius = 8;

  /// 左右内边距（作为 DropdownButton 自身的 padding，计入高亮区域）。
  static const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: providerId,
          isDense: true,
          padding: padding,
          borderRadius: BorderRadius.circular(radius),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          items: [
            for (final kind in FrpProviderKind.values)
              DropdownMenuItem(value: kind.id, child: Text(kind.label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
