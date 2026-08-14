import 'dart:io';

import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _sha = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:'
    'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('deeplink_detect_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('detects applicationId from Groovy Gradle', () async {
    await _write(
      tmp,
      'android/app/build.gradle',
      '''
android {
  defaultConfig {
    applicationId "com.example.groovy"
  }
}
''',
    );
    final info =
        await ProjectDetector(environment: const {}).detect(root: tmp.path);
    expect(info.androidPackage, 'com.example.groovy');
  });

  test('detects applicationId from Kotlin Gradle and falls back to namespace',
      () async {
    await _write(
      tmp,
      'android/app/build.gradle.kts',
      '''
android {
  namespace = "com.example.namespace"
}
''',
    );
    final info =
        await ProjectDetector(environment: const {}).detect(root: tmp.path);
    expect(info.androidPackage, 'com.example.namespace');
  });

  test('reads debug keystore under USERPROFILE on Windows-style homes',
      () async {
    final home = Directory(p.join(tmp.path, 'win-home'));
    final keystore = File(p.join(home.path, '.android', 'debug.keystore'));
    await keystore.parent.create(recursive: true);
    await keystore.writeAsString('dummy');
    await _write(
        tmp, 'android/app/build.gradle', 'applicationId "com.example.app"\n');

    final info = await ProjectDetector(
      environment: {'USERPROFILE': home.path},
      runProcess: (exe, args) async {
        expect(exe, contains('keytool'));
        expect(args, contains(keystore.path));
        return ProcessResult(1, 0, 'SHA256: $_sha\n', '');
      },
    ).detect(root: tmp.path);

    expect(info.androidSha256, _sha);
    expect(info.diagnostics.where((d) => d.isWarning), isEmpty);
  });

  test('prefers HOME over USERPROFILE when both are set', () async {
    final home = Directory(p.join(tmp.path, 'unix-home'));
    final keystore = File(p.join(home.path, '.android', 'debug.keystore'));
    await keystore.parent.create(recursive: true);
    await keystore.writeAsString('dummy');
    await _write(
        tmp, 'android/app/build.gradle', 'applicationId "com.example.app"\n');

    final info = await ProjectDetector(
      environment: {
        'HOME': home.path,
        'USERPROFILE': p.join(tmp.path, 'other'),
      },
      runProcess: (exe, args) async {
        expect(args, contains(keystore.path));
        return ProcessResult(1, 0, 'SHA256: $_sha\n', '');
      },
    ).detect(root: tmp.path);

    expect(info.androidSha256, _sha);
  });

  test('warns when keytool is missing instead of failing', () async {
    await _write(
        tmp, 'android/app/build.gradle', 'applicationId "com.example.app"\n');
    await _write(tmp, 'android/app/debug.keystore', 'dummy');

    final info = await ProjectDetector(
      environment: const {},
      runProcess: (exe, args) {
        throw ProcessException(
            exe, args, 'The system cannot find the file specified', 2);
      },
    ).detect(root: tmp.path);

    expect(info.androidPackage, 'com.example.app');
    expect(info.androidSha256, isNull);
    expect(info.diagnostics.map((d) => d.code), contains('KEYTOOL_NOT_FOUND'));
    expect(
        info.diagnostics
            .where((d) => d.code == 'KEYTOOL_NOT_FOUND')
            .single
            .isWarning,
        isTrue);
    expect(info.diagnostics.where((d) => d.isError), isEmpty);
  });

  test('warns when the debug keystore is missing', () async {
    await _write(
        tmp, 'android/app/build.gradle', 'applicationId "com.example.app"\n');

    final info =
        await ProjectDetector(environment: const {}).detect(root: tmp.path);

    expect(info.androidSha256, isNull);
    expect(info.diagnostics.map((d) => d.code),
        contains('DEBUG_KEYSTORE_NOT_FOUND'));
  });

  test('detects iOS bundle id and team id from Xcode project', () async {
    await _write(
      tmp,
      'ios/Runner/Info.plist',
      '''
<key>CFBundleIdentifier</key>
<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
''',
    );
    await _write(
      tmp,
      'ios/Runner.xcodeproj/project.pbxproj',
      '''
PRODUCT_BUNDLE_IDENTIFIER = com.example.ios;
DEVELOPMENT_TEAM = TEAM123XYZ;
''',
    );

    final info =
        await ProjectDetector(environment: const {}).detect(root: tmp.path);
    expect(info.iosBundleId, 'com.example.ios');
    expect(info.iosTeamId, 'TEAM123XYZ');
  });

  test('warns when an iOS project has no team id', () async {
    await _write(
      tmp,
      'ios/Runner/Info.plist',
      '''
<key>CFBundleIdentifier</key>
<string>com.example.ios</string>
''',
    );

    final info =
        await ProjectDetector(environment: const {}).detect(root: tmp.path);
    expect(info.iosBundleId, 'com.example.ios');
    expect(info.iosTeamId, isNull);
    expect(info.diagnostics.map((d) => d.code), contains('TEAM_ID_NOT_FOUND'));
  });
}

Future<void> _write(Directory root, String relative, String contents) async {
  final file = File(p.join(root.path, relative));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}
