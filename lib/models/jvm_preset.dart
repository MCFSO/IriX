// JVM 优化参数预设
//
// 命名与取舍：
// - `none`  —— 不注入任何优化参数，保持用户命令原样（默认，行为最保守）。
// - `aikar` —— Aikar's Flags（面向 Minecraft 服务端的 G1 GC 调参组合），
//   参数逐项照抄官方推荐列表，顺序不变，便于与
//   https://docs.papermc.io/paper/aikars-flags 对照。
//
// 注入策略（见 [JvmArgs]）：只追加命令中尚不存在的参数，
// 用户手写的同名参数优先，不会被覆盖。

/// JVM 优化参数预设。
enum JvmPreset {
  /// 无：不注入优化参数。
  none,

  /// Aikar's Flags。
  aikar;

  /// 从数据库 / JSON 字符串反序列化，未知值回退为 [none]。
  static JvmPreset fromString(String? value) {
    for (final preset in JvmPreset.values) {
      if (preset.name == value) return preset;
    }
    return JvmPreset.none;
  }

  /// 该预设注入的参数列表（[none] 为空）。
  List<String> get flags => switch (this) {
    JvmPreset.none => const [],
    JvmPreset.aikar => aikarFlags,
  };

  /// 展示名（预设在 UI 上的名字）。
  String get displayName => switch (this) {
    JvmPreset.none => '无',
    JvmPreset.aikar => "Aikar's",
  };
}

/// Aikar's Flags（官方推荐组合，顺序与来源一致）。
const List<String> aikarFlags = [
  '-XX:+AlwaysPreTouch',
  '-XX:+DisableExplicitGC',
  '-XX:+ParallelRefProcEnabled',
  '-XX:+PerfDisableSharedMem',
  '-XX:+UnlockExperimentalVMOptions',
  '-XX:+UseG1GC',
  '-XX:G1HeapRegionSize=8M',
  '-XX:G1HeapWastePercent=5',
  '-XX:G1MaxNewSizePercent=40',
  '-XX:G1MixedGCCountTarget=4',
  '-XX:G1MixedGCLiveThresholdPercent=90',
  '-XX:G1NewSizePercent=30',
  '-XX:G1RSetUpdatingPauseTimePercent=5',
  '-XX:G1ReservePercent=20',
  '-XX:InitiatingHeapOccupancyPercent=15',
  '-XX:MaxGCPauseMillis=200',
  '-XX:MaxTenuringThreshold=1',
  '-XX:SurvivorRatio=32',
  '-Dusing.aikars.flags=https://mcflags.emc.gs',
  '-Daikars.new.flags=true',
];
