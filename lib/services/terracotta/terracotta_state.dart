// 陶瓦联机（Terracotta）状态模型。
//
// 对应 HMCL `org.jackhuang.hmcl.terracotta.TerracottaState`：联机核心在
// `http://127.0.0.1:<port>/state` 暴露一个带自增 `index` 的状态快照，本文件
// 负责把它解析成强类型状态对象，UI 再按状态渲染。
//
// 与 HMCL 的差异：Dart 没有 sealed class + Gson 多态注解，这里用
// `state` 字段做手工分发，并对字段缺失/越界做显式校验（HMCL 用 Validation）。

/// 联机难度估算（房主/房客 NAT 类型推算，仅供参考）。
enum TerracottaDifficulty { unknown, easiest, simple, medium, tough }

/// 玩家身份（对应 HMCL `ProfileKind`）。
enum TerracottaPlayerKind { host, local, guest }

/// 运行期异常类型（对应 HMCL `TerracottaState.Exception.Type`，序号与线上协议一致）。
enum TerracottaExceptionType {
  /// 加入房间失败：房间已关闭或网络不稳定。
  pingHostFail,

  /// 房间连接断开。
  pingHostRst,

  /// 房客侧 EasyTier 崩溃。
  guestEtCrash,

  /// 房主侧 EasyTier 崩溃。
  hostEtCrash,

  /// 房间已关闭（房主退出游戏世界）。
  pingServerRst,

  /// 协议错误：对端响应数据非法。
  scaffoldingInvalidResponse,
}

/// 联机核心致命错误类型（对应 HMCL `TerracottaState.Fatal.Type`）。
enum TerracottaFatalType {
  /// 平台不支持。
  os,

  /// 下载联机核心失败。
  network,

  /// 安装联机核心失败。
  install,

  /// 与联机核心通讯失败。
  terracotta,

  /// 未知原因。
  unknown,
}

/// 房间内的一位玩家。
class TerracottaProfile {
  const TerracottaProfile({
    required this.machineId,
    required this.name,
    required this.vendor,
    required this.kind,
  });

  /// 联机核心给的机器标识（用于列表去重/稳定 key）。
  final String machineId;

  /// 玩家名。
  final String name;

  /// 客户端品牌（如 `HMCL`、`PCL CE`）。
  final String vendor;

  /// 玩家身份。
  final TerracottaPlayerKind kind;

  /// 宽松解析：字段缺失时退化为安全默认值，不因单条数据异常毁掉整个状态。
  factory TerracottaProfile.fromJson(Map<String, dynamic> json) {
    return TerracottaProfile(
      machineId: json['machine_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      vendor: json['vendor']?.toString() ?? '',
      kind: _parsePlayerKind(json['kind']),
    );
  }

  static TerracottaPlayerKind _parsePlayerKind(Object? raw) {
    final text = raw?.toString().toLowerCase();
    for (final kind in TerracottaPlayerKind.values) {
      if (kind.name == text) return kind;
    }
    return TerracottaPlayerKind.guest;
  }
}

/// 联机状态基类。
sealed class TerracottaState {
  const TerracottaState();

  /// 该状态是否绑定某个本地控制端口（`/state` 等接口需要）。
  bool get isPortSpecific => false;

  /// 本地控制端口；非端口状态返回 null。
  int? get port => null;
}

/// 初始态：正在判断平台支持与本地联机核心状态。
class TerracottaBootstrap extends TerracottaState {
  const TerracottaBootstrap();
}

/// 未安装（或需要更新）联机核心。
class TerracottaUninitialized extends TerracottaState {
  const TerracottaUninitialized({required this.hasLegacy});

  /// 是否存在旧版本联机核心（存在即「需更新」）。
  final bool hasLegacy;
}

/// 正在下载 / 安装联机核心。
class TerracottaPreparing extends TerracottaState {
  const TerracottaPreparing({
    this.progress,
    this.hasInstallFence = true,
    this.statusText,
  });

  /// 下载进度 0..1；null 表示进度未知（-1）。
  final double? progress;

  /// 是否仍允许「安装完成后自动启动」。
  ///
  /// 用户在下载过程中手动从本地选择了安装包时，会把 fence 置为 false，
  /// 从而让下载任务在收尾时主动放弃，避免覆盖用户手动安装的包。
  final bool hasInstallFence;

  /// 附加说明（例如「正在解包…」），仅用于界面展示。
  final String? statusText;

  TerracottaPreparing copyWith({
    double? progress,
    bool? hasInstallFence,
    String? statusText,
  }) {
    return TerracottaPreparing(
      progress: progress ?? this.progress,
      hasInstallFence: hasInstallFence ?? this.hasInstallFence,
      statusText: statusText ?? this.statusText,
    );
  }
}

/// 正在启动联机核心进程。
class TerracottaLaunching extends TerracottaState {
  const TerracottaLaunching();
}

/// 联机核心已就绪但状态未明（刚完成端口握手）。
class TerracottaUnknown extends TerracottaState {
  const TerracottaUnknown(this.port);

  @override
  final int port;

  @override
  bool get isPortSpecific => true;
}

/// 由 `/state` 返回的「就绪」状态族。
sealed class TerracottaReady extends TerracottaState {
  const TerracottaReady({required this.port, required this.index});

  @override
  final int port;

  /// 状态自增序号；越小越旧。UI 的「假状态」用 -1。
  final int index;

  @override
  bool get isPortSpecific => true;

  /// 是否为本地伪造状态（刚点按钮时先本地乐观显示，不等核心回报）。
  bool get isUiFakeState => index == -1;
}

/// 空闲态：可选择当房主（扫描局域网世界）或当房客（输入邀请码）。
class TerracottaWaiting extends TerracottaReady {
  const TerracottaWaiting({required super.port, required super.index});
}

/// 正在扫描局域网世界。
class TerracottaHostScanning extends TerracottaReady {
  const TerracottaHostScanning({required super.port, required super.index});
}

/// 正在创建房间。
class TerracottaHostStarting extends TerracottaReady {
  const TerracottaHostStarting({required super.port, required super.index});
}

/// 房间已创建：`room` 为邀请码。
class TerracottaHostOk extends TerracottaReady {
  const TerracottaHostOk({
    required super.port,
    required super.index,
    required this.room,
    required this.profiles,
    this.profileIndex = -1,
  });

  /// 邀请码（房主念给朋友的一串数字）。
  final String room;

  /// 玩家列表。
  final List<TerracottaProfile> profiles;

  /// 玩家列表的版本号（用于判断是否可以原地刷新玩家列表）。
  final int profileIndex;

  /// 是否是 [previous] 的「玩家列表刷新」而非新房间。
  bool isForkOf(TerracottaState? previous) {
    if (previous is! TerracottaHostOk) return false;
    return index - previous.index <= profileIndex;
  }
}

/// 房客：正在连接房主。
class TerracottaGuestConnecting extends TerracottaReady {
  const TerracottaGuestConnecting({required super.port, required super.index});
}

/// 房客：正在建立虚拟网络（带难度估算）。
class TerracottaGuestStarting extends TerracottaReady {
  const TerracottaGuestStarting({
    required super.port,
    required super.index,
    required this.difficulty,
  });

  final TerracottaDifficulty difficulty;
}

/// 房客：已加入房间，`url` 为备用联机地址。
class TerracottaGuestOk extends TerracottaReady {
  const TerracottaGuestOk({
    required super.port,
    required super.index,
    required this.url,
    required this.profiles,
    this.profileIndex = -1,
  });

  /// 备用联机地址（`host:port`，粘贴到「添加服务器」里即可）。
  final String url;

  final List<TerracottaProfile> profiles;
  final int profileIndex;

  bool isForkOf(TerracottaState? previous) {
    if (previous is! TerracottaGuestOk) return false;
    return index - previous.index <= profileIndex;
  }
}

/// 运行期异常（房主/房客都可能命中）。
class TerracottaExceptionState extends TerracottaReady {
  const TerracottaExceptionState({
    required super.port,
    required super.index,
    required this.type,
  });

  final TerracottaExceptionType type;
}

/// 致命错误（可恢复的会给出「重试」按钮）。
class TerracottaFatal extends TerracottaState {
  const TerracottaFatal(this.type);

  final TerracottaFatalType type;

  /// 除「未知」外都可以通过重新下载/重启联机核心恢复。
  bool get isRecoverable => type != TerracottaFatalType.unknown;
}

/// `/state` JSON → 状态对象。
TerracottaStateParseResult parseTerracottaReadyJson(
  Map<String, dynamic> json, {
  required int port,
}) {
  final index = _asInt(json['index']) ?? -1;
  final state = json['state']?.toString() ?? '';
  final profilesJson = json['profiles'];

  List<TerracottaProfile> parseProfiles() {
    if (profilesJson is! List) return const [];
    return profilesJson
        .whereType<Map>()
        .map((e) => TerracottaProfile.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  switch (state) {
    case 'waiting':
      return TerracottaStateParseResult.ok(
        TerracottaWaiting(port: port, index: index),
      );
    case 'host-scanning':
      return TerracottaStateParseResult.ok(
        TerracottaHostScanning(port: port, index: index),
      );
    case 'host-starting':
      return TerracottaStateParseResult.ok(
        TerracottaHostStarting(port: port, index: index),
      );
    case 'host-ok':
      final room = json['room']?.toString();
      if (room == null || room.isEmpty) {
        return const TerracottaStateParseResult.error('host-ok 缺少 room 字段');
      }
      if (profilesJson is! List) {
        return const TerracottaStateParseResult.error('host-ok 缺少 profiles 字段');
      }
      return TerracottaStateParseResult.ok(
        TerracottaHostOk(
          port: port,
          index: index,
          room: room,
          profiles: parseProfiles(),
          profileIndex: _asInt(json['profile_index']) ?? -1,
        ),
      );
    case 'guest-connecting':
      return TerracottaStateParseResult.ok(
        TerracottaGuestConnecting(port: port, index: index),
      );
    case 'guest-starting':
      return TerracottaStateParseResult.ok(
        TerracottaGuestStarting(
          port: port,
          index: index,
          difficulty: _parseDifficulty(json['difficulty']),
        ),
      );
    case 'guest-ok':
      if (profilesJson is! List) {
        return const TerracottaStateParseResult.error(
          'guest-ok 缺少 profiles 字段',
        );
      }
      return TerracottaStateParseResult.ok(
        TerracottaGuestOk(
          port: port,
          index: index,
          url: json['url']?.toString() ?? '',
          profiles: parseProfiles(),
          profileIndex: _asInt(json['profile_index']) ?? -1,
        ),
      );
    case 'exception':
      final rawType = _asInt(json['type']);
      if (rawType == null ||
          rawType < 0 ||
          rawType >= TerracottaExceptionType.values.length) {
        return TerracottaStateParseResult.error('exception.type 越界: $rawType');
      }
      return TerracottaStateParseResult.ok(
        TerracottaExceptionState(
          port: port,
          index: index,
          type: TerracottaExceptionType.values[rawType],
        ),
      );
    default:
      return TerracottaStateParseResult.error('未知的联机状态: "$state"');
  }
}

/// 解析结果：成功带状态，失败带原因（调用方据此转成 Fatal/异常）。
class TerracottaStateParseResult {
  const TerracottaStateParseResult._(this.state, this.error);

  const TerracottaStateParseResult.ok(TerracottaReady state)
    : this._(state, null);

  const TerracottaStateParseResult.error(String error) : this._(null, error);

  final TerracottaReady? state;
  final String? error;

  bool get isOk => state != null;
}

TerracottaDifficulty _parseDifficulty(Object? raw) {
  final text = raw?.toString().toLowerCase();
  return switch (text) {
    'easiest' => TerracottaDifficulty.easiest,
    'simple' => TerracottaDifficulty.simple,
    'medium' => TerracottaDifficulty.medium,
    'tough' => TerracottaDifficulty.tough,
    _ => TerracottaDifficulty.unknown,
  };
}

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}
