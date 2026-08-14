import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:test/test.dart';

const _canonicalSha = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

void main() {
  test('parses configuration', () {
    final c = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
  sha256: "AA:BB"
ios:
  bundle_id: com.example.app
  team_id: TEAM
''');
    expect(c.domain, 'example.com');
    expect(c.androidPackage, 'com.example.app');
    expect(c.iosTeamId, 'TEAM');
  });

  test('requires domain', () {
    expect(
      () => DeeplinkConfig.fromYaml('android: {}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('normalizes SHA-256 from colon, hyphen, and compact hex', () {
    const compact =
        'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899';
    const hyphenated = 'aa-bb-cc-dd-ee-ff-00-11-22-33-44-55-66-77-88-99-'
        'aa-bb-cc-dd-ee-ff-00-11-22-33-44-55-66-77-88-99';

    expect(
      DeeplinkConfig.normalizeSha256(_canonicalSha.toLowerCase()),
      _canonicalSha,
    );
    expect(DeeplinkConfig.normalizeSha256(compact), _canonicalSha);
    expect(DeeplinkConfig.normalizeSha256(hyphenated), _canonicalSha);
    expect(DeeplinkConfig.normalizeSha256('  $_canonicalSha  '), _canonicalSha);
  });

  test('treats missing platform blocks as incomplete, not present', () {
    final c = DeeplinkConfig.fromYaml('domain: example.com\n');
    expect(c.hasCompleteAndroid, isFalse);
    expect(c.hasCompleteIos, isFalse);
    expect(c.hasPartialAndroid, isFalse);
    expect(c.hasPartialIos, isFalse);
  });

  test('detects partial Android and iOS blocks', () {
    final androidOnly = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
''');
    expect(androidOnly.hasPartialAndroid, isTrue);
    expect(androidOnly.hasCompleteAndroid, isFalse);

    final iosOnly = DeeplinkConfig.fromYaml('''
domain: example.com
ios:
  bundle_id: com.example.app
''');
    expect(iosOnly.hasPartialIos, isTrue);
    expect(iosOnly.hasCompleteIos, isFalse);
  });

  test('fromYaml stores a canonical SHA-256 fingerprint', () {
    final c = DeeplinkConfig.fromYaml('''
domain: example.com
android:
  package: com.example.app
  sha256: "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
''');
    expect(c.androidSha256, _canonicalSha);
    expect(c.hasCompleteAndroid, isTrue);
  });

  test('toYaml writes team_id placeholder when bundle_id is known', () {
    final yaml = DeeplinkConfig(
      domain: 'example.com',
      iosBundleId: 'com.example.app',
    ).toYaml();
    expect(yaml, contains('bundle_id: com.example.app'));
    expect(yaml, contains('team_id: YOUR_TEAM_ID'));
    expect(yaml, contains('Apple Developer'));
  });
}
