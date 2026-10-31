// 流式布局装箱
//
// 插件条目宽度随内容变化（图标 + 名称 + 类型徽章），Flutter 没有现成的
// 「高度固定、宽度自适应、自动换行、可虚拟化」的 sliver。这里的做法是：
//   1. 先测量每个条目的宽度（调用方负责测量并传入）；
//   2. 用贪心算法把它们装进若干行（保持原始顺序）；
//   3. 用 SliverList 按「行」虚拟化渲染——只构建视口内的行，
//      插件上千时也不会一次性创建上千个 Widget。
//
// 纯函数、无 Flutter 依赖，便于单测。

/// 按容器宽度把定宽子项装箱成多行。
class FlowPacker {
  const FlowPacker._();

  /// 把 [widths] 依次装入宽度不超过 [maxWidth] 的行。
  ///
  /// 行内相邻子项间距为 [spacing]；返回每一行包含的子项下标。
  /// 单个子项宽于 [maxWidth] 时独占一行（由调用方保证名称已截断）。
  static List<List<int>> pack(
    List<double> widths, {
    required double maxWidth,
    required double spacing,
  }) {
    final rows = <List<int>>[];
    var current = <int>[];
    var used = 0.0;

    for (var i = 0; i < widths.length; i++) {
      final width = widths[i];
      final needed = current.isEmpty ? width : used + spacing + width;
      if (current.isNotEmpty && needed > maxWidth) {
        rows.add(current);
        current = <int>[i];
        used = width;
      } else {
        current.add(i);
        used = needed;
      }
    }
    if (current.isNotEmpty) rows.add(current);
    return rows;
  }
}
