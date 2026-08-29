// 编排系统数据模型（K8s 风格）
// 与 Rust xmc_orchestrator crate 的 JSON 契约一一对应（camelCase）：
// McService ≈ Deployment（期望状态）、McReplica ≈ Pod（有状态副本）、
// MigrationJob ≈ 跨物理机迁移工作流、OrchestrationAction ≈ 对账动作。

import '../services/locale_settings.dart';
/// 服务组（Deployment）：期望状态与弹性/自愈策略。
class McService {
  const McService({
    required this.id,
    required this.name,
    required this.runtime,
    required this.image,
    this.command,
    this.ports = const [],
    this.volumes = const [],
    this.env = const {},
    this.restartPolicy,
    this.memoryLimitMb,
    this.cpus,
    this.workdir,
    this.worldDir = '/data/world',
    this.jailType,
    this.vnetMode,
    this.bastilleIpBase,
    this.bastilleIpMask = 24,
    this.desiredReplicas = 1,
    this.minReplicas = 0,
    this.maxReplicas = 8,
    this.autoscale = false,
    this.targetPlayers = 20,
    this.scaleUpPlayers = 20,
    this.scaleDownPlayers = 10,
    this.cooldownSecs = 300,
    this.autoHeal = true,
    this.crashThreshold = 5,
    this.backoffBaseSecs = 5,
    this.maxBackoffSecs = 300,
    this.nodeSelector = const {},
    this.createdAtMs = 0,
  });

  final String id;
  final String name;

  /// docker | bastille
  final String runtime;
  final String image;
  final String? command;
  final List<String> ports;
  final List<String> volumes;
  final Map<String, String> env;
  final String? restartPolicy;
  final int? memoryLimitMb;
  final int? cpus;
  final String? workdir;
  final String worldDir;
  final String? jailType;
  final String? vnetMode;
  final String? bastilleIpBase;
  final int bastilleIpMask;
  final int desiredReplicas;
  final int minReplicas;
  final int maxReplicas;
  final bool autoscale;
  final int targetPlayers;
  final int scaleUpPlayers;
  final int scaleDownPlayers;
  final int cooldownSecs;
  final bool autoHeal;
  final int crashThreshold;
  final int backoffBaseSecs;
  final int maxBackoffSecs;
  final Map<String, String> nodeSelector;
  final int createdAtMs;

  factory McService.fromJson(Map<String, dynamic> json) => McService(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    runtime: json['runtime'] as String? ?? 'docker',
    image: json['image'] as String? ?? '',
    command: json['command'] as String?,
    ports: (json['ports'] as List<dynamic>? ?? []).whereType<String>().toList(),
    volumes: (json['volumes'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList(),
    env: (json['env'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, v.toString()),
    ),
    restartPolicy: json['restartPolicy'] as String?,
    memoryLimitMb: (json['memoryLimitMb'] as num?)?.toInt(),
    cpus: (json['cpus'] as num?)?.toInt(),
    workdir: json['workdir'] as String?,
    worldDir: json['worldDir'] as String? ?? '/data/world',
    jailType: json['jailType'] as String?,
    vnetMode: json['vnetMode'] as String?,
    bastilleIpBase: json['bastilleIpBase'] as String?,
    bastilleIpMask: (json['bastilleIpMask'] as num?)?.toInt() ?? 24,
    desiredReplicas: (json['desiredReplicas'] as num?)?.toInt() ?? 1,
    minReplicas: (json['minReplicas'] as num?)?.toInt() ?? 0,
    maxReplicas: (json['maxReplicas'] as num?)?.toInt() ?? 8,
    autoscale: json['autoscale'] as bool? ?? false,
    targetPlayers: (json['targetPlayers'] as num?)?.toInt() ?? 20,
    scaleUpPlayers: (json['scaleUpPlayers'] as num?)?.toInt() ?? 20,
    scaleDownPlayers: (json['scaleDownPlayers'] as num?)?.toInt() ?? 10,
    cooldownSecs: (json['cooldownSecs'] as num?)?.toInt() ?? 300,
    autoHeal: json['autoHeal'] as bool? ?? true,
    crashThreshold: (json['crashThreshold'] as num?)?.toInt() ?? 5,
    backoffBaseSecs: (json['backoffBaseSecs'] as num?)?.toInt() ?? 5,
    maxBackoffSecs: (json['maxBackoffSecs'] as num?)?.toInt() ?? 300,
    nodeSelector: (json['nodeSelector'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, v.toString()),
    ),
    createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
  );

  /// 转为 Rust 侧接受的 JSON（camelCase）。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'runtime': runtime,
    'image': image,
    'command': command,
    'ports': ports,
    'volumes': volumes,
    'env': env,
    'restartPolicy': restartPolicy,
    'memoryLimitMb': memoryLimitMb,
    'cpus': cpus,
    'workdir': workdir,
    'worldDir': worldDir,
    'jailType': jailType,
    'vnetMode': vnetMode,
    'bastilleIpBase': bastilleIpBase,
    'bastilleIpMask': bastilleIpMask,
    'desiredReplicas': desiredReplicas,
    'minReplicas': minReplicas,
    'maxReplicas': maxReplicas,
    'autoscale': autoscale,
    'targetPlayers': targetPlayers,
    'scaleUpPlayers': scaleUpPlayers,
    'scaleDownPlayers': scaleDownPlayers,
    'cooldownSecs': cooldownSecs,
    'autoHeal': autoHeal,
    'crashThreshold': crashThreshold,
    'backoffBaseSecs': backoffBaseSecs,
    'maxBackoffSecs': maxBackoffSecs,
    'nodeSelector': nodeSelector,
    'createdAtMs': createdAtMs,
  };
}

/// 副本期望状态。
enum ReplicaDesired {
  running,
  stopped;

  static ReplicaDesired fromString(String? value) =>
      value == 'stopped' ? ReplicaDesired.stopped : ReplicaDesired.running;
}

/// 副本（Pod）：部署节点、容器名、观测状态、崩溃计数。
class McReplica {
  const McReplica({
    required this.id,
    required this.serviceId,
    required this.indexNo,
    required this.nodeId,
    required this.containerName,
    this.hostPort,
    this.ip,
    this.desired = ReplicaDesired.running,
    this.running = false,
    this.ready = false,
    this.playersOnline = 0,
    this.crashCount = 0,
    this.crashLoop = false,
    this.lastAttemptMs = 0,
    this.backoffSecs = 0,
    this.lastObservedMs = 0,
    this.stableSinceMs = 0,
    this.createdAtMs = 0,
  });

  final String id;
  final String serviceId;
  final int indexNo;
  final String nodeId;
  final String containerName;
  final int? hostPort;
  final String? ip;
  final ReplicaDesired desired;
  final bool running;
  final bool ready;
  final int playersOnline;
  final int crashCount;
  final bool crashLoop;
  final int lastAttemptMs;
  final int backoffSecs;
  final int lastObservedMs;
  final int stableSinceMs;
  final int createdAtMs;

  factory McReplica.fromJson(Map<String, dynamic> json) => McReplica(
    id: json['id'] as String? ?? '',
    serviceId: json['serviceId'] as String? ?? '',
    indexNo: (json['indexNo'] as num?)?.toInt() ?? 0,
    nodeId: json['nodeId'] as String? ?? '',
    containerName: json['containerName'] as String? ?? '',
    hostPort: (json['hostPort'] as num?)?.toInt(),
    ip: json['ip'] as String?,
    desired: ReplicaDesired.fromString(json['desired'] as String?),
    running: json['running'] as bool? ?? false,
    ready: json['ready'] as bool? ?? false,
    playersOnline: (json['playersOnline'] as num?)?.toInt() ?? 0,
    crashCount: (json['crashCount'] as num?)?.toInt() ?? 0,
    crashLoop: json['crashLoop'] as bool? ?? false,
    lastAttemptMs: (json['lastAttemptMs'] as num?)?.toInt() ?? 0,
    backoffSecs: (json['backoffSecs'] as num?)?.toInt() ?? 0,
    lastObservedMs: (json['lastObservedMs'] as num?)?.toInt() ?? 0,
    stableSinceMs: (json['stableSinceMs'] as num?)?.toInt() ?? 0,
    createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'serviceId': serviceId,
    'indexNo': indexNo,
    'nodeId': nodeId,
    'containerName': containerName,
    'hostPort': hostPort,
    'ip': ip,
    'desired': desired.name,
    'running': running,
    'ready': ready,
    'playersOnline': playersOnline,
    'crashCount': crashCount,
    'crashLoop': crashLoop,
    'lastAttemptMs': lastAttemptMs,
    'backoffSecs': backoffSecs,
    'lastObservedMs': lastObservedMs,
    'stableSinceMs': stableSinceMs,
    'createdAtMs': createdAtMs,
  };
}

/// 服务 + 副本聚合状态（UI 快照）。
class ServiceStatus {
  const ServiceStatus({
    required this.service,
    required this.replicas,
    required this.runningReplicas,
    required this.totalPlayers,
    required this.avgPlayers,
    required this.migrating,
  });

  final McService service;
  final List<McReplica> replicas;
  final int runningReplicas;
  final int totalPlayers;
  final double avgPlayers;
  final bool migrating;

  factory ServiceStatus.fromJson(Map<String, dynamic> json) => ServiceStatus(
    service: McService.fromJson(json),
    replicas: (json['replicas'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(McReplica.fromJson)
        .toList(),
    runningReplicas: (json['runningReplicas'] as num?)?.toInt() ?? 0,
    totalPlayers: (json['totalPlayers'] as num?)?.toInt() ?? 0,
    avgPlayers: (json['avgPlayers'] as num?)?.toDouble() ?? 0,
    migrating: json['migrating'] as bool? ?? false,
  );
}

/// 迁移状态机状态。
enum MigrationState {
  pending,
  stopping,
  archiving,
  transferring,
  restoring,
  creating,
  starting,
  done,
  failed;

  static MigrationState fromString(String? value) {
    for (final state in MigrationState.values) {
      if (state.name == value) return state;
    }
    return MigrationState.pending;
  }

  /// 展示标签（随语言设置切换）。
  String get label {
    final en = LocaleSettings.instance.localeCode == 'en';
    return switch (this) {
      MigrationState.pending => en ? 'Waiting to start' : '等待开始',
      MigrationState.stopping => en ? 'Stopping replica' : '停止副本',
      MigrationState.archiving => en ? 'Archiving world' : '压缩存档',
      MigrationState.transferring => en ? 'Transferring' : '传输存档',
      MigrationState.restoring => en ? 'Restoring' : '恢复存档',
      MigrationState.creating => en ? 'Creating container' : '创建容器',
      MigrationState.starting => en ? 'Starting replica' : '启动副本',
      MigrationState.done => en ? 'Done' : '完成',
      MigrationState.failed => en ? 'Failed' : '失败',
    };
  }

  bool get isActive =>
      this != MigrationState.done && this != MigrationState.failed;
}

/// 跨物理机迁移任务。
class MigrationJob {
  const MigrationJob({
    required this.id,
    required this.serviceId,
    required this.replicaId,
    required this.fromNode,
    required this.toNode,
    required this.state,
    this.error,
    this.archiveName = '',
    this.createdAtMs = 0,
    this.updatedAtMs = 0,
  });

  final String id;
  final String serviceId;
  final String replicaId;
  final String fromNode;
  final String toNode;
  final MigrationState state;
  final String? error;
  final String archiveName;
  final int createdAtMs;
  final int updatedAtMs;

  factory MigrationJob.fromJson(Map<String, dynamic> json) => MigrationJob(
    id: json['id'] as String? ?? '',
    serviceId: json['serviceId'] as String? ?? '',
    replicaId: json['replicaId'] as String? ?? '',
    fromNode: json['fromNode'] as String? ?? '',
    toNode: json['toNode'] as String? ?? '',
    state: MigrationState.fromString(json['state'] as String?),
    error: json['error'] as String?,
    archiveName: json['archiveName'] as String? ?? '',
    createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
    updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
  );
}

/// 对账动作种类。
enum OrchestrationActionKind {
  createContainer,
  startContainer,
  restartContainer,
  stopContainer,
  destroyContainer,
  archiveWorld,
  transferArchive,
  restoreArchive,
  ping,
  noop;

  static OrchestrationActionKind fromString(String? value) {
    if (value == null) return OrchestrationActionKind.noop;
    // 兼容 Rust 的 snake_case（如 restart_container）与 Dart 枚举名
    final normalized = value.replaceAll('_', '').toLowerCase();
    for (final kind in OrchestrationActionKind.values) {
      if (kind.name.toLowerCase() == normalized) return kind;
    }
    return OrchestrationActionKind.noop;
  }
}

/// 对账动作（Rust 引擎产出 → Dart 执行层落地）。
class OrchestrationAction {
  const OrchestrationAction({
    required this.kind,
    this.serviceId = '',
    this.replicaId = '',
    this.nodeId = '',
    this.payload = const {},
    this.delayMs = 0,
    this.migrationId = '',
  });

  final OrchestrationActionKind kind;
  final String serviceId;
  final String replicaId;
  final String nodeId;
  final Map<String, dynamic> payload;
  final int delayMs;
  final String migrationId;

  factory OrchestrationAction.fromJson(Map<String, dynamic> json) =>
      OrchestrationAction(
        kind: OrchestrationActionKind.fromString(json['kind'] as String?),
        serviceId: json['serviceId'] as String? ?? '',
        replicaId: json['replicaId'] as String? ?? '',
        nodeId: json['nodeId'] as String? ?? '',
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
        delayMs: (json['delayMs'] as num?)?.toInt() ?? 0,
        migrationId: json['migrationId'] as String? ?? '',
      );
}

/// MC 服务器状态（Server List Ping 结果）。
class McStatus {
  const McStatus({
    required this.online,
    this.players = 0,
    this.maxPlayers = 0,
    this.latencyMs = 0,
    this.version,
    this.motd,
  });

  final bool online;
  final int players;
  final int maxPlayers;
  final int latencyMs;
  final String? version;
  final String? motd;

  factory McStatus.fromJson(Map<String, dynamic> json) => McStatus(
    online: json['online'] as bool? ?? false,
    players: (json['players'] as num?)?.toInt() ?? 0,
    maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 0,
    latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
    version: json['version'] as String?,
    motd: json['motd'] as String?,
  );
}
