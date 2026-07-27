// Apple 风格 UI 组件
// 提供符合 Apple Designing Fluid Interfaces 原则的响应式控件
// 包括：即时反馈按钮、半透明材质、弹性卡片等
//
// 所有动画均受全局设置 animationsEnabled 控制 (见 AppState)；
// 关闭动画时，按下/悬停的过渡即时完成，无弹簧/淡入效果。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Apple 风格响应式按钮
///
/// 特点：
/// - 按下时即时缩放反馈（scale 0.97）
/// - 使用弹簧动画（damping 1.0）
/// - 符合 "Respond on pointer-down" 原则
class AppleButton extends StatefulWidget {
  const AppleButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;

  @override
  State<AppleButton> createState() => _AppleButtonState();
}

class _AppleButtonState extends State<AppleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    // 弹簧动画：damping 1.0（无弹跳），response 0.1s
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null && _animationsEnabled) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (_animationsEnabled) {
      _controller.reverse();
    }
    widget.onPressed?.call();
  }

  void _onTapCancel() {
    if (_animationsEnabled) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    _animationsEnabled =
        context.select<AppState, bool>((s) => s.animationsEnabled);
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.style != null
            ? FilledButton(
                onPressed: widget.onPressed,
                style: widget.style,
                child: widget.child,
              )
            : FilledButton(
                onPressed: widget.onPressed,
                child: widget.child,
              ),
      ),
    );
  }
}

/// Apple 风格卡片
///
/// 特点：
/// - 半透明背景（毛玻璃效果）
/// - 微妙的阴影层次感
/// - 悬停时轻微提升
class AppleCard extends StatefulWidget {
  const AppleCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  State<AppleCard> createState() => _AppleCardState();
}

class _AppleCardState extends State<AppleCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _elevationAnimation;
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _elevationAnimation = Tween<double>(begin: 2.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHover(bool hovering) {
    if (!_animationsEnabled) return;
    if (hovering) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    _animationsEnabled =
        context.select<AppState, bool>((s) => s.animationsEnabled);
    return AnimatedBuilder(
      animation: _elevationAnimation,
      builder: (context, _) {
        return MouseRegion(
          onEnter: (_) => _onHover(true),
          onExit: (_) => _onHover(false),
          child: Card(
            margin: widget.margin ?? const EdgeInsets.all(8),
            elevation: _elevationAnimation.value,
            // 半透明背景
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: widget.padding ?? const EdgeInsets.all(16),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Apple 风格开关（带动画）
///
/// 特点：
/// - 切换时颜色渐变过渡
/// - 符合 Apple 人机界面指南
class AppleSwitch extends StatelessWidget {
  const AppleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animationsEnabled =
        context.select<AppState, bool>((s) => s.animationsEnabled);
    return AnimatedContainer(
      duration: animationsEnabled
          ? const Duration(milliseconds: 200)
          : Duration.zero,
      curve: Curves.easeOut,
      child: Switch(
        value: value,
        onChanged: onChanged,
        // Apple 风格：开启时使用主色，关闭时使用灰色
        activeThumbColor: theme.colorScheme.primary,
        inactiveThumbColor: Colors.grey[400],
      ),
    );
  }
}

/// Apple 风格列表项
///
/// 特点：
/// - 点击时背景高亮
/// - 平滑过渡动画
/// - 适合设置页面使用
class AppleListTile extends StatelessWidget {
  const AppleListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Apple 风格进度指示器
///
/// 特点：
/// - 使用系统配色
/// - 平滑动画
class AppleProgressIndicator extends StatelessWidget {
  const AppleProgressIndicator({
    super.key,
    this.value,
  });

  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return value != null
        ? LinearProgressIndicator(
            value: value,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            borderRadius: BorderRadius.circular(4),
          )
        : LinearProgressIndicator(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            borderRadius: BorderRadius.circular(4),
          );
  }
}