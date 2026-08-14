import 'dart:io';

import 'package:deeplink_setup/deeplink_setup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _flutterManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="example">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('deeplink_configure_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('inserts autoVerify intent-filter inside MainActivity, not application',
      () async {
    final manifest = await _write(
      tmp,
      'android/app/src/main/AndroidManifest.xml',
      _flutterManifest,
    );

    final result = await ProjectConfigurator().configure(
      root: tmp.path,
      domain: 'example.com',
    );

    final text = await manifest.readAsString();
    expect(_changed(result), contains(p.normalize(manifest.path)));
    expect(text, contains('android:autoVerify="true"'));
    expect(text, contains('android:host="example.com"'));
    expect(text, contains('<!-- deeplink_setup:begin -->'));

    final activity = text.substring(
      text.indexOf('android:name=".MainActivity"'),
      text.indexOf('</activity>'),
    );
    expect(activity, contains('android:host="example.com"'));

    final beforeActivity = text.substring(0, text.indexOf('<activity'));
    expect(beforeActivity.contains('android:host="example.com"'), isFalse);

    final backup = File('${manifest.path}.deeplink_setup.bak');
    expect(await backup.exists(), isTrue);
    expect(await backup.readAsString(), _flutterManifest);
  });

  test('does not treat an application-level host as already configured',
      () async {
    await _write(
      tmp,
      'android/app/src/main/AndroidManifest.xml',
      '''
<manifest>
    <application>
        <intent-filter android:autoVerify="true">
            <data android:scheme="https" android:host="example.com" />
        </intent-filter>
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
    );

    await ProjectConfigurator()
        .configure(root: tmp.path, domain: 'example.com');
    final text = await File(
      p.join(tmp.path, 'android/app/src/main/AndroidManifest.xml'),
    ).readAsString();
    final activity = text.substring(
      text.indexOf('android:name=".MainActivity"'),
      text.indexOf('</activity>'),
    );
    expect(activity, contains('android:host="example.com"'));
  });

  test('is idempotent when the activity already has the host', () async {
    await _write(
      tmp,
      'android/app/src/main/AndroidManifest.xml',
      _flutterManifest,
    );
    final first = await ProjectConfigurator().configure(
      root: tmp.path,
      domain: 'example.com',
    );
    final second = await ProjectConfigurator().configure(
      root: tmp.path,
      domain: 'example.com',
    );
    expect(first.changed, isNotEmpty);
    expect(second.changed, isEmpty);
  });

  test('adds applinks to an existing entitlements file', () async {
    final entitlements = await _write(
      tmp,
      'ios/Runner/Runner.entitlements',
      '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
''',
    );

    final result = await ProjectConfigurator().configure(
      root: tmp.path,
      domain: 'example.com',
    );
    final text = await entitlements.readAsString();
    expect(_changed(result), contains(p.normalize(entitlements.path)));
    expect(text, contains('com.apple.developer.associated-domains'));
    expect(text, contains('applinks:example.com'));
    expect(
      await File('${entitlements.path}.deeplink_setup.bak').exists(),
      isTrue,
    );
  });

  test('creates Runner.entitlements and references it from the Xcode project',
      () async {
    await _write(
      tmp,
      'ios/Runner.xcodeproj/project.pbxproj',
      '''
buildSettings = {
				INFOPLIST_FILE = Runner/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
			};
''',
    );
    await Directory(p.join(tmp.path, 'ios', 'Runner')).create(recursive: true);

    final result = await ProjectConfigurator().configure(
      root: tmp.path,
      domain: 'example.com',
    );
    final entitlements = File(
      p.join(tmp.path, 'ios', 'Runner', 'Runner.entitlements'),
    );
    expect(await entitlements.exists(), isTrue);
    expect(await entitlements.readAsString(), contains('applinks:example.com'));
    expect(
      _changed(result),
      contains(p.normalize(entitlements.path)),
    );

    final pbx = await File(
      p.join(tmp.path, 'ios/Runner.xcodeproj/project.pbxproj'),
    ).readAsString();
    expect(
        pbx, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
  });

  test('warns when the manifest has no activity', () async {
    await _write(
      tmp,
      'android/app/src/main/AndroidManifest.xml',
      '<manifest><application></application></manifest>\n',
    );
    final result = await ProjectConfigurator().configure(
      root: tmp.path,
      domain: 'example.com',
    );
    expect(result.changed, isEmpty);
    expect(result.diagnostics.map((d) => d.code),
        contains('ANDROID_ACTIVITY_NOT_FOUND'));
  });
}

Iterable<String> _changed(ConfigureResult result) =>
    result.changed.map(p.normalize);

Future<File> _write(Directory root, String relative, String contents) async {
  final file = File(p.joinAll([root.path, ...relative.split('/')]));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
  return file;
}
