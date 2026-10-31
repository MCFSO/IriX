// 堆内存分配算法（移植自 HMCL）
//
// 两个来源，各自独立：
//   1. GameSettings.SUGGESTED_MEMORY —— 手动模式的默认推荐值
//        total >= 32 GiB            → 8192 MiB
//        否则 max(round(total/4/128)*128, 256) MiB
//   2. HMCLGameRepository.getAutoAllocatedMemory —— 自动模式的堆上限
//        usable = 可用内存 - 512 MiB（留给堆外与启动器自身）
//        usable <= 8 GiB ? usable * 0.8
//                        : min(8 GiB * 0.8 + (usable - 8 GiB) * 0.2, 16 GiB)
//
// 两点约定：
// - 结果按 128 MiB 向下取整：JVM 对 -Xmx 的实际取整粒度与 G1 region 相关，
//   取整后显示值与实际堆更接近，也避免出现 6143M 这类怪值。
// - 自动模式永远不超过「可用内存」，避免在低内存机器上把堆开爆。

/// 128 MiB 对齐粒度。
const int _granularityMb = 128;

/// 自动模式为堆外内存与启动器自身预留的空间（MiB）。
const int _autoReserveMb = 512;

/// 自动模式上限（MiB）。
const int _autoCapMb = 16 * 1024;

/// 自动模式的拐点（MiB）。
const int _autoThresholdMb = 8 * 1024;

/// 手动模式的最小可配置值（MiB）——低于此值任何服务端都无法启动。
const int minMemoryMb = 512;

/// 堆内存分配计算。
class MemoryAllocator {
  const MemoryAllocator._();

  /// 手动模式的默认推荐值（对应 HMCL `GameSettings.SUGGESTED_MEMORY`）。
  ///
  /// [totalMemoryMb] 为物理内存总量。
  static int suggestedMemoryMb(int totalMemoryMb) {
    if (totalMemoryMb >= 32 * 1024) return 8192;
    final quarter = (totalMemoryMb / 4.0 / 128.0).round() * 128;
    final value = quarter < 256 ? 256 : quarter;
    return value;
  }

  /// 自动模式的堆上限（对应 HMCL `getAutoAllocatedMemory`）。
  ///
  /// [availableBytes] 为当前可用物理内存；返回值单位 MiB。
  static int autoMemoryMb(int availableBytes) {
    final availableMb = availableBytes ~/ (1024 * 1024);
    final usable = availableMb - _autoReserveMb;
    if (usable <= 0) {
      // 可用内存不足以扣预留：直接按可用量给，且不低于最小值。
      return _alignDown(availableMb < minMemoryMb ? minMemoryMb : availableMb);
    }

    int suggested;
    if (usable <= _autoThresholdMb) {
      suggested = (usable * 0.8).floor();
    } else {
      final extra = ((usable - _autoThresholdMb) * 0.2).floor();
      suggested = (_autoThresholdMb * 0.8).floor() + extra;
      if (suggested > _autoCapMb) suggested = _autoCapMb;
    }

    if (suggested < minMemoryMb) suggested = minMemoryMb;
    return _alignDown(suggested);
  }

  /// 手动模式的取值上限：可用内存扣预留（不低于最小值）。
  static int manualUpperBoundMb(int availableBytes) {
    final availableMb = availableBytes ~/ (1024 * 1024);
    final usable = availableMb - _autoReserveMb;
    final bound = usable < minMemoryMb ? minMemoryMb : usable;
    return _alignUp(bound);
  }

  /// 把任意输入夹到 [minMemoryMb] - [upperBoundMb] 并对齐到 128 MiB。
  static int clampMb(int valueMb, {required int upperBoundMb}) {
    final upper = upperBoundMb < minMemoryMb ? minMemoryMb : upperBoundMb;
    final clamped = valueMb.clamp(minMemoryMb, upper);
    return _alignDown(clamped);
  }

  static int _alignDown(int valueMb) {
    final aligned = (valueMb ~/ _granularityMb) * _granularityMb;
    return aligned < minMemoryMb ? minMemoryMb : aligned;
  }

  static int _alignUp(int valueMb) {
    final aligned =
        ((valueMb + _granularityMb - 1) ~/ _granularityMb) * _granularityMb;
    return aligned < minMemoryMb ? minMemoryMb : aligned;
  }
}
