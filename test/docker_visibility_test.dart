// Docker 设置可见性规则测试
// 规则：
// - 客户端 Windows + 节点 Windows（或平台未知）→ 不显示
// - 客户端 Windows + 节点 Linux/macOS 等 → 显示
// - 客户端 Linux/macOS 等其他平台 → 永久显示

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/utils/docker_visibility.dart';

void main() {
  group('客户端为 Windows', () {
    test('节点为 Windows（win32 / Windows_NT）时不显示', () {
      expect(shouldShowDockerSettings(nodePlatform: 'win32', clientIsWindows: true), isFalse);
      expect(shouldShowDockerSettings(nodePlatform: 'Windows_NT', clientIsWindows: true), isFalse);
      expect(shouldShowDockerSettings(nodePlatform: 'windows', clientIsWindows: true), isFalse);
    });

    test('节点平台未知时不显示', () {
      expect(shouldShowDockerSettings(nodePlatform: null, clientIsWindows: true), isFalse);
      expect(shouldShowDockerSettings(nodePlatform: '', clientIsWindows: true), isFalse);
    });

    test('节点为 Linux / macOS 等其他平台时显示', () {
      expect(shouldShowDockerSettings(nodePlatform: 'linux', clientIsWindows: true), isTrue);
      expect(shouldShowDockerSettings(nodePlatform: 'darwin', clientIsWindows: true), isTrue);
      expect(shouldShowDockerSettings(nodePlatform: 'freebsd', clientIsWindows: true), isTrue);
    });
  });

  group('客户端为 Linux / macOS 等其他平台', () {
    test('无论节点平台如何均永久显示', () {
      expect(
        shouldShowDockerSettings(nodePlatform: 'win32', clientIsWindows: false),
        isTrue,
      );
      expect(
        shouldShowDockerSettings(nodePlatform: 'linux', clientIsWindows: false),
        isTrue,
      );
      expect(
        shouldShowDockerSettings(nodePlatform: null, clientIsWindows: false),
        isTrue,
      );
      expect(
        shouldShowDockerSettings(nodePlatform: 'darwin', clientIsWindows: false),
        isTrue,
      );
    });
  });
}
