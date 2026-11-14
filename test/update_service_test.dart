// OTA 更新：GitHub Release 解析与平台安装包选择测试
//
// 这里不发起真实网络请求（HTTP 全部走 Rust FFI，集成测试见
// test/http_ffi_test.dart），只覆盖纯函数部分：
// - Release / Asset JSON 解析（含真实 API 的 `Stable-v1.3.0` 形态与 draft 过滤）；
// - 平台 + 架构的安装包打分选择；
// - 大小格式化。
//
// 反例都来自真实发布：v1.3.0 同时上传了 exe/msix/zip、AppImage/deb/rpm/zip、
// dmg/zip，选错会导致 Windows 装到 zip、Linux 下到 rpm。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/models/update_info.dart';
import 'package:irix/services/update_service.dart';

/// 真实 v1.3.0 发布的精简版 JSON（字段取自 GitHub API）。
Map<String, dynamic> releaseJson({
  String tag = 'Stable-v1.3.0',
  String name = 'v1.3.0',
  bool draft = false,
  bool prerelease = false,
  List<String> assetNames = const [
    'irix-1.3.0-windows-x64.exe',
    'irix-1.3.0-windows-x64.msix',
    'irix-1.3.0-windows-x64.zip',
    'irix-1.3.0-linux-x64.AppImage',
    'irix-1.3.0-linux-x64.deb',
    'irix-1.3.0-linux-x64.rpm',
    'irix-1.3.0-linux-x64.zip',
    'irix-1.3.0-macOS-arm64.dmg',
    'irix-1.3.0-macOS-arm64.zip',
  ],
  String? digest =
      'sha256:f190066c49a1bd6826d00c6a76369c1dc3e951ff5245fe1101d020eb3d6933f9',
}) {
  return {
    'tag_name': tag,
    'name': name,
    'draft': draft,
    'prerelease': prerelease,
    'published_at': '2026-11-01T00:08:42Z',
    'html_url': 'https://github.com/MCFSO/IriX/releases/tag/$tag',
    'body': '# IriX 1.3.0\n- 设备绑定\n',
    'assets': [
      for (final assetName in assetNames)
        {
          'name': assetName,
          'browser_download_url':
              'https://github.com/MCFSO/IriX/releases/download/$tag/$assetName',
          'size': 26032108,
          'digest': ?digest,
        },
    ],
  };
}

void main() {
  group('UpdateRelease.fromJson', () {
    test('解析 Stable-v 前缀 tag 与资源列表', () {
      final release = UpdateRelease.fromJson(releaseJson())!;
      expect(release.version.toString(), '1.3.0');
      expect(release.tagName, 'Stable-v1.3.0');
      expect(release.versionLabel, 'v1.3.0');
      expect(release.prerelease, isFalse);
      expect(release.assets, hasLength(9));
      expect(release.publishedAt, DateTime.utc(2026, 11, 1, 0, 8, 42));
      expect(release.notes, contains('设备绑定'));
      expect(release.assets.first.sha256, startsWith('f190066c'));
    });

    test('draft 发布被忽略', () {
      expect(UpdateRelease.fromJson(releaseJson(draft: true)), isNull);
    });

    test('tag 无法解析版本号时被忽略（如 Stable）', () {
      expect(
        UpdateRelease.fromJson(releaseJson(tag: 'Stable', name: 'Stable')),
        isNull,
      );
    });

    test('预发布标记可从 prerelease 或版本号后缀识别', () {
      expect(
        UpdateRelease.fromJson(releaseJson(prerelease: true))!.prerelease,
        isTrue,
      );
      expect(
        UpdateRelease.fromJson(
          releaseJson(tag: 'v1.4.0-rc.1', name: 'v1.4.0-rc.1'),
        )!.prerelease,
        isTrue,
      );
    });

    test('digest 只接受 sha256', () {
      final sha512 = UpdateRelease.fromJson(
        releaseJson(digest: 'sha512:${'a' * 128}'),
      )!;
      expect(sha512.assets.first.sha256, isNull);
      final malformed = UpdateRelease.fromJson(releaseJson(digest: 'sha256:zz'))!;
      expect(malformed.assets.first.sha256, isNull);
    });

    test('识别 SHA256SUMS 校验和清单', () {
      final release = UpdateRelease.fromJson(
        releaseJson(
          assetNames: const [
            'irix-1.3.0-windows-x64.exe',
            'SHA256SUMS-1.3.0.txt',
          ],
        ),
      )!;
      expect(release.checksumAsset?.name, 'SHA256SUMS-1.3.0.txt');
    });
  });

  group('UpdateService.selectAsset', () {
    List<UpdateAsset> assetsOf(Map<String, dynamic> json) {
      final assets = (json['assets'] as List)
          .cast<Map<String, dynamic>>()
          .map(UpdateAsset.fromJson)
          .whereType<UpdateAsset>()
          .toList();
      return assets;
    }

    final assets = assetsOf(releaseJson());

    test('Windows 优先安装程序 exe，而不是 msix / zip', () {
      final picked = UpdateService.selectAsset(
        assets: assets,
        platform: 'windows',
        arch: 'x64',
      );
      expect(picked?.name, 'irix-1.3.0-windows-x64.exe');
    });

    test('macOS 优先 dmg', () {
      final picked = UpdateService.selectAsset(
        assets: assets,
        platform: 'macos',
        arch: 'arm64',
      );
      expect(picked?.name, 'irix-1.3.0-macOS-arm64.dmg');
    });

    test('Linux 在 AppImage 内运行时选 AppImage', () {
      final picked = UpdateService.selectAsset(
        assets: assets,
        platform: 'linux',
        arch: 'x64',
        hasAppImage: true,
      );
      expect(picked?.name, 'irix-1.3.0-linux-x64.AppImage');
    });

    test('Linux 未以 AppImage 运行时按发行版选 deb / rpm', () {
      final deb = UpdateService.selectAsset(
        assets: assets,
        platform: 'linux',
        arch: 'x64',
        isDebLike: true,
      );
      expect(deb?.name, 'irix-1.3.0-linux-x64.deb');
      final rpm = UpdateService.selectAsset(
        assets: assets,
        platform: 'linux',
        arch: 'x64',
        isRpmLike: true,
      );
      expect(rpm?.name, 'irix-1.3.0-linux-x64.rpm');
    });

    test('架构不匹配的包被降权（arm64 优先 arm64 包）', () {
      final mixed = assetsOf(
        releaseJson(
          assetNames: const [
            'irix-1.3.0-windows-x64.exe',
            'irix-1.3.0-windows-arm64.exe',
          ],
        ),
      );
      expect(
        UpdateService.selectAsset(
          assets: mixed,
          platform: 'windows',
          arch: 'arm64',
        )?.name,
        'irix-1.3.0-windows-arm64.exe',
      );
      expect(
        UpdateService.selectAsset(
          assets: mixed,
          platform: 'windows',
          arch: 'x64',
        )?.name,
        'irix-1.3.0-windows-x64.exe',
      );
    });

    test('没有匹配平台时返回 null（调用方引导去发布页）', () {
      final dmgOnly = assetsOf(
        releaseJson(assetNames: const ['irix-1.3.0-macOS-arm64.dmg']),
      );
      expect(
        UpdateService.selectAsset(
          assets: dmgOnly,
          platform: 'windows',
          arch: 'x64',
        ),
        isNull,
      );
    });

    test('校验和清单不会被当成安装包', () {
      final withChecksum = assetsOf(
        releaseJson(
          assetNames: const ['SHA256SUMS-1.3.0.txt', 'irix-1.3.0-windows-x64.exe'],
        ),
      );
      expect(
        UpdateService.selectAsset(
          assets: withChecksum,
          platform: 'windows',
          arch: 'x64',
        )?.name,
        'irix-1.3.0-windows-x64.exe',
      );
    });
  });

  group('UpdateInfo', () {
    test('展示用版本标签', () {
      final release = UpdateRelease.fromJson(releaseJson())!;
      final info = UpdateInfo(
        release: release,
        currentVersion: release.version,
        asset: release.assets.first,
      );
      expect(info.versionLabel, 'v1.3.0');
      expect(info.transitionLabel, 'v1.3.0 → v1.3.0');
      expect(info.hasAsset, isTrue);
    });
  });

  group('formatBytes', () {
    test('按单位换算', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(26032108), '24.8 MB');
    });
  });

  group('Cloudflare Worker 更新源', () {
    test('normalizeFeedUrl：空值表示用官方源', () {
      expect(UpdateService.normalizeFeedUrl(''), '');
      expect(UpdateService.normalizeFeedUrl('   '), '');
    });

    test('normalizeFeedUrl：根地址补 /api/releases', () {
      expect(
        UpdateService.normalizeFeedUrl('https://irix.example.workers.dev'),
        'https://irix.example.workers.dev/api/releases',
      );
      expect(
        UpdateService.normalizeFeedUrl('irix.example.workers.dev/'),
        'https://irix.example.workers.dev/api/releases',
      );
    });

    test('normalizeFeedUrl：完整地址原样保留', () {
      const feed = 'https://feed.example.com/api/releases';
      expect(UpdateService.normalizeFeedUrl(feed), feed);
      expect(
        UpdateService.normalizeFeedUrl('https://feed.example.com/api/latest/?x=1'),
        'https://feed.example.com/api/latest',
      );
      expect(
        UpdateService.normalizeFeedUrl('https://cdn.example.com/manifest.json'),
        'https://cdn.example.com/manifest.json',
      );
    });

    test('默认内置源是项目自建的 Cloudflare Worker', () {
      // 已部署：https://update.mcfso.org（workers/update-feed，绑自有域名，
      // 因为 *.workers.dev 在国内常被 DNS 污染）。
      expect(UpdateService.defaultFeedUrl, 'https://update.mcfso.org');
      expect(UpdateService.buildTimeFeedUrl, UpdateService.defaultFeedUrl);
      expect(
        UpdateService.feedCandidates(configured: '').first,
        'https://update.mcfso.org/api/releases',
      );
      expect(
        UpdateService.feedCandidates(configured: '').last,
        UpdateService.githubFeedUrl,
      );
    });

    test('feedCandidates：自定义 → 构建内置 → GitHub 兜底', () {
      final feeds = UpdateService.feedCandidates(
        configured: 'https://irix.example.workers.dev',
        buildTime: 'https://builtin.example.workers.dev',
      );
      expect(feeds, [
        'https://irix.example.workers.dev/api/releases',
        'https://builtin.example.workers.dev/api/releases',
        UpdateService.githubFeedUrl,
      ]);
      // GitHub 始终在最后，作为兜底
      expect(feeds.last, contains('api.github.com'));
    });

    test('feedCandidates：未配置时只剩官方源（或构建内置源）', () {
      expect(
        UpdateService.feedCandidates(configured: '', buildTime: ''),
        [UpdateService.githubFeedUrl],
      );
      expect(
        UpdateService.feedCandidates(configured: '', buildTime: ''),
        hasLength(1),
      );
    });

    test('feedCandidates：去重（配置与内置相同）', () {
      final feeds = UpdateService.feedCandidates(
        configured: 'https://same.example.workers.dev',
        buildTime: 'https://same.example.workers.dev/',
      );
      expect(feeds.where((f) => f.contains('same.example')).length, 1);
    });

    test('parseReleasesPayload：Worker 的 {releases:[...]} 形态', () {
      final body = jsonEncode({
        'source': {'owner': 'MCFSO', 'repo': 'IriX'},
        'generated_at': '2026-12-01T00:00:00Z',
        'releases': [releaseJson()],
      });
      final releases = UpdateService.parseReleasesPayload(body);
      expect(releases, hasLength(1));
      expect(releases.first.version.toString(), '1.3.0');
      expect(releases.first.tagName, 'Stable-v1.3.0');
      expect(
        releases.first.assets.first.name,
        'irix-1.3.0-windows-x64.exe',
      );
      expect(releases.first.assets.first.sha256, startsWith('f190066c'));
    });

    test('parseReleasesPayload：GitHub 原始数组与 {data:[...]}、单条 release', () {
      expect(
        UpdateService.parseReleasesPayload(jsonEncode([releaseJson()])).single
            .version
            .toString(),
        '1.3.0',
      );
      expect(
        UpdateService.parseReleasesPayload(
          jsonEncode({
            'data': [releaseJson()],
          }),
        ).single.version.toString(),
        '1.3.0',
      );
      expect(
        UpdateService.parseReleasesPayload(
          jsonEncode({'release': releaseJson()}),
        ).single.version.toString(),
        '1.3.0',
      );
    });

    test('Worker 改写后的 /dl 下载地址被原样采用', () {
      final payload = releaseJson();
      final rebuilt = <Map<String, dynamic>>[
        for (final item in payload['assets'] as List)
          Map<String, dynamic>.from(item as Map),
      ];
      rebuilt[0]['browser_download_url'] =
          'https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe';
      payload['assets'] = rebuilt;

      final release = UpdateService.parseReleasesPayload(
        jsonEncode({
          'releases': [payload],
        }),
      ).single;
      final asset = UpdateService.selectAsset(
        assets: release.assets,
        platform: 'windows',
        arch: 'x64',
      )!;
      expect(asset.name, 'irix-1.3.0-windows-x64.exe');
      expect(
        asset.url,
        'https://feed.example.com/dl/Stable-v1.3.0/irix-1.3.0-windows-x64.exe',
        reason: '下载必须走 Worker，而不是绕过它直连 GitHub',
      );
      expect(asset.sha256, startsWith('f190066c'));
    });

    test('parseReleasesPayload：预发布过滤与非法负载', () {      final pre = releaseJson(tag: 'v1.4.0-rc.1', name: 'v1.4.0-rc.1');
      expect(
        UpdateService.parseReleasesPayload(jsonEncode([pre])),
        isEmpty,
        reason: '默认不含预发布',
      );
      expect(
        UpdateService.parseReleasesPayload(
          jsonEncode([pre]),
          includePrerelease: true,
        ),
        hasLength(1),
      );

      expect(
        () => UpdateService.parseReleasesPayload('not json'),
        throwsA(isA<UpdateException>()),
      );
      expect(
        () => UpdateService.parseReleasesPayload('{"foo":1}'),
        throwsA(isA<UpdateException>()),
      );
      expect(
        () => UpdateService.parseReleasesPayload('"text"'),
        throwsA(isA<UpdateException>()),
      );
    });
  });
}
