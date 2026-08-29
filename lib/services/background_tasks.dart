// 后台文件任务管理系统
// ChangeNotifier 管理复制/移动/删除文件任务的队列，支持进度回调和取消操作。
// 小文件 (<1MB) 不展示进度条直接完成，大文件通过 Stream 读取实现进度追踪。
// UI 层通过 FileProgressDialog (模态) 和 FileProgressOverlay (内嵌) 展示任务状态。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'locale_settings.dart';

const _oneMegabyte = 1024 * 1024;

int _nextId = 0;
final _random = Random();

String _generateId() {
  _nextId++;
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = _random.nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
  return '${ts}_${rnd}_$_nextId';
}

enum TaskType { copy, move, delete }

enum TaskStatus { running, completed, failed, cancelled }

class FileTask {
  final String id;
  final TaskType type;
  final String sourcePath;
  final String destPath;
  final int totalBytes;
  int completedBytes;
  TaskStatus status;
  String? error;
  final DateTime createdAt;
  bool cancelled;

  FileTask({
    required this.id,
    required this.type,
    required this.sourcePath,
    this.destPath = '',
    this.totalBytes = 0,
    this.completedBytes = 0,
    this.status = TaskStatus.running,
    this.error,
    DateTime? createdAt,
    this.cancelled = false,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress => totalBytes > 0 ? completedBytes / totalBytes : 0.0;

  String get fileName => path.basename(sourcePath);
}

class BackgroundTaskManager extends ChangeNotifier {
  final List<FileTask> _tasks = [];

  List<FileTask> get tasks => List.unmodifiable(_tasks);
  List<FileTask> get runningTasks =>
      _tasks.where((t) => t.status == TaskStatus.running).toList();
  List<FileTask> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  bool get hasRunningTasks => _tasks.any((t) => t.status == TaskStatus.running);

  Future<FileTask> addCopyTask(String source, String dest, int totalBytes) {
    final task = FileTask(
      id: _generateId(),
      type: TaskType.copy,
      sourcePath: source,
      destPath: dest,
      totalBytes: totalBytes,
    );
    _tasks.insert(0, task);
    notifyListeners();
    _executeTask(task);
    return Future.value(task);
  }

  Future<FileTask> addMoveTask(String source, String dest, int totalBytes) {
    final task = FileTask(
      id: _generateId(),
      type: TaskType.move,
      sourcePath: source,
      destPath: dest,
      totalBytes: totalBytes,
    );
    _tasks.insert(0, task);
    notifyListeners();
    _executeTask(task);
    return Future.value(task);
  }

  Future<FileTask> addDeleteTask(String path, int totalBytes) {
    final task = FileTask(
      id: _generateId(),
      type: TaskType.delete,
      sourcePath: path,
      totalBytes: totalBytes,
    );
    _tasks.insert(0, task);
    notifyListeners();
    _executeTask(task);
    return Future.value(task);
  }

  void cancelTask(String id) {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    _tasks[idx].cancelled = true;
    notifyListeners();
  }

  void dismissCompleted() {
    _tasks.removeWhere(
      (t) =>
          t.status == TaskStatus.completed || t.status == TaskStatus.cancelled,
    );
    notifyListeners();
  }

  void updateProgress(String taskId, int bytesCompleted) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    _tasks[idx].completedBytes = bytesCompleted;
    notifyListeners();
  }

  void markComplete(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    _tasks[idx].status = TaskStatus.completed;
    _tasks[idx].completedBytes = _tasks[idx].totalBytes;
    notifyListeners();
  }

  void markFailed(String taskId, String error) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    _tasks[idx].status = TaskStatus.failed;
    _tasks[idx].error = error;
    notifyListeners();
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  Future<void> _executeTask(FileTask task) async {
    try {
      final srcFile = File(task.sourcePath);

      if (task.totalBytes > 0 && task.totalBytes < _oneMegabyte) {
        await _executeSmall(task, srcFile);
        return;
      }

      switch (task.type) {
        case TaskType.copy:
          await _streamCopy(task, srcFile);
        case TaskType.move:
          await _streamMove(task, srcFile);
        case TaskType.delete:
          await _executeDelete(task, srcFile);
      }
    } catch (e) {
      if (!task.cancelled) {
        markFailed(task.id, e.toString());
      }
    }
  }

  Future<void> _executeSmall(FileTask task, File file) async {
    if (task.cancelled) {
      _tasks[_tasks.indexWhere((t) => t.id == task.id)].status =
          TaskStatus.cancelled;
      notifyListeners();
      return;
    }
    String? err;
    try {
      switch (task.type) {
        case TaskType.copy:
          await file.copy(task.destPath);
        case TaskType.move:
          await file.rename(task.destPath);
        case TaskType.delete:
          await file.delete();
      }
    } catch (e) {
      err = e.toString();
    }
    if (task.cancelled) {
      _tasks[_tasks.indexWhere((t) => t.id == task.id)].status =
          TaskStatus.cancelled;
      notifyListeners();
      return;
    }
    if (err != null) {
      markFailed(task.id, err);
    } else {
      markComplete(task.id);
    }
  }

  Future<void> _streamCopy(FileTask task, File srcFile) async {
    final destDir = path.dirname(task.destPath);
    final dir = Directory(destDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final destFile = File(task.destPath);
    final input = srcFile.openRead();
    final output = destFile.openWrite();

    int bytesWritten = 0;
    StreamSubscription<List<int>>? sub;

    try {
      final completer = Completer<void>();
      sub = input.listen(
        (chunk) {
          if (task.cancelled) {
            sub?.cancel();
            output.close();
            completer.complete();
            return;
          }
          output.add(chunk);
          bytesWritten += chunk.length;
          updateProgress(task.id, bytesWritten);
        },
        onDone: () async {
          await output.flush();
          await output.close();
          completer.complete();
        },
        onError: (e) {
          output.close();
          completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;

      if (task.cancelled) {
        _tasks[_tasks.indexWhere((t) => t.id == task.id)].status =
            TaskStatus.cancelled;
        notifyListeners();
        try {
          await destFile.delete();
        } catch (_) {}
        return;
      }
      markComplete(task.id);
    } catch (e) {
      await output.close();
      if (!task.cancelled) {
        markFailed(task.id, e.toString());
      }
      try {
        await destFile.delete();
      } catch (_) {}
    } finally {
      await sub?.cancel();
    }
  }

  Future<void> _streamMove(FileTask task, File srcFile) async {
    try {
      if (task.cancelled) {
        _tasks[_tasks.indexWhere((t) => t.id == task.id)].status =
            TaskStatus.cancelled;
        notifyListeners();
        return;
      }
      await srcFile.rename(task.destPath);
      markComplete(task.id);
    } on FileSystemException {
      await _streamCopy(task, srcFile);
      if (!task.cancelled && task.status == TaskStatus.completed) {
        try {
          await srcFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _executeDelete(FileTask task, File file) async {
    if (task.cancelled) {
      _tasks[_tasks.indexWhere((t) => t.id == task.id)].status =
          TaskStatus.cancelled;
      notifyListeners();
      return;
    }
    try {
      await file.delete();
      if (task.cancelled) {
        _tasks[_tasks.indexWhere((t) => t.id == task.id)].status =
            TaskStatus.cancelled;
        notifyListeners();
        return;
      }
      markComplete(task.id);
    } catch (e) {
      if (file.existsSync()) {
        markFailed(task.id, '删除失败: $e');
      } else {
        markComplete(task.id);
      }
    }
  }
}

IconData _taskTypeIcon(TaskType type) {
  switch (type) {
    case TaskType.copy:
      return Icons.copy;
    case TaskType.move:
      return Icons.drive_file_move;
    case TaskType.delete:
      return Icons.delete_outline;
  }
}

class FileProgressDialog extends StatelessWidget {
  final List<FileTask> tasks;
  final BackgroundTaskManager manager;

  const FileProgressDialog({
    super.key,
    required this.tasks,
    required this.manager,
  });

  static Future<void> show(
    BuildContext context,
    BackgroundTaskManager manager,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FileProgressDialogBody(manager: manager),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _FileProgressDialogBody(manager: manager);
  }
}

class _FileProgressDialogBody extends StatelessWidget {
  final BackgroundTaskManager manager;

  const _FileProgressDialogBody({required this.manager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final running = manager.runningTasks;
        final others = manager.tasks
            .where((t) => t.status != TaskStatus.running)
            .toList();

        return AlertDialog(
          title: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                LocaleSettings.instance.localeCode == 'en'
                    ? 'File operations (${running.length})'
                    : '文件操作 (${running.length})',
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.minimize, size: 20),
                tooltip: LocaleSettings.instance.localeCode == 'en'
                    ? 'Minimize'
                    : '最小化',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (running.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      LocaleSettings.instance.localeCode == 'en'
                          ? 'No running tasks'
                          : '暂无运行中的任务',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ...running.map((t) => _TaskTile(task: t, manager: manager)),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  ...others
                      .take(10)
                      .map((t) => _TaskTile(task: t, manager: manager)),
                  if (others.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        LocaleSettings.instance.localeCode == 'en'
                            ? '... ${others.length - 10} more completed tasks'
                            : '... 还有 ${others.length - 10} 个已完成任务',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: running.isEmpty
                  ? () {
                      manager.dismissCompleted();
                      Navigator.of(context).pop();
                    }
                  : null,
              child: Text(
                LocaleSettings.instance.localeCode == 'en'
                    ? 'Clear completed'
                    : '清除已完成',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                LocaleSettings.instance.localeCode == 'en' ? 'Close' : '关闭',
              ),
            ),
          ],
        );
      },
    );
  }
}

class FileProgressOverlay extends StatelessWidget {
  final BackgroundTaskManager manager;

  const FileProgressOverlay({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final running = manager.runningTasks;
        if (running.isEmpty) {
          final lastDone = manager.tasks
              .where(
                (t) =>
                    t.status == TaskStatus.completed ||
                    t.status == TaskStatus.failed,
              )
              .toList();
          if (lastDone.isEmpty) return const SizedBox.shrink();

          return Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.green[600],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    LocaleSettings.instance.localeCode == 'en'
                        ? 'Last finished: ${path.basename(lastDone.first.sourcePath)}'
                        : '最后完成: ${path.basename(lastDone.first.sourcePath)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => manager.dismissCompleted(),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      LocaleSettings.instance.localeCode == 'en'
                          ? '${running.length} task(s) running'
                          : '${running.length} 个任务运行中',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => FileProgressDialog.show(context, manager),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          LocaleSettings.instance.localeCode == 'en'
                              ? 'Details'
                              : '详情',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...running
                    .take(3)
                    .map((t) => _CompactTaskTile(task: t, manager: manager)),
                if (running.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      LocaleSettings.instance.localeCode == 'en'
                          ? '... ${running.length - 3} more task(s)'
                          : '... 还有 ${running.length - 3} 个任务',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool _shouldShowProgress(FileTask task) =>
    task.totalBytes > 0 && task.totalBytes >= _oneMegabyte;

class _TaskTile extends StatelessWidget {
  final FileTask task;
  final BackgroundTaskManager manager;

  const _TaskTile({required this.task, required this.manager});

  @override
  Widget build(BuildContext context) {
    final isRunning = task.status == TaskStatus.running;
    final hasProgress = _shouldShowProgress(task);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(_taskTypeIcon(task.type), size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusChip(task),
                  ],
                ),
                if (hasProgress && isRunning) ...[
                  const SizedBox(height: 3),
                  LinearProgressIndicator(value: task.progress),
                  const SizedBox(height: 1),
                  Text(
                    '${(task.progress * 100).toStringAsFixed(1)}%  '
                    '${_formatBytes(task.completedBytes)} / ${_formatBytes(task.totalBytes)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
                if (task.error != null)
                  Text(
                    task.error!,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isRunning)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: LocaleSettings.instance.localeCode == 'en'
                  ? 'Cancel'
                  : '取消',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => manager.cancelTask(task.id),
            )
          else
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: LocaleSettings.instance.localeCode == 'en'
                  ? 'Remove'
                  : '移除',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => manager.removeTask(task.id),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(FileTask task) {
    final en = LocaleSettings.instance.localeCode == 'en';
    Color color;
    String label;
    switch (task.status) {
      case TaskStatus.running:
        color = Colors.blue;
        label = en ? 'Running' : '进行中';
      case TaskStatus.completed:
        color = Colors.green;
        label = en ? 'Done' : '完成';
      case TaskStatus.failed:
        color = Colors.red;
        label = en ? 'Failed' : '失败';
      case TaskStatus.cancelled:
        color = Colors.orange;
        label = en ? 'Cancelled' : '已取消';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

class _CompactTaskTile extends StatelessWidget {
  final FileTask task;
  final BackgroundTaskManager manager;

  const _CompactTaskTile({required this.task, required this.manager});

  @override
  Widget build(BuildContext context) {
    final hasProgress = _shouldShowProgress(task);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(_taskTypeIcon(task.type), size: 14, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              task.fileName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (hasProgress) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 4,
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          InkWell(
            onTap: () => manager.cancelTask(task.id),
            child: const Icon(Icons.close, size: 14),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < _oneMegabyte) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < _oneMegabyte * 1024) {
    return '${(bytes / _oneMegabyte).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (_oneMegabyte * 1024)).toStringAsFixed(1)} GB';
}
