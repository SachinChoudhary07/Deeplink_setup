import 'dart:convert';
import 'dart:io';

import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _sha = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

void main() {
  final c = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
  sha256: "$_sha"
ios:
  bundle_id: com.example.app
  team_id: TEAM123
paths:
  - "/*"
''');

  test('assetlinks is valid JSON with canonical fingerprint', () {
    final value = jsonDecode(AssociationGenerator.assetLinks(c));
    expect(value[0]['target']['package_name'], 'com.example.app');
    expect(value[0]['target']['sha256_cert_fingerprints'], [_sha]);
  });

  test('AASA contains appID', () {
    final value = jsonDecode(AssociationGenerator.aasa(c));
    expect(value['applinks']['details'][0]['appIDs'], [
      'TEAM123.com.example.app',
    ]);
  });

  test('generation is deterministic', () {
    expect(
      AssociationGenerator.assetLinks(c),
      AssociationGenerator.assetLinks(c),
    );
    expect(AssociationGenerator.aasa(c), AssociationGenerator.aasa(c));
  });

  group('write', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('deeplink_setup_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('writes both files when Android and iOS are complete', () async {
      final files = await AssociationGenerator.write(c, root: tmp.path);
      expect(files.map((f) => p.basename(f.path)), [
        'assetlinks.json',
        'apple-app-site-association',
      ]);
      expect(
        await File(p.join(tmp.path, '.well-known', 'assetlinks.json')).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(tmp.path, '.well-known', 'apple-app-site-association'),
        ).exists(),
        isTrue,
      );
    });

    test('writes only assetlinks.json for Android-only config', () async {
      final androidOnly = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
  sha256: "$_sha"
''');
      final files = await AssociationGenerator.write(
        androidOnly,
        root: tmp.path,
      );
      expect(files.map((f) => p.basename(f.path)), ['assetlinks.json']);
      expect(
        await File(
          p.join(tmp.path, '.well-known', 'apple-app-site-association'),
        ).exists(),
        isFalse,
      );
    });

    test('writes only AASA for iOS-only config', () async {
      final iosOnly = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');
      final files = await AssociationGenerator.write(iosOnly, root: tmp.path);
      expect(files.map((f) => p.basename(f.path)), [
        'apple-app-site-association',
      ]);
      expect(
        await File(p.join(tmp.path, '.well-known', 'assetlinks.json')).exists(),
        isFalse,
      );
    });

    test('throws when a platform block is partial', () async {
      final partial = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');
      expect(
        () => AssociationGenerator.write(partial, root: tmp.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when neither platform is configured', () {
      final none = DeeplinkConfig.fromYaml('domain: example.com\n');
      expect(
        () => AssociationGenerator.write(none, root: tmp.path),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
