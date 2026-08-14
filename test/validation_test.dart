import 'dart:convert';
import 'dart:io';

import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _sha = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('deeplink_validate_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('passes when generated files match the config', () async {
    final c = _both();
    await AssociationGenerator.write(c, root: tmp.path);
    final ds = await ValidationService().local(c, root: tmp.path);
    expect(ds.map((d) => d.code), containsAll(['LOCAL_MATCH', 'LOCAL_VALID']));
    expect(ds.where((d) => d.isError), isEmpty);
  });

  test('does not require Android files for an iOS-only config', () async {
    final c = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');
    await AssociationGenerator.write(c, root: tmp.path);
    final ds = await ValidationService().local(c, root: tmp.path);
    expect(ds.map((d) => d.code), isNot(contains('ASSETLINKS_CONFIG')));
    expect(ds.where((d) => d.isError), isEmpty);
    expect(ds.map((d) => d.code), contains('LOCAL_MATCH'));
  });

  test('reports missing generated files as errors', () async {
    final ds = await ValidationService().local(_both(), root: tmp.path);
    expect(ds.where((d) => d.code == 'FILE_MISSING').length, 2);
    expect(ds.where((d) => d.code == 'FILE_MISSING').every((d) => d.isError),
        isTrue);
    expect(ds.map((d) => d.code), isNot(contains('LOCAL_VALID')));
  });

  test('reports a stale generated file as an error', () async {
    final c = _both();
    await AssociationGenerator.write(c, root: tmp.path);
    await File(p.join(tmp.path, '.well-known', 'assetlinks.json'))
        .writeAsString('[]\n');
    final ds = await ValidationService().local(c, root: tmp.path);
    expect(
      ds.where((d) => d.code == 'LOCAL_MISMATCH' && d.isError),
      isNotEmpty,
    );
  });

  test('rejects an invalid domain and package', () async {
    final c = DeeplinkConfig(
      domain: 'not a domain',
      androidPackage: 'invalid',
      androidSha256: 'AA:BB',
    );
    final ds = await ValidationService().local(c, root: tmp.path);
    expect(ds.map((d) => d.code), contains('INVALID_DOMAIN'));
    expect(ds.map((d) => d.code), contains('INVALID_ANDROID_PACKAGE'));
    expect(ds.map((d) => d.code), contains('INVALID_SHA256'));
  });

  test('rejects partial platform blocks', () async {
    final android = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
''');
    final ios = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
''');
    expect(
      (await ValidationService().local(android, root: tmp.path))
          .map((d) => d.code),
      contains('INCOMPLETE_ANDROID'),
    );
    expect(
      (await ValidationService().local(ios, root: tmp.path)).map((d) => d.code),
      contains('INCOMPLETE_IOS'),
    );
  });

  test('rejects a domain-only config with no platforms', () async {
    final c = DeeplinkConfig.fromYaml('domain: example.com\n');
    final ds = await ValidationService().local(c, root: tmp.path);
    expect(ds.map((d) => d.code), contains('NO_PLATFORM_CONFIG'));
    expect(ds.any((d) => d.isError), isTrue);
  });

  group('live', () {
    test('matches origin JSON against generated config, even if minified',
        () async {
      final c = _both();
      final asset = AssociationGenerator.assetLinks(c);
      final aasa = AssociationGenerator.aasa(c);
      final client = MockClient((request) async {
        final name = request.url.pathSegments.last;
        final body = name == 'assetlinks.json'
            ? jsonEncode(jsonDecode(asset))
            : jsonEncode(jsonDecode(aasa));
        return http.Response(
          body,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final ds = await ValidationService().live(c, client: client);
      expect(ds.where((d) => d.code == 'ORIGIN_MATCH').length, 2);
      expect(ds.where((d) => d.isError), isEmpty);
    });

    test('fails when the origin file does not match generated config',
        () async {
      final c = _both();
      final client = MockClient((request) async {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final ds = await ValidationService().live(c, client: client);
      expect(
        ds.where((d) => d.code == 'ORIGIN_MISMATCH' && d.isError),
        isNotEmpty,
      );
    });

    test('fails on redirects instead of following them', () async {
      final c = _both();
      final client = MockClient((request) async {
        return http.Response(
          '',
          301,
          headers: {'location': 'https://cdn.example.com/assetlinks.json'},
        );
      });
      final ds = await ValidationService().live(c, client: client);
      expect(ds.map((d) => d.code), contains('HTTP_REDIRECT'));
      expect(ds.any((d) => d.code == 'ORIGIN_MATCH'), isFalse);
    });

    test('does not fetch Android when the config is iOS-only', () async {
      final c = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');
      final seen = <String>[];
      final client = MockClient((request) async {
        seen.add(request.url.path);
        return http.Response(
          AssociationGenerator.aasa(c),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final ds = await ValidationService().live(c, client: client);
      expect(seen, ['/.well-known/apple-app-site-association']);
      expect(ds.map((d) => d.code), contains('ORIGIN_MATCH'));
    });
  });
}

DeeplinkConfig _both() => DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
  sha256: "$_sha"
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');
