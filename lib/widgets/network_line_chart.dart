// 网络吞吐折线图
// 手写 CustomPaint 实现的轻量折线图（不引入图表依赖）：
// - 展示一组 NetworkSample 的总吞吐（下载 + 上传）
// - 鼠标悬停时高亮最近采样点并显示数值

import 'package:flutter/material.dart';

import '../state/cluster_state.dart';

/// 网络吞吐折线图。
class NetworkLineChart extends StatefulWidget {
  const NetworkLineChart({super.key, required this.samples, this.height = 140});

  final List<NetworkSample> samples;
  final double height;

  @override
  State<NetworkLineChart> createState() => _NetworkLineChartState();
}

class _NetworkLineChartState extends State<NetworkLineChart> {
  /// 悬停的采样点下标（-1 表示未悬停）。
  int _hoverIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = widget.samples;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: MouseRegion(
        onHover: (e) => _updateHover(e.localPosition.dx, samples.length),
        onExit: (_) => setState(() => _hoverIndex = -1),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _NetworkLinePainter(
                  samples: samples,
                  hoverIndex: _hoverIndex,
                  lineColor: theme.colorScheme.primary,
                  gridColor: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                  fillColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
            ),
            if (_hoverIndex >= 0 && _hoverIndex < samples.length)
              Positioned(
                left: 12,
                top: 8,
                child: _hoverLabel(theme, samples[_hoverIndex]),
              ),
          ],
        ),
      ),
    );
  }

  void _updateHover(double dx, int length) {
    if (length == 0) return;
    final index = (dx / context.size!.width * length).floor().clamp(
      0,
      length - 1,
    );
    if (index != _hoverIndex) {
      setState(() => _hoverIndex = index);
    }
  }

  Widget _hoverLabel(ThemeData theme, NetworkSample sample) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '↓ ${_fmtRate(sample.download)}  ↑ ${_fmtRate(sample.upload)}',
        style: theme.textTheme.labelSmall,
      ),
    );
  }

  static String _fmtRate(double v) {
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var x = v;
    var i = 0;
    while (x >= 1024 && i < units.length - 1) {
      x /= 1024;
      i++;
    }
    return '${x.toStringAsFixed(1)} ${units[i]}';
  }
}

/// 折线图绘制器。
class _NetworkLinePainter extends CustomPainter {
  _NetworkLinePainter({
    required this.samples,
    required this.hoverIndex,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
  });

  final List<NetworkSample> samples;
  final int hoverIndex;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final maxValue = _maxTotal();
    final stepY = maxValue <= 0 ? size.height / 4 : size.height / 4;
    final stepX =
        size.width / samples.length.clamp(1, samples.length).toDouble();

    // 网格横线（4 段）。
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height - i * stepY;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 折线路径 + 填充区域。
    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i * stepX;
      final y =
          size.height -
          (samples[i].total / (maxValue <= 0 ? 1 : maxValue)) * size.height;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo((samples.length - 1) * stepX, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // 悬停高亮。
    if (hoverIndex >= 0 && hoverIndex < samples.length) {
      final x = hoverIndex * stepX;
      final y =
          size.height -
          (samples[hoverIndex].total / (maxValue <= 0 ? 1 : maxValue)) *
              size.height;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()..color = lineColor.withValues(alpha: 0.4),
      );
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = lineColor);
    }
  }

  double _maxTotal() {
    var max = 0.0;
    for (final s in samples) {
      if (s.total > max) max = s.total;
    }
    return max;
  }

  @override
  bool shouldRepaint(covariant _NetworkLinePainter old) {
    return old.samples != samples || old.hoverIndex != hoverIndex;
  }
}
