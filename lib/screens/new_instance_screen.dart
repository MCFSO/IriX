// 新建实例二级选择界面
// 提供「下载核心」与「导入核心文件」两个子选项，进入对应子流程。

import 'package:flutter/material.dart';

import '../utils/apple_widgets.dart';
import 'download_core_screen.dart';
import 'import_core_screen.dart';

/// 新建实例二级选择界面。
///
/// 展示两个子选项卡片：
/// - 「下载」：进入 [DownloadCoreScreen]，自动下载核心并新建服务器实例。
/// - 「导入」：进入 [ImportCoreScreen]，导入一个服务器核心新建服务器实例。
class NewInstanceScreen extends StatelessWidget {
  const NewInstanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建实例')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SubOptionCard(
                      icon: Icons.download,
                      title: '下载',
                      description: '自动下载核心并新建服务器实例',
                      onTap: () =>
                          pushPage(context, (_) => const DownloadCoreScreen()),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _SubOptionCard(
                      icon: Icons.file_download_done,
                      title: '导入',
                      description: '导入一个服务器核心新建服务器实例',
                      onTap: () =>
                          pushPage(context, (_) => const ImportCoreScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 二级选择用的小卡片组件。
class _SubOptionCard extends StatelessWidget {
  const _SubOptionCard({
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
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge),
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
