// IriX 本地节点（Go 守护进程）扩展接口的数据模型。
//
// 覆盖 NODE_API.md 之外、irix-node 独有的节点侧接口返回结构：
// 实例日志/指标、快照备份、回收站、Java 运行时、FRP、账户、集群状态。
// 纯 Dart 模型，不依赖 Flutter；所有解析均带容错默认值。

/// 实例实时运行指标（GET /api/instance/stats，见 instance_stats.go）。
///
/// pid / cpu / 内存 / 网络 / 运行时长为进程级；players / maxPlayers / tps
/// 由服务器输出解析，解析失败时字段为 -1（客户端显示「—」）。
class InstanceStatsData {
  final int pid;
  final double cpuPercent;
  final int memoryMb;
  final int networkDownloadBps;
  final int networkUploadBps;
  final int uptimeSec;
  final int players;
  final int maxPlayers;
  final double tps;

  const InstanceStatsData({
    this.pid = 0,
    this.cpuPercent = 0,
    this.memoryMb = 0,
    this.networkDownloadBps = 0,
    this.networkUploadBps = 0,
    this.uptimeSec = 0,
    this.players = -1,
    this.maxPlayers = -1,
    this.tps = -1,
  });

  factory InstanceStatsData.fromJson(Map<String, dynamic> json) {
    double numOr(Object? v, [double d = 0]) => (v as num?)?.toDouble() ?? d;
    return InstanceStatsData(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      cpuPercent: numOr(json['cpuPercent']),
      memoryMb: (json['memoryMb'] as num?)?.toInt() ?? 0,
      networkDownloadBps: (json['networkDownloadBps'] as num?)?.toInt() ?? 0,
      networkUploadBps: (json['networkUploadBps'] as num?)?.toInt() ?? 0,
      uptimeSec: (json['uptimeSec'] as num?)?.toInt() ?? 0,
      players: (json['players'] as num?)?.toInt() ?? -1,
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? -1,
      tps: numOr(json['tps'], -1),
    );
  }

  /// TPS 是否已解析（未解析为 -1）。
  bool get hasTps => tps >= 0;

  /// 玩家数是否已解析（未解析为 -1）。
  bool get hasPlayers => players >= 0;
}

/// 实例监控历史采样（GET /api/instance/metrics，见 instance_metrics.go）。
class MetricSample {
  final int time; // unix 毫秒
  final double cpu;
  final int memoryMb;
  final int downloadBps;
  final int uploadBps;

  const MetricSample({
    this.time = 0,
    this.cpu = 0,
    this.memoryMb = 0,
    this.downloadBps = 0,
    this.uploadBps = 0,
  });

  factory MetricSample.fromJson(Map<String, dynamic> json) {
    double numOr(Object? v, [double d = 0]) => (v as num?)?.toDouble() ?? d;
    return MetricSample(
      time: (json['time'] as num?)?.toInt() ?? 0,
      cpu: numOr(json['cpu']),
      memoryMb: (json['memoryMb'] as num?)?.toInt() ?? 0,
      downloadBps: (json['downloadBps'] as num?)?.toInt() ?? 0,
      uploadBps: (json['uploadBps'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 实例备份条目（GET /api/instance/backups，见 backup.go）。
class BackupItem {
  final String fileName;
  final int size;
  final String mtime;
  final String path;

  const BackupItem({
    this.fileName = '',
    this.size = 0,
    this.mtime = '',
    this.path = '',
  });

  factory BackupItem.fromJson(Map<String, dynamic> json) {
    return BackupItem(
      fileName: json['fileName'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtime: json['mtime'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

/// 回收站条目（GET /api/files/trash/list，见 trash.go）。
class TrashItem {
  final String id;
  final String name;
  final String originalPath; // 相对 cwd（/ 开头）
  final String trashPath; // 相对 cwd（/ 开头）
  final int size;
  final int deletedAt; // unix 毫秒

  const TrashItem({
    this.id = '',
    this.name = '',
    this.originalPath = '',
    this.trashPath = '',
    this.size = 0,
    this.deletedAt = 0,
  });

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      originalPath: json['originalPath'] as String? ?? '',
      trashPath: json['trashPath'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      deletedAt: (json['deletedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 节点上检测到的 Java 运行时（GET /api/runtime/java，见 runtime.go）。
class JavaRuntime {
  final String path;
  final String version;
  final String vendor;
  final int major;
  final bool available;

  const JavaRuntime({
    this.path = '',
    this.version = '',
    this.vendor = '',
    this.major = 0,
    this.available = false,
  });

  factory JavaRuntime.fromJson(Map<String, dynamic> json) {
    return JavaRuntime(
      path: json['path'] as String? ?? '',
      version: json['version'] as String? ?? '',
      vendor: json['vendor'] as String? ?? '',
      major: (json['major'] as num?)?.toInt() ?? 0,
      available: json['available'] as bool? ?? false,
    );
  }
}

/// 节点 frpc 二进制状态（GET /api/frp/status，见 frp.go）。
class FrpcBinaryInfo {
  final bool present;
  final String path;
  final String version;

  const FrpcBinaryInfo({
    this.present = false,
    this.path = '',
    this.version = '',
  });

  factory FrpcBinaryInfo.fromJson(Map<String, dynamic> json) {
    return FrpcBinaryInfo(
      present: json['present'] as bool? ?? false,
      path: json['path'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }
}

/// FRP 隧道（GET /api/frp/status，见 frp.go）。
class FrpTunnelInfo {
  final String id;
  final String name;
  final String provider; // openfrp | sakura | self
  final String status; // running | stopped | failed
  final Map<String, dynamic> config;

  const FrpTunnelInfo({
    this.id = '',
    this.name = '',
    this.provider = '',
    this.status = 'stopped',
    this.config = const {},
  });

  factory FrpTunnelInfo.fromJson(Map<String, dynamic> json) {
    final cfg = json['config'];
    return FrpTunnelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      status: json['status'] as String? ?? 'stopped',
      config: cfg is Map<String, dynamic> ? cfg : <String, dynamic>{},
    );
  }
}

/// 账户信息（GET /api/accounts、/api/accounts/me，见 accounts_handlers.go）。
class AccountInfo {
  final String username;
  final bool isAdmin;
  final bool builtin;
  final bool mustChangePassword;
  final int? createdAt;

  const AccountInfo({
    this.username = '',
    this.isAdmin = false,
    this.builtin = false,
    this.mustChangePassword = false,
    this.createdAt,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      username: json['username'] as String? ?? '',
      isAdmin: json['isAdmin'] as bool? ?? false,
      builtin: json['builtin'] as bool? ?? false,
      mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }
}

/// 权限目录条目（GET /api/accounts/catalog，见 perm_catalog.go）。
class PermissionEntry {
  final String key; // 端点模式，如 "GET /api/files/list"
  final String description;

  const PermissionEntry({this.key = '', this.description = ''});

  factory PermissionEntry.fromJson(Map<String, dynamic> json) {
    return PermissionEntry(
      key: json['key'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// 权限分组（GET /api/accounts/catalog）。
class PermissionGroup {
  final String name;
  final List<PermissionEntry> entries;

  const PermissionGroup({this.name = '', this.entries = const []});

  factory PermissionGroup.fromJson(Map<String, dynamic> json) {
    final list = <PermissionEntry>[];
    for (final item in (json['entries'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        list.add(PermissionEntry.fromJson(item));
      }
    }
    return PermissionGroup(name: json['name'] as String? ?? '', entries: list);
  }
}

/// 集群状态（GET /api/cluster/status，见 cluster.go）。
class ClusterStatusData {
  final String monitorNodeId;
  final String role;
  final List<Map<String, dynamic>> peers;
  final Map<String, dynamic> self;

  const ClusterStatusData({
    this.monitorNodeId = '',
    this.role = '',
    this.peers = const [],
    this.self = const {},
  });

  factory ClusterStatusData.fromJson(Map<String, dynamic> json) {
    final peers = <Map<String, dynamic>>[];
    for (final item in (json['peers'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) peers.add(item);
    }
    final self = json['self'];
    return ClusterStatusData(
      monitorNodeId: json['monitorNodeId'] as String? ?? '',
      role: json['role'] as String? ?? '',
      peers: peers,
      self: self is Map<String, dynamic> ? self : <String, dynamic>{},
    );
  }
}

/// 任务进度（节点任务化接口：快照/恢复/核心下载/JDK 安装共用）。
///
/// 字段：status(running|done|failed|pending)、percent(0~1)、message、path/archivePath。
/// 失败时 data 为错误消息字符串（见 _request 的 NodeApiException）。
class NodeTaskProgress {
  final String status;
  final double percent;
  final String message;
  final String path;

  const NodeTaskProgress({
    this.status = '',
    this.percent = 0,
    this.message = '',
    this.path = '',
  });

  factory NodeTaskProgress.fromJson(Map<String, dynamic> json) {
    double numOr(Object? v, [double d = 0]) => (v as num?)?.toDouble() ?? d;
    return NodeTaskProgress(
      status: json['status'] as String? ?? '',
      percent: numOr(json['percent']),
      message: json['message'] as String? ?? '',
      path: json['path'] as String? ?? json['archivePath'] as String? ?? '',
    );
  }

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
}

/// 长任务进度（无百分比的日志型任务）。
///
/// 对应 irix-node 的 `GET /api/bastille/jobs/{jobId}`（见 container.go 的
/// `longJob`）：只返回 `{status, log}`，状态取 `running` / `done` / `failed`，
/// `log` 为按行收集的进程输出（服务端保留最近若干行）。与带百分比 / 消息的
/// [NodeTaskProgress]（任务表 jobs.go）区分。
class NodeJobProgress {
  /// 任务状态：`running` / `done` / `failed`。
  final String status;

  /// 进程输出行（保留最近 N 行）。
  final List<String> log;

  const NodeJobProgress({this.status = '', this.log = const []});

  factory NodeJobProgress.fromJson(Map<String, dynamic> json) {
    final raw = json['log'];
    final lines = <String>[];
    if (raw is List) {
      for (final line in raw) {
        lines.add(line?.toString() ?? '');
      }
    } else if (raw is String && raw.isNotEmpty) {
      // 兼容服务端未来把 log 收敛为整段文本的形态。
      lines.addAll(raw.split('\n'));
    }
    return NodeJobProgress(
      status: json['status'] as String? ?? '',
      log: lines,
    );
  }

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  /// 日志尾部 [lines] 行（用于向用户展示失败原因）。
  String tailLog([int lines = 10]) {
    if (log.isEmpty) return '';
    final start = log.length > lines ? log.length - lines : 0;
    return log.sublist(start).join('\n');
  }
}

/// 集群节点间迁移的来源节点信息（irix-node `POST /api/cluster/transfer`）。
///
/// [token] 为来源节点的**账户会话 token**（来源为 MCSM 节点时填其 apikey，
/// 见 cluster.go 的 nodeRequest 说明）；目标节点用它向来源节点申请实例快照
/// 并直连下载。
class ClusterTransferSource {
  /// 来源节点地址（host:port 或 http(s)://host:port）。
  final String address;

  /// 来源节点会话 token（可为空，前提是来源节点未启用账户系统）。
  final String token;

  /// 来源节点上的实例 uuid。
  final String uuid;

  /// 来源节点的 daemonId（MCSM 兼容字段，irix-node 可留空）。
  final String daemonId;

  const ClusterTransferSource({
    required this.address,
    this.token = '',
    required this.uuid,
    this.daemonId = '',
  });

  Map<String, dynamic> toJson() => {
    'address': address,
    'token': token,
    'uuid': uuid,
    'daemonId': daemonId,
  };
}

/// 集群节点间迁移任务进度（irix-node `GET /api/cluster/transfer`）。
class ClusterTransferProgress {
  /// 任务状态：`running` / `done` / `failed`。
  final String status;

  /// 已传输字节数（服务端实时累计）。
  final int bytes;

  const ClusterTransferProgress({this.status = '', this.bytes = 0});

  factory ClusterTransferProgress.fromJson(Map<String, dynamic> json) {
    return ClusterTransferProgress(
      status: json['status'] as String? ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
}
