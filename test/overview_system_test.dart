// OverviewSystem 解析测试
// 验证磁盘 / 网络 / 系统版本字段的解析、回退与合并。

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/models/remote.dart';

void main() {
  test('解析磁盘/网络/版本字段', () {
    final sys = OverviewSystem.fromJson({
      'type': 'Linux',
      'release': '5.15.0-91-generic',
      'version': '22.04',
      'totalmem': 17179869184,
      'freemem': 8589934592,
      'cpuUsage': 0.3,
      'memUsage': 0.5,
      'diskusage': 0.6,
      'disktotal': 107374182400,
      'diskused': 64424509440,
      'networkDownload': 1048576,
      'networkUpload': 524288,
    });

    expect(sys.systemVersion, '22.04');
    expect(sys.hasDisk, isTrue);
    expect(sys.diskUsage, 0.6);
    expect(sys.diskTotal, 107374182400);
    expect(sys.hasNetwork, isTrue);
    expect(sys.networkDownload, 1048576);
  });

  test('缺字段回退默认值', () {
    final sys = OverviewSystem.fromJson({});
    expect(sys.systemVersion, '');
    expect(sys.hasDisk, isFalse);
    expect(sys.hasNetwork, isFalse);
  });

  test('systemVersion 回退 release', () {
    final sys = OverviewSystem.fromJson({
      'release': '5.15.0',
    });
    expect(sys.systemVersion, '5.15.0');
  });

  test('mergedWith 用其它实例填充缺失磁盘/网络', () {
    final panel = OverviewSystem.fromJson({
      'cpuUsage': 0.2,
      'memUsage': 0.4,
    });
    final daemon = OverviewSystem.fromJson({
      'diskusage': 0.7,
      'disktotal': 1000,
      'diskused': 700,
      'networkDownload': 2048,
      'networkUpload': 1024,
    });

    final merged = panel.mergedWith(daemon);
    expect(merged.hasDisk, isTrue);
    expect(merged.diskUsage, 0.7);
    expect(merged.hasNetwork, isTrue);
    expect(merged.networkDownload, 2048);
    // 已有字段不被覆盖
    expect(merged.cpuUsage, 0.2);
  });
}
