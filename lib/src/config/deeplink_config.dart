import 'dart:io';
import 'package:yaml/yaml.dart';

class DeeplinkConfig {
  DeeplinkConfig({
    required this.domain,
    this.androidPackage,
    String? androidSha256,
    this.iosBundleId,
    this.iosTeamId,
    List<String>? paths,
  })  : androidSha256 = normalizeSha256(androidSha256),
        paths = List.unmodifiable(paths ?? const ['/*']);

  final String domain;
  final String? androidPackage;
  final String? androidSha256;
  final String? iosBundleId;
  final String? iosTeamId;
  final List<String> paths;

  bool get hasCompleteAndroid =>
      androidPackage != null && androidSha256 != null;
  bool get hasCompleteIos => iosBundleId != null && iosTeamId != null;
  bool get hasPartialAndroid =>
      (androidPackage != null) != (androidSha256 != null);
  bool get hasPartialIos => (iosBundleId != null) != (iosTeamId != null);

  /// Accepts colon, hyphen, or compact hex and returns `AA:BB:...` uppercase.
  /// Returns null for empty input. Invalid length is still formatted so
  /// validation can report an invalid SHA-256.
  static String? normalizeSha256(String? value) {
    if (value == null) return null;
    final compact = value.trim().toUpperCase().replaceAll(
          RegExp(r'[^0-9A-F]'),
          '',
        );
    if (compact.isEmpty) return null;
    final pairs = <String>[];
    for (var i = 0; i + 1 < compact.length; i += 2) {
      pairs.add(compact.substring(i, i + 2));
    }
    if (compact.length.isOdd) {
      pairs.add(compact.substring(compact.length - 1));
    }
    return pairs.join(':');
  }

  static Future<DeeplinkConfig> load([
    String file = 'deeplink_config.yaml',
  ]) async {
    final f = File(file);
    if (!await f.exists()) {
      throw FileSystemException('Configuration file not found.', file);
    }
    return DeeplinkConfig.fromYaml(await f.readAsString());
  }

  factory DeeplinkConfig.fromYaml(String source) {
    final yaml = loadYaml(source);
    if (yaml is! YamlMap) {
      throw const FormatException('Root YAML value must be an object.');
    }
    final domain = yaml['domain'];
    if (domain is! String || domain.trim().isEmpty) {
      throw const FormatException('Missing required "domain".');
    }

    final android = yaml['android'];
    final ios = yaml['ios'];
    final rawPaths = yaml['paths'];
    final paths = <String>[];

    if (rawPaths != null) {
      if (rawPaths is! YamlList) {
        throw const FormatException('"paths" must be a YAML list.');
      }
      for (final value in rawPaths) {
        if (value is! String || value.trim().isEmpty) {
          throw const FormatException('Each path must be a non-empty string.');
        }
        paths.add(value.trim());
      }
    }

    return DeeplinkConfig(
      domain: domain.trim(),
      androidPackage: _value(android, 'package'),
      androidSha256: _value(android, 'sha256'),
      iosBundleId: _value(ios, 'bundle_id'),
      iosTeamId: _value(ios, 'team_id'),
      paths: paths.isEmpty ? const ['/*'] : paths,
    );
  }

  static String? _value(Object? parent, String key) {
    if (parent is! YamlMap) return null;
    final value = parent[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  String toYaml() {
    final b = StringBuffer()
      ..writeln('domain: $domain')
      ..writeln()
      ..writeln('android:');
    if (androidPackage != null) b.writeln('  package: $androidPackage');
    if (androidSha256 != null) b.writeln('  sha256: "$androidSha256"');
    b
      ..writeln()
      ..writeln('ios:');
    if (iosBundleId != null) b.writeln('  bundle_id: $iosBundleId');
    if (iosTeamId != null) b.writeln('  team_id: $iosTeamId');
    b
      ..writeln()
      ..writeln('paths:');
    for (final path in paths) {
      b.writeln('  - "$path"');
    }
    return b.toString();
  }
}
