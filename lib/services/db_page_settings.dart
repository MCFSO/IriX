// 数据库浏览分页设置 - 纯内存
// 每页行数仅保存在内存中，不持久化到磁盘

/// 数据库数据浏览的分页设置服务。
///
/// 控制"数据库 → 表数据浏览"时每页显示的行数。
/// 仅存于内存，应用重启后恢复默认值。
class DbPageSettings {
  /// 默认每页行数。
  static const int defaultPageSize = 50;

  /// 每页行数下限。
  static const int minPageSize = 10;

  /// 每页行数上限。
  static const int maxPageSize = 500;

  /// 当前每页行数（内存值，不持久化）。
  static int pageSize = defaultPageSize;

  /// 设置每页行数，自动 clamp 到合法区间。
  static void setPageSize(int value) {
    pageSize = value.clamp(minPageSize, maxPageSize);
  }
}
