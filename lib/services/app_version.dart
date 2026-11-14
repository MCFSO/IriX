// 应用版本号与语义化版本（SemVer）比较
//
// 这里是**应用版本的唯一 Dart 侧真源**：OTA 更新检查（update_service.dart）、
// 设备绑定上报的 `appVersion`（device_auth.dart）以及设置页展示的版本都读同一
// 个常量，避免出现「界面显示 1.3.0、更新检查以为自己是 1.0.0」这类漂移。
//
// 约定：
// - `kIrixAppVersion` 必须与 `pubspec.yaml` 的 `version:` 前半段一致
//   （`test/app_version_test.dart` 会校验，不一致 CI 直接失败）；
// - 发布时两者一起改；CI 也可用 `--dart-define=IRIX_VERSION=x.y.z` 覆盖；
// - 只写三段式 `major.minor.patch`，预发布用 `-rc.1` 这样的后缀，
//   不要写 `v` 前缀（git tag 上的 `Stable-v` / `v` 前缀由
//   [SemVersion.normalizeTag] 负责剥离）。

/// 当前应用版本（三段式语义化版本，不含 `v` 前缀）。
///
/// 可用 `--dart-define=IRIX_VERSION=1.4.0` 在构建时覆盖。
const String kIrixAppVersion = String.fromEnvironment(
  'IRIX_VERSION',
  defaultValue: '1.3.0',
);

/// 构建号（对应 pubspec `version:` 的 `+` 之后部分），仅用于展示。
const String kIrixAppBuildNumber = String.fromEnvironment(
  'IRIX_BUILD_NUMBER',
  defaultValue: '1',
);

/// 展示用版本标签，如 `v1.3.0`。
String get kIrixAppVersionLabel => 'v$kIrixAppVersion';

/// 解析后的当前版本；解析失败时为 null（理论上不会发生）。
SemVersion? get kIrixAppSemVersion => SemVersion.tryParse(kIrixAppVersion);

/// 语义化版本（SemVer 2.0.0 的主体部分）。
///
/// 只实现更新检查需要的部分：
/// - 三段式数字比较（缺失的段按 0 处理，`1.3` == `1.3.0`）；
/// - 预发布后缀（`1.4.0-rc.1`）小于同号正式版，标识符按 SemVer 规则比较；
/// - 构建元数据（`+13`）只保留不参与比较。
class SemVersion implements Comparable<SemVersion> {
  const SemVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const <String>[],
    this.build = '',
  });

  /// 主版本号。
  final int major;

  /// 次版本号。
  final int minor;

  /// 修订号。
  final int patch;

  /// 预发布标识符（`1.4.0-rc.1` → `['rc', '1']`）。
  final List<String> preRelease;

  /// 构建元数据（`1.4.0+13` → `13`），不参与比较。
  final String build;

  /// 是否为预发布版本。
  bool get isPreRelease => preRelease.isNotEmpty;

  /// 匹配版本号主体的正则：允许前面带 `v` / `Stable-` 等任意非数字前缀，
  /// 数字段必须至少有一位，后续段可选。
  static final RegExp _pattern = RegExp(
    r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?',
  );

  /// 解析版本字符串；无法解析时返回 null。
  ///
  /// 接受 `1.3.0`、`v1.3.0`、`Stable-v1.3.0`、`1.4.0-rc.1+build.5` 等形式。
  static SemVersion? tryParse(String? input) {
    if (input == null) return null;
    final text = input.trim();
    if (text.isEmpty) return null;
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final major = int.tryParse(match.group(1) ?? '');
    if (major == null) return null;
    final pre = (match.group(4) ?? '')
        .split('.')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    return SemVersion(
      major: major,
      minor: int.tryParse(match.group(2) ?? '') ?? 0,
      patch: int.tryParse(match.group(3) ?? '') ?? 0,
      preRelease: pre,
      build: match.group(5) ?? '',
    );
  }

  /// 把 git tag / 发布名规范化为纯版本号字符串。
  ///
  /// `Stable-v1.3.0` → `1.3.0`；无法解析时原样返回。
  static String normalizeTag(String tag) {
    final parsed = tryParse(tag);
    return parsed?.toString() ?? tag.trim();
  }

  @override
  int compareTo(SemVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // SemVer §11：预发布版本优先级低于同号正式版。
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    final len = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < len; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      final an = int.tryParse(a);
      final bn = int.tryParse(b);
      if (an != null && bn != null) {
        if (an != bn) return an.compareTo(bn);
        continue;
      }
      // 数字标识符优先级低于字母标识符。
      if (an != null) return -1;
      if (bn != null) return 1;
      final cmp = a.compareTo(b);
      if (cmp != 0) return cmp;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  /// 本版本是否比 [other] 新。
  bool isNewerThan(SemVersion other) => compareTo(other) > 0;

  /// 本版本是否比 [other] 旧。
  bool isOlderThan(SemVersion other) => compareTo(other) < 0;

  bool operator >(SemVersion other) => isNewerThan(other);
  bool operator <(SemVersion other) => isOlderThan(other);
  bool operator >=(SemVersion other) => compareTo(other) >= 0;
  bool operator <=(SemVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is SemVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    final pre = preRelease.isEmpty ? '' : '-${preRelease.join('.')}';
    final meta = build.isEmpty ? '' : '+$build';
    return '$base$pre$meta';
  }
}
