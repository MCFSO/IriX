// 集群迁移与增量同步服务
// 负责多机模式下实例在节点间的数据搬运：
// - syncToMirror：把实例工作目录增量同步到协调器本地镜像（按 size/mtime 判定变化文件）
// - restoreFromMirror：把本地镜像下发到目标节点的新实例
// - migrate：停止源实例 → 同步镜像 → 目标节点重建 → 下发 → 启动
// 网络传输复用 NodeApiClient 的文件接口（listFiles / downloadTicket / uploadTicket / mkdir）。

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cluster_instance.dart';
import '../models/node.dart';
import '../models/remote.dart';
import '../services/database_manager.dart';
import '../services/node_api_client.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';

/// 集群迁移 / 同步服务。
class ClusterMigrator {
  ClusterMigrator({required this.nodeState, required this.clusterState});

  final NodeState nodeState;
  final ClusterState clusterState;

  /// 迁移阈值：等待实例停止的超时。
  static const Duration stopTimeout = Duration(seconds: 60);

  NodeInfo? _nodeById(String id) {
    for (final node in nodeState.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// 本地镜像根目录（协调器应用文档目录下的 `cluster_mirrors/<instanceId>`）。
  Future<Directory> _mirrorDir(String instanceId) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'cluster_mirrors', instanceId));
  }

  /// 解析节点的守护进程 id（优先可用守护进程，否则首个）。
  Future<String> resolveDaemonId(NodeInfo node) async {
    final overview = await nodeState.clientFor(node).overview();
    if (overview.remote.isNotEmpty) {
      final available = overview.remote.where((d) => d.available).toList();
      return (available.isNotEmpty ? available : overview.remote).first.uuid;
    }
    return '';
  }

  /// 递归枚举远程目录，返回扁平文件列表（相对路径 → 条目）。
  ///
  /// 仅文件参与同步；目录通过递归进入，不单独下载。
  Future<List<({String relPath, RemoteFileEntry entry})>> _walkRemote(
    NodeApiClient client,
    String daemonId,
    String uuid,
    String dir,
  ) async {
    final result = <({String relPath, RemoteFileEntry entry})>[];
    final data = await client.listFiles(
      daemonId: daemonId,
      uuid: uuid,
      target: dir,
    );
    for (final entry in data.items) {
      final childPath = dir == '/' ? '/${entry.name}' : '$dir/${entry.name}';
      if (entry.isDirectory) {
        final sub = await _walkRemote(client, daemonId, uuid, childPath);
        result.addAll(sub);
      } else {
        result.add((relPath: childPath, entry: entry));
      }
    }
    return result;
  }

  /// 将相对路径（`/` 分隔）写入本地镜像文件。
  Future<File> _mirrorFile(Directory mirror, String relPath) async {
    final segments = relPath.split('/').where((e) => e.isNotEmpty).toList();
    final file = File(p.joinAll([mirror.path, ...segments]));
    await file.parent.create(recursive: true);
    return file;
  }

  /// 增量同步：源实例工作目录 → 本地镜像。
  ///
  /// 与 `cluster_sync_manifest` 比对的 `(size, mtime)` 判定变化文件，仅下载变化项。
  Future<void> syncToMirror(ClusterInstance instance) async {
    final sourceNode = _nodeById(instance.nodeId);
    if (sourceNode == null) {
      throw StateError('节点 ${instance.nodeId} 不存在');
    }
    final client = nodeState.clientFor(sourceNode);
    final files = await _walkRemote(
      client,
      instance.daemonId,
      instance.remoteUuid,
      '/',
    );

    final mirror = await _mirrorDir(instance.id);
    final manifestRows = await DatabaseManager.instance.getSyncManifest(
      instance.id,
    );
    final oldByPath = {
      for (final row in manifestRows)
        row['rel_path'] as String: row,
    };

    final newManifest = <Map<String, dynamic>>[];
    for (final file in files) {
      final old = oldByPath[file.relPath];
      final changed =
          old == null ||
          old['size'] != file.entry.size ||
          old['mtime'] != file.entry.time;
      if (changed) {
        final ticket = await client.downloadTicket(
          daemonId: instance.daemonId,
          uuid: instance.remoteUuid,
          fileName: file.relPath,
        );
        final bytes = await client.directDownload(ticket);
        final target = await _mirrorFile(mirror, file.relPath);
        await target.writeAsBytes(bytes, flush: true);
      }
      newManifest.add({
        'rel_path': file.relPath,
        'size': file.entry.size,
        'mtime': file.entry.time,
      });
    }

    await DatabaseManager.instance.replaceSyncManifest(instance.id, newManifest);
    await clusterState.markSynced(instance.id, DateTime.now());
  }

  /// 递归枚举本地镜像目录，返回扁平文件列表（相对路径 → 文件）。
  Future<List<({String relPath, File file})>> _walkLocal(Directory dir) async {
    final result = <({String relPath, File file})>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final rel = p
            .relative(entity.path, from: dir.path)
            .replaceAll('\\', '/');
        result.add((relPath: rel, file: entity));
      }
    }
    return result;
  }

  /// 下发本地镜像到目标实例：重建目录结构并逐个上传文件。
  Future<void> restoreFromMirror(
    ClusterInstance instance, {
    required NodeApiClient client,
    required String daemonId,
    required String uuid,
  }) async {
    final mirror = await _mirrorDir(instance.id);
    if (!await mirror.exists()) return;
    final files = await _walkLocal(mirror);

    // 先按路径深度升序建目录，确保父目录先于子目录创建。
    final dirs = <String>{};
    for (final file in files) {
      final parent = p.posix.dirname(file.relPath);
      if (parent != '.' && parent != '/') {
        dirs.add(parent);
      }
    }
    final sortedDirs = dirs.toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final dir in sortedDirs) {
      await client.mkdir(daemonId: daemonId, uuid: uuid, target: '/$dir');
    }

    for (final file in files) {
      final parent = p.posix.dirname(file.relPath);
      final uploadDir = (parent == '.' || parent == '/') ? '/' : '/$parent';
      final ticket = await client.uploadTicket(
        daemonId: daemonId,
        uuid: uuid,
        uploadDir: uploadDir,
      );
      await client.directUpload(ticket: ticket, localPath: file.file.path);
    }
  }

  /// 等待远程实例转为停止态（超时抛错）。
  Future<void> waitStopped(
    NodeApiClient client,
    String daemonId,
    String uuid,
  ) async {
    final deadline = DateTime.now().add(stopTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final instance = await client.getInstance(uuid: uuid, daemonId: daemonId);
      if (instance.status == RemoteStatus.stopped) return;
      await Future.delayed(const Duration(seconds: 2));
    }
    throw StateError('等待实例停止超时');
  }

  /// 组装迁移 / 重建实例所需的配置（autoRestart 关闭，保证崩溃可观测）。
  InstanceConfig _configFor(ClusterInstance instance) {
    return InstanceConfig(
      nickname: instance.name,
      startCommand: instance.startCommand,
      stopCommand: 'stop',
      cwd: instance.cwd,
      processType: 'universal',
      autoStart: false,
      autoRestart: false,
    );
  }

  /// 将实例从源节点迁移到 [targetNodeId]。
  Future<void> migrate(
    ClusterInstance instance, {
    required String targetNodeId,
  }) async {
    final sourceNode = _nodeById(instance.nodeId);
    final targetNode = _nodeById(targetNodeId);
    if (sourceNode == null || targetNode == null) {
      throw StateError('源节点或目标节点不存在');
    }
    if (targetNodeId == instance.nodeId) {
      throw StateError('目标节点与当前节点相同，无需迁移');
    }

    final sourceClient = nodeState.clientFor(sourceNode);
    final targetClient = nodeState.clientFor(targetNode);

    // 1. 优雅停止源实例并等待退出。
    await sourceClient.instanceAction(
      uuid: instance.remoteUuid,
      daemonId: instance.daemonId,
      action: RemoteAction.stop,
    );
    await waitStopped(sourceClient, instance.daemonId, instance.remoteUuid);

    // 2. 同步数据到本地镜像。
    await syncToMirror(instance);

    // 3. 在目标节点重建实例。
    final targetDaemonId = await resolveDaemonId(targetNode);
    final newUuid = await targetClient.createInstance(
      daemonId: targetDaemonId,
      config: _configFor(instance).toJson(),
    );

    // 4. 从镜像下发数据。
    await restoreFromMirror(
      instance,
      client: targetClient,
      daemonId: targetDaemonId,
      uuid: newUuid,
    );

    // 5. 启动目标实例。
    await targetClient.instanceAction(
      uuid: newUuid,
      daemonId: targetDaemonId,
      action: RemoteAction.start,
    );

    // 6. 更新位置并清零崩溃计数。
    await clusterState.updatePlacement(
      instance.id,
      nodeId: targetNodeId,
      daemonId: targetDaemonId,
      remoteUuid: newUuid,
    );
    await clusterState.resetCrash(instance.id);
  }
}
