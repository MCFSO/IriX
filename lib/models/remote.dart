// 远程节点数据模型
// 解析 MCSManager / IriX 本地节点 API 返回的 JSON（概览、实例、文件、用户）。
// 纯 Dart 模型，不依赖 Flutter；所有解析均带容错默认值。

/// 概览数据（GET /api/overview）。
class OverviewData {
  /// 面板/守护进程版本。
  final String version;

  /// 系统信息。
  final OverviewSystem system;

  /// 面板进程信息。
  final OverviewProcess process;

  /// 守护进程列表。
  final List<DaemonInfo> remote;

  const OverviewData({
    required this.version,
    required this.system,
    required this.process,
    required this.remote,
  });

  factory OverviewData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final system = OverviewSystem.fromJson(
      (data['system'] as Map<String, dynamic>?) ?? {},
    );
    final process = OverviewProcess.fromJson(
      (data['process'] as Map<String, dynamic>?) ?? {},
    );
    final remotes = <DaemonInfo>[];
    for (final item in (data['remote'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        remotes.add(DaemonInfo.fromJson(item));
      }
    }
    return OverviewData(
      version: data['version'] as String? ?? '',
      system: system,
      process: process,
      remote: remotes,
    );
  }
}

/// 概览中的系统信息。
class OverviewSystem {
  final String type;
  final String hostname;
  final String platform;
  final String release;

  /// 系统版本（如 "22.04"），部分面板单独返回；缺失时回退 [release]。
  final String version;

  final double uptime;
  final int totalMem;
  final int freeMem;
  final double cpuUsage;
  final double memUsage;

  /// 磁盘使用率（0~1）。
  final double diskUsage;

  /// 磁盘总容量 / 已用（字节）。
  final int diskTotal;
  final int diskUsed;

  /// 网络下载 / 上传速率（字节/秒）。
  final double networkDownload;
  final double networkUpload;

  const OverviewSystem({
    this.type = '',
    this.hostname = '',
    this.platform = '',
    this.release = '',
    this.version = '',
    this.uptime = 0,
    this.totalMem = 0,
    this.freeMem = 0,
    this.cpuUsage = 0,
    this.memUsage = 0,
    this.diskUsage = 0,
    this.diskTotal = 0,
    this.diskUsed = 0,
    this.networkDownload = 0,
    this.networkUpload = 0,
  });

  factory OverviewSystem.fromJson(Map<String, dynamic> json) {
    return OverviewSystem(
      type: json['type'] as String? ?? '',
      hostname: json['hostname'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      release: json['release'] as String? ?? '',
      version: json['version'] as String? ?? '',
      uptime: (json['uptime'] as num?)?.toDouble() ?? 0,
      totalMem: (json['totalmem'] as num?)?.toInt() ?? 0,
      freeMem: (json['freemem'] as num?)?.toInt() ?? 0,
      cpuUsage: (json['cpuUsage'] as num?)?.toDouble() ?? 0,
      memUsage: (json['memUsage'] as num?)?.toDouble() ?? 0,
      diskUsage: (json['diskusage'] as num?)?.toDouble() ?? 0,
      diskTotal: (json['disktotal'] as num?)?.toInt() ?? 0,
      diskUsed: (json['diskused'] as num?)?.toInt() ?? 0,
      networkDownload: (json['networkDownload'] as num?)?.toDouble() ?? 0,
      networkUpload: (json['networkUpload'] as num?)?.toDouble() ?? 0,
    );
  }

  /// 系统版本（优先 [version]，回退 [release]）。
  String get systemVersion => version.isNotEmpty ? version : release;

  /// 是否有磁盘数据。
  bool get hasDisk => diskTotal > 0 || diskUsage > 0;

  /// 是否有网络数据。
  bool get hasNetwork => networkDownload > 0 || networkUpload > 0;

  /// 用 [other] 填充本实例缺失的磁盘 / 网络字段，返回新实例。
  ///
  /// 供 MCSM 场景使用：面板 `system` 可能不含磁盘 / 网络，而数据位于
  /// `overview.remote` 的 daemon 中，需要合并。
  OverviewSystem mergedWith(OverviewSystem other) {
    return OverviewSystem(
      type: type,
      hostname: hostname,
      platform: platform,
      release: release,
      version: version,
      uptime: uptime,
      totalMem: totalMem,
      freeMem: freeMem,
      cpuUsage: cpuUsage,
      memUsage: memUsage,
      diskUsage: hasDisk ? diskUsage : other.diskUsage,
      diskTotal: hasDisk ? diskTotal : other.diskTotal,
      diskUsed: hasDisk ? diskUsed : other.diskUsed,
      networkDownload: hasNetwork ? networkDownload : other.networkDownload,
      networkUpload: hasNetwork ? networkUpload : other.networkUpload,
    );
  }
}

/// 概览中的进程信息。
class OverviewProcess {
  final double cpu;
  final int memory;
  final String cwd;

  const OverviewProcess({this.cpu = 0, this.memory = 0, this.cwd = ''});

  factory OverviewProcess.fromJson(Map<String, dynamic> json) {
    return OverviewProcess(
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0,
      memory: (json['memory'] as num?)?.toInt() ?? 0,
      cwd: json['cwd'] as String? ?? '',
    );
  }
}

/// 守护进程信息（概览 remote 列表项）。
class DaemonInfo {
  final String uuid;
  final String ip;
  final int port;
  final String remarks;
  final String version;
  final bool available;
  final int runningInstances;
  final int totalInstances;
  final OverviewSystem system;

  const DaemonInfo({
    required this.uuid,
    required this.ip,
    required this.port,
    required this.remarks,
    required this.version,
    required this.available,
    required this.runningInstances,
    required this.totalInstances,
    required this.system,
  });

  factory DaemonInfo.fromJson(Map<String, dynamic> json) {
    final instance = (json['instance'] as Map<String, dynamic>?) ?? {};
    return DaemonInfo(
      uuid: json['uuid'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      remarks: json['remarks'] as String? ?? '',
      version: json['version'] as String? ?? '',
      available: json['available'] as bool? ?? false,
      runningInstances: (instance['running'] as num?)?.toInt() ?? 0,
      totalInstances: (instance['total'] as num?)?.toInt() ?? 0,
      system: OverviewSystem.fromJson(
        (json['system'] as Map<String, dynamic>?) ?? {},
      ),
    );
  }

  String get displayName => remarks.isNotEmpty ? remarks : '$ip:$port';
}

/// 远程实例运行状态（与 MCSM 一致）。
enum RemoteStatus {
  busy(-1, '忙碌'),
  stopped(0, '已关闭'),
  stopping(1, '停止中'),
  starting(2, '启动中'),
  running(3, '运行中');

  const RemoteStatus(this.code, this.label);

  final int code;
  final String label;

  static RemoteStatus fromCode(int code) {
    for (final s in RemoteStatus.values) {
      if (s.code == code) return s;
    }
    return RemoteStatus.stopped;
  }
}

/// 远程实例（MCSM InstanceDetail）。
class RemoteInstance {
  final String uuid;
  final InstanceConfig config;
  final RemoteStatus status;
  final int started;
  final int space;
  final int pid;
  final int currentPlayers;
  final int maxPlayers;

  const RemoteInstance({
    required this.uuid,
    required this.config,
    required this.status,
    required this.started,
    required this.space,
    required this.pid,
    required this.currentPlayers,
    required this.maxPlayers,
  });

  factory RemoteInstance.fromJson(Map<String, dynamic> json) {
    final info = (json['info'] as Map<String, dynamic>?) ?? {};
    final proc = (json['processInfo'] as Map<String, dynamic>?) ?? {};
    final cfgJson = (json['config'] as Map<String, dynamic>?) ?? {};
    return RemoteInstance(
      uuid: json['instanceUuid'] as String? ?? '',
      config: InstanceConfig.fromJson(cfgJson),
      status: RemoteStatus.fromCode((json['status'] as num?)?.toInt() ?? 0),
      started: (json['started'] as num?)?.toInt() ?? 0,
      space: (json['space'] as num?)?.toInt() ?? 0,
      pid: (proc['pid'] as num?)?.toInt() ?? 0,
      currentPlayers: (info['currentPlayers'] as num?)?.toInt() ?? -1,
      maxPlayers: (info['maxPlayers'] as num?)?.toInt() ?? -1,
    );
  }
}

/// 实例 Docker 配置（MCSM InstanceConfig.docker）。
class InstanceDockerConfig {
  final String containerName;
  final String image;
  final int memory; // MB
  final List<String> ports;
  final List<String> extraVolumes;
  final String networkMode;
  final int cpuUsage;
  final List<String> env;
  final List<String> networkAliases;

  const InstanceDockerConfig({
    this.containerName = '',
    this.image = 'mcsm-ubuntu:22.04',
    this.memory = 1024,
    this.ports = const [],
    this.extraVolumes = const [],
    this.networkMode = 'bridge',
    this.cpuUsage = 100,
    this.env = const [],
    this.networkAliases = const [],
  });

  factory InstanceDockerConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InstanceDockerConfig();
    List<String> strList(Object? value) =>
        (value as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    return InstanceDockerConfig(
      containerName: json['containerName'] as String? ?? '',
      image: json['image'] as String? ?? 'mcsm-ubuntu:22.04',
      memory: (json['memory'] as num?)?.toInt() ?? 1024,
      ports: strList(json['ports']),
      extraVolumes: strList(json['extraVolumes']),
      networkMode: json['networkMode'] as String? ?? 'bridge',
      cpuUsage: (json['cpuUsage'] as num?)?.toInt() ?? 100,
      env: strList(json['env']),
      networkAliases: strList(json['networkAliases']),
    );
  }

  /// 转回 MCSM API 所需的完整 docker 配置 JSON。
  Map<String, dynamic> toJson() => {
    'containerName': containerName,
    'image': image,
    'memory': memory,
    'ports': ports,
    'extraVolumes': extraVolumes,
    'maxSpace': null,
    'network': null,
    'io': null,
    'networkMode': networkMode,
    'networkAliases': networkAliases,
    'cpusetCpus': '',
    'cpuUsage': cpuUsage,
    'workingDir': '',
    'changeWorkdir': false,
    'env': env,
  };
}

/// 实例配置（MCSM InstanceConfig）。
class InstanceConfig {
  final String nickname;
  final String startCommand;
  final String stopCommand;
  final String cwd;
  final String type;
  final String processType;
  final String fileCode;
  final String ie;
  final String oe;
  final bool autoStart;
  final bool autoRestart;
  final bool ignore;
  final List<String> tag;
  final int createDatetime;
  final InstanceDockerConfig docker;

  const InstanceConfig({
    this.nickname = '',
    this.startCommand = '',
    this.stopCommand = 'stop',
    this.cwd = '',
    this.type = 'universal',
    this.processType = 'universal',
    this.fileCode = 'utf-8',
    this.ie = 'utf-8',
    this.oe = 'utf-8',
    this.autoStart = false,
    this.autoRestart = false,
    this.ignore = false,
    this.tag = const [],
    this.createDatetime = 0,
    this.docker = const InstanceDockerConfig(),
  });

  factory InstanceConfig.fromJson(Map<String, dynamic> json) {
    final event = (json['eventTask'] as Map<String, dynamic>?) ?? {};
    return InstanceConfig(
      nickname: json['nickname'] as String? ?? '',
      startCommand: json['startCommand'] as String? ?? '',
      stopCommand: json['stopCommand'] as String? ?? 'stop',
      cwd: json['cwd'] as String? ?? '',
      type: json['type'] as String? ?? 'universal',
      processType: json['processType'] as String? ?? 'universal',
      fileCode: json['fileCode'] as String? ?? 'utf-8',
      ie: json['ie'] as String? ?? 'utf-8',
      oe: json['oe'] as String? ?? 'utf-8',
      autoStart: event['autoStart'] as bool? ?? false,
      autoRestart: event['autoRestart'] as bool? ?? false,
      ignore: event['ignore'] as bool? ?? false,
      tag: (json['tag'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      createDatetime: (json['createDatetime'] as num?)?.toInt() ?? 0,
      docker: InstanceDockerConfig.fromJson(
        (json['docker'] as Map<String, dynamic>?) ?? {},
      ),
    );
  }

  /// 转回 MCSM API 所需的完整配置 JSON。
  Map<String, dynamic> toJson() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'nickname': nickname,
      'startCommand': startCommand,
      'stopCommand': stopCommand,
      'cwd': cwd,
      'ie': ie,
      'oe': oe,
      'createDatetime': createDatetime,
      'lastDatetime': now,
      'type': type,
      'tag': tag,
      'endTime': now + 365 * 24 * 3600 * 1000,
      'fileCode': fileCode,
      'processType': processType,
      'updateCommand': '',
      'actionCommandList': [],
      'crlf': 2,
      'eventTask': {
        'autoStart': autoStart,
        'autoRestart': autoRestart,
        'ignore': ignore,
      },
      'pingConfig': {'ip': '', 'port': 25565, 'type': 1},
      'docker': docker.toJson(),
    };
  }
}

/// 远程文件条目。
class RemoteFileEntry {
  final String name;
  final int size;
  final String time;
  final int mode;
  final int type; // 0 = 文件夹, 1 = 文件

  const RemoteFileEntry({
    required this.name,
    required this.size,
    required this.time,
    required this.mode,
    required this.type,
  });

  bool get isDirectory => type == 0;

  factory RemoteFileEntry.fromJson(Map<String, dynamic> json) {
    return RemoteFileEntry(
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      time: json['time'] as String? ?? '',
      mode: (json['mode'] as num?)?.toInt() ?? 0,
      type: (json['type'] as num?)?.toInt() ?? 1,
    );
  }
}

/// 文件列表数据。
class FileListData {
  final List<RemoteFileEntry> items;
  final int total;
  final String absolutePath;

  const FileListData({
    required this.items,
    required this.total,
    required this.absolutePath,
  });

  factory FileListData.fromJson(Map<String, dynamic> json) {
    final list = <RemoteFileEntry>[];
    for (final item in (json['items'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        list.add(RemoteFileEntry.fromJson(item));
      }
    }
    return FileListData(
      items: list,
      total: (json['total'] as num?)?.toInt() ?? 0,
      absolutePath: json['absolutePath'] as String? ?? '/',
    );
  }
}

/// 远程用户。
class RemoteUser {
  final String uuid;
  final String userName;
  final int permission; // 1=User, 10=Admin, -1=Banned
  final String registerTime;
  final String loginTime;
  final String apiKey;
  final bool isInit;
  final bool open2FA;
  final List<Map<String, String>> instances;

  const RemoteUser({
    required this.uuid,
    required this.userName,
    required this.permission,
    required this.registerTime,
    required this.loginTime,
    required this.apiKey,
    required this.isInit,
    required this.open2FA,
    required this.instances,
  });

  factory RemoteUser.fromJson(Map<String, dynamic> json) {
    final instances = <Map<String, String>>[];
    for (final item in (json['instances'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        instances.add({
          'instanceUuid': item['instanceUuid'] as String? ?? '',
          'daemonId': item['daemonId'] as String? ?? '',
        });
      }
    }
    return RemoteUser(
      uuid: json['uuid'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      permission: (json['permission'] as num?)?.toInt() ?? 1,
      registerTime: json['registerTime'] as String? ?? '',
      loginTime: json['loginTime'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      isInit: json['isInit'] as bool? ?? false,
      open2FA: json['open2FA'] as bool? ?? false,
      instances: instances,
    );
  }

  /// 构建 PUT /api/auth 所需的完整用户配置。
  Map<String, dynamic> toConfigJson() => {
    'uuid': uuid,
    'userName': userName,
    'loginTime': loginTime,
    'registerTime': registerTime,
    'instances': instances,
    'permission': permission,
    'apiKey': apiKey,
    'isInit': isInit,
    'secret': '',
    'open2FA': open2FA,
  };
}

/// 用户列表数据（GET /api/auth/search）。
class UserListData {
  final List<RemoteUser> users;
  final int maxPage;
  final int total;

  const UserListData({
    required this.users,
    required this.maxPage,
    required this.total,
  });

  factory UserListData.fromJson(Map<String, dynamic> json) {
    final list = <RemoteUser>[];
    for (final item in (json['data'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        list.add(RemoteUser.fromJson(item));
      }
    }
    return UserListData(
      users: list,
      maxPage: (json['maxPage'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}
