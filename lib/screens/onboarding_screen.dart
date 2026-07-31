// 首次运行 / 创建入口界面
// 居中展示两张大卡片：「新建」与「导入」，分别进入对应子流程。
// 子流程创建实例并返回后，本界面自动 pop 回上层 HomeScreen 以触发刷新。

import 'package:flutter/material.dart';

import '../utils/apple_widgets.dart';
import 'import_instance_screen.dart';
import 'new_instance_screen.dart';

/// 应用首次运行 / 创建入口界面。
///
/// 居中展示两张大卡片：
/// - 「新建」：进入 [NewInstanceScreen]
/// - 「导入」：进入 [ImportInstanceScreen]
///
/// 从子界面返回后自动 pop 回上层，使主界面刷新实例列表。
///
/// 当 [embedded] 为 true 时，仅渲染卡片内容（不含 Scaffold/AppBar），
/// 用于嵌入到 [HomeScreen] 的空列表状态中作为引导界面。
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, this.embedded = false});

  /// 是否以嵌入模式渲染（不含 Scaffold/AppBar）。
  final bool embedded;

  /// 推入子界面，待其返回后再 pop 本界面，使底层 HomeScreen 刷新。
  Future<void> _pushAndReturn(BuildContext context, WidgetBuilder builder) async {
    await pushPage(context, builder);
    if (!context.mounted) return;
    // 子流程结束（已创建/导入实例或取消）后返回上层，触发 HomeScreen 刷新。
    // 嵌入模式下不 pop（因为本就是 HomeScreen 的一部分）。
    if (!embedded) {
      Navigator.pop(context);
    }
  }

  /// 构建两张选项卡片的主体内容。
  Widget _buildBody(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _OptionCard(
                    icon: Icons.add_box,
                    title: '新建',
                    description: '新建一个MC服务器实例',
                    onTap: () => _pushAndReturn(
                      context,
                      (_) => const NewInstanceScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _OptionCard(
                    icon: Icons.folder,
                    title: '导入',
                    description: '导入一个MC服务器实例',
                    onTap: () => _pushAndReturn(
                      context,
                      (_) => const ImportInstanceScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 嵌入模式：仅返回主体内容，由外层 HomeScreen 的 Scaffold 提供 AppBar。
    if (embedded) {
      return _buildBody(context);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('IriX'),
        centerTitle: true,
      ),
      body: _buildBody(context),
    );
  }
}

/// 引导界面用的大卡片选项组件。
///
/// 展示图标、标题与描述，点击时触发 [onTap] 回调。
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}