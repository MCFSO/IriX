// 应用版本与语义化版本解析/比较测试
//
// 更新检查的正确性完全依赖这里的比较规则（`Stable-v1.3.0` 这类 tag 要能正确
// 解析、预发布版本要小于正式版），所以单独覆盖。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/app_version.dart';

void main() {
  group('SemVersion.tryParse', () {
    test('解析三段式版本', () {
      final v = SemVersion.tryParse('1.3.0')!;
      expect(v.major, 1);
      expect(v.minor, 3);
      expect(v.patch, 0);
      expect(v.isPreRelease, isFalse);
    });

    test('解析带 v 前缀与 Stable- 前缀的 tag', () {
      expect(SemVersion.tryParse('v1.2.0').toString(), '1.2.0');
      expect(SemVersion.tryParse('Stable-v1.3.0').toString(), '1.3.0');
      expect(SemVersion.tryParse('Stable-v1.0.1').toString(), '1.0.1');
    });

    test('缺失的段按 0 处理', () {
      expect(SemVersion.tryParse('1.3').toString(), '1.3.0');
      expect(SemVersion.tryParse('2').toString(), '2.0.0');
    });

    test('解析预发布与构建元数据', () {
      final v = SemVersion.tryParse('1.4.0-rc.1+build.7')!;
      expect(v.preRelease, ['rc', '1']);
      expect(v.build, 'build.7');
      expect(v.isPreRelease, isTrue);
    });

    test('无法解析时返回 null', () {
      expect(SemVersion.tryParse('Stable'), isNull);
      expect(SemVersion.tryParse(''), isNull);
      expect(SemVersion.tryParse(null), isNull);
    });
  });

  group('SemVersion 比较', () {
    SemVersion v(String s) => SemVersion.tryParse(s)!;

    test('按主/次/修订号升序', () {
      expect(v('1.9.9') < v('1.10.0'), isTrue);
      expect(v('1.3.0') < v('1.4.0'), isTrue);
      expect(v('2.0.0') > v('1.99.99'), isTrue);
    });

    test('缺失段等价于 0', () {
      expect(v('1.3') == v('1.3.0'), isTrue);
      expect(v('1.3').compareTo(v('1.3.0')), 0);
    });

    test('预发布版本小于同号正式版', () {
      expect(v('1.4.0-rc.1') < v('1.4.0'), isTrue);
      expect(v('1.4.0') > v('1.4.0-rc.1'), isTrue);
    });

    test('预发布标识符按 SemVer 规则比较', () {
      expect(v('1.4.0-rc.1') < v('1.4.0-rc.2'), isTrue);
      expect(v('1.4.0-rc.2') < v('1.4.0-rc.10'), isTrue);
      expect(v('1.4.0-alpha') < v('1.4.0-beta'), isTrue);
      // 数字标识符优先级低于字母标识符。
      expect(v('1.4.0-1') < v('1.4.0-alpha'), isTrue);
    });

    test('isNewerThan / isOlderThan', () {
      expect(v('1.4.0').isNewerThan(v('1.3.0')), isTrue);
      expect(v('1.3.0').isNewerThan(v('1.3.0')), isFalse);
      expect(v('1.3.0').isOlderThan(v('1.3.0')), isFalse);
    });
  });

  group('SemVersion.normalizeTag', () {
    test('剥离 tag 前缀', () {
      expect(SemVersion.normalizeTag('Stable-v1.3.0'), '1.3.0');
      expect(SemVersion.normalizeTag('v1.2.0'), '1.2.0');
    });

    test('无法解析时原样返回', () {
      expect(SemVersion.normalizeTag('Stable'), 'Stable');
    });
  });

  group('应用版本真源', () {
    test('kIrixAppVersion 可解析', () {
      final v = kIrixAppSemVersion;
      expect(v, isNotNull, reason: 'kIrixAppVersion=$kIrixAppVersion');
      expect(v!.isPreRelease, isFalse);
    });

    test('kIrixAppVersion 与 pubspec.yaml 的 version 一致', () {
      // 二者不一致会导致 OTA 误判（一直提示有更新 / 漏掉更新），
      // 发布时 pubspec 与 app_version.dart 必须一起改。
      final pubspec = File('pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);
      final line = pubspec
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
      expect(line, isNotEmpty, reason: 'pubspec.yaml 缺少 version:');
      final declared = line
          .substring('version:'.length)
          .split('+')
          .first
          .trim();
      expect(kIrixAppVersion, declared);
    });
  });
}
