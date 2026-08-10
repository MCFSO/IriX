// 导入实例界面
// 用于导入一个已存在的服务器目录作为实例。提供根目录路径选择与启动命令编辑，
// 校验通过后调用 AppState.createImportedInstance 创建实例并返回上一屏。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// 导入实例界面。
///
/// 通过 [file_picker] 选择服务器根目录，填入启动命令后创建一个
/// 「导入目录」方式的实例。校验失败时以 SnackBar 提示。
class ImportInstanceScreen extends StatefulWidget {
  /// 创建 [ImportInstanceScreen]。
  const ImportInstanceScreen({super.key});

  @override
  State<ImportInstanceScreen> createState() => _ImportInstanceScreenState();
}

class _ImportInstanceScreenState extends State<ImportInstanceScreen> {
  /// 服务器根目录路径控制器。
  final TextEditingController _rootPathController = TextEditingController();

  /// 启动命令控制器，预填示例命令。
  final TextEditingController _startCommandController = TextEditingController(
    text: 'java -Xmx2G -jar server.jar nogui',
  );

  /// 是否正在处理创建（避免重复提交）。
  bool _creating = false;

  @override
  void dispose() {
    _rootPathController.dispose();
    _startCommandController.dispose();
    super.dispose();
  }

  /// 打开目录选择器，选择后将路径填入根目录输入框。
  /// 用户取消选择（返回 null）时不做任何改动。
  Future<void> _pickRootPath() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) return;
    _rootPathController.text = directoryPath;
  }

  /// 校验输入并创建实例。
  ///
  /// 两个字段均不能为空（去除首尾空白后），否则通过 SnackBar 提示。
  /// 创建成功后通过 [Navigator.pop] 返回上一屏，列表会因
  /// [AppState.notifyListeners] 自动刷新。
  Future<void> _onCreate() async {
    final rootPath = _rootPathController.text.trim();
    final startCommand = _startCommandController.text.trim();
    if (rootPath.isEmpty || startCommand.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写服务器根目录路径与启动命令')));
      return;
    }

    setState(() => _creating = true);
    try {
      await context.read<AppState>().createImportedInstance(
        rootPath: rootPath,
        startCommand: startCommand,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入实例')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 服务器根目录路径：输入框 + 浏览按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _rootPathController,
                    decoration: const InputDecoration(
                      labelText: '服务器根目录路径',
                      hintText: '选择或输入服务器根目录',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.tonalIcon(
                    onPressed: _pickRootPath,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('浏览'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 启动命令
            TextField(
              controller: _startCommandController,
              decoration: const InputDecoration(
                labelText: '启动命令',
                hintText: 'java -Xmx2G -jar server.jar nogui',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            // 创建实例按钮
            FilledButton.icon(
              onPressed: _creating ? null : _onCreate,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_for_offline),
              label: Text(_creating ? '创建中…' : '创建实例'),
            ),
            const SizedBox(height: 8),
            Text('导入一个已存在的服务器目录，使用其原有文件结构。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
