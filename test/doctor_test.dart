import 'dart:io';

import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('deeplink_doctor_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('skips CDN and still runs local checks without iOS config', () async {
    final c = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
  sha256: "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
''');
    await AssociationGenerator.write(c, root: tmp.path);
    final client = MockClient((request) async {
      if (request.url.host.contains('cdn-apple')) {
        fail('Apple CDN should not be queried without iOS config');
      }
      return http.Response(
        AssociationGenerator.assetLinks(c),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final ds = await DoctorService().run(c, root: tmp.path, client: client);
    expect(ds.map((d) => d.code), contains('CDN_SKIPPED'));
    expect(ds.map((d) => d.code), contains('LOCAL_VALID'));
    expect(ds.map((d) => d.code), contains('ORIGIN_MATCH'));
  });

  test('includes origin vs Apple CDN warning in a full iOS doctor run',
      () async {
    final c = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');
    await AssociationGenerator.write(c, root: tmp.path);
    final origin = AssociationGenerator.aasa(c);
    final client = MockClient((request) async {
      final body = request.url.host.contains('cdn-apple')
          ? '{"applinks":{"details":[]}}'
          : origin;
      return http.Response(
        body,
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final ds = await DoctorService().run(c, root: tmp.path, client: client);
    expect(ds.map((d) => d.code), contains('APPLE_CDN_ORIGIN_MISMATCH'));
    expect(
      ds.where((d) => d.code == 'APPLE_CDN_ORIGIN_MISMATCH').single.isWarning,
      isTrue,
    );
  });
}
