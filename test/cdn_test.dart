import 'dart:convert';

import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final ios = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
  team_id: TEAM123
''');

  test('skips Apple CDN when iOS config is incomplete', () async {
    final c = DeeplinkConfig.fromYaml('domain: example.com\n');
    var fetched = false;
    final client = MockClient((request) async {
      fetched = true;
      return http.Response('{}', 200);
    });
    final ds = await CdnService().check(c, client: client);
    expect(fetched, isFalse);
    expect(ds.map((d) => d.code), ['CDN_SKIPPED']);
    expect(ds.where((d) => d.isError), isEmpty);
  });

  test('treats pretty vs minified AASA as a CDN match', () async {
    final pretty = AssociationGenerator.aasa(ios);
    final compact = jsonEncode(jsonDecode(pretty));
    final client = MockClient((request) async {
      final body = request.url.host.contains('cdn-apple') ? compact : pretty;
      return http.Response(
        body,
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final ds = await CdnService().check(ios, client: client);
    expect(ds.map((d) => d.code), contains('APPLE_CDN_MATCH'));
    expect(ds.where((d) => d.isWarning || d.isError), isEmpty);
  });

  test('warns when Apple CDN still has a different AASA than origin', () async {
    final origin = AssociationGenerator.aasa(ios);
    const stale = '{"applinks":{"details":[]}}';
    final client = MockClient((request) async {
      final body = request.url.host.contains('cdn-apple') ? stale : origin;
      return http.Response(
        body,
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final ds = await CdnService().check(ios, client: client);
    final mismatch =
        ds.where((d) => d.code == 'APPLE_CDN_ORIGIN_MISMATCH').single;
    expect(mismatch.isWarning, isTrue);
    expect(mismatch.isError, isFalse);
    expect(mismatch.message, contains('Your server:'));
    expect(
      mismatch.message,
      contains('https://example.com/.well-known/apple-app-site-association'),
    );
    expect(
      mismatch.message,
      contains('https://app-site-association.cdn-apple.com/a/v1/example.com'),
    );
    expect(mismatch.action, contains('24 hours'));
    expect(mismatch.action, contains('several days'));
    expect(mismatch.action, contains('cannot clear this cache'));
  });

  test('does not follow origin redirects', () async {
    final client = MockClient((request) async {
      return http.Response(
        '',
        302,
        headers: {'location': 'https://example.com/aasa'},
      );
    });
    final ds = await CdnService().check(ios, client: client);
    expect(ds.map((d) => d.code), contains('ORIGIN_AASA_REDIRECT'));
  });
}
