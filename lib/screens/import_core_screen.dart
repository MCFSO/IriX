// 导入核心界面
// 用于导入一个已下载的核心 .jar 文件并创建新实例。
// 提供核心文件选择、根目录选择与启动命令编辑，
// 选择 jar 后自动用其文件名预填启动命令。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';

/// 导入核心界面。
///
/// 通过 [file_picker] 选择核心 .jar 文件与服务器根目录，启动命令会在
/// 选择 jar 后自动预填为 `java -Xmx2G -jar <jar文件名> nogui`。
/// 校验通过后调用 [AppState.createFromCoreFile] 创建实例并返回上一屏。
class ImportCoreScreen extends StatefulWidget {
  /// 创建 [ImportCoreScreen]。
  const ImportCoreScreen({super.key});

  @override
  State<ImportCoreScreen> createState() => _ImportCoreScreenState();
}

class _ImportCoreScreenState extends State<ImportCoreScreen> {
  /// 核心文件路径控制器。
  final TextEditingController _coreFilePathController = TextEditingController();

  /// 服务器根目录路径控制器。
  final TextEditingController _rootPathController = TextEditingController();

  /// 启动命令控制器。
  final TextEditingController _startCommandController = TextEditingController(
    text: 'java -Xmx2G -jar nogui',
  );

  /// 是否正在处理创建（避免重复提交）。
  bool _creating = false;

  @override
  void dispose() {
    _coreFilePathController.dispose();
    _rootPathController.dispose();
    _startCommandController.dispose();
    super.dispose();
  }

  /// 打开核心文件选择器（仅允许 .jar）。
  /// 选择后将文件路径填入输入框，并用文件名刷新启动命令预填。
  /// 用户取消选择时不做改动。
  Future<void> _pickCoreFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jar'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    _coreFilePathController.text = path;
    // 用所选 jar 的文件名预填启动命令。
    final basename = p.basename(path);
    _startCommandController.text = 'java -Xmx2G -jar $basename nogui';
  }

  /// 打开目录选择器，选择后将路径填入根目录输入框。
  /// 用户取消选择时不做改动。
  Future<void> _pickRootPath() async {
    final directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath == null) return;
    _rootPathController.text = directoryPath;
  }

  /// 校验输入并创建实例。
  ///
  /// 三个字段均不能为空（去除首尾空白后），否则通过 SnackBar 提示。
  /// 创建成功后通过 [Navigator.pop] 返回上一屏。
  Future<void> _onCreate() async {
    final l = AppLocalizations.of(context);
    final coreFilePath = _coreFilePathController.text.trim();
    final rootPath = _rootPathController.text.trim();
    final startCommand = _startCommandController.text.trim();
    if (coreFilePath.isEmpty || rootPath.isEmpty || startCommand.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.importCore_fillAllFields)));
      return;
    }

    setState(() => _creating = true);
    try {
      await context.read<AppState>().createFromCoreFile(
        coreFilePath: coreFilePath,
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.importCore_title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 核心文件：输入框 + 浏览按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _coreFilePathController,
                    decoration: InputDecoration(
                      labelText: l.importCore_coreFile,
                      hintText: l.importCore_coreFileHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.tonalIcon(
                    onPressed: _pickCoreFile,
                    icon: const Icon(Icons.file_open),
                    label: Text(l.importCore_browse),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 服务器根目录路径：输入框 + 浏览按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _rootPathController,
                    decoration: InputDecoration(
                      labelText: l.importCore_rootPath,
                      hintText: l.importCore_rootPathHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.tonalIcon(
                    onPressed: _pickRootPath,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l.importCore_browse),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 启动命令（选择 jar 后自动预填文件名）
            TextField(
              controller: _startCommandController,
              decoration: InputDecoration(
                labelText: l.instanceDetail_startCommand,
                hintText: l.importCore_startCommandHint,
                border: const OutlineInputBorder(),
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
                  : const Icon(Icons.add_box),
              label: Text(_creating ? l.importCore_creating : l.importCore_createInstance),
            ),
            const SizedBox(height: 8),
            Text(
              l.importCore_desc,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
