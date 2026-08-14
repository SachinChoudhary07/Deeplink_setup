import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic.dart';

class ConfigureResult {
  const ConfigureResult({
    this.changed = const [],
    this.diagnostics = const [],
  });

  final List<String> changed;
  final List<Diagnostic> diagnostics;
}

class ProjectConfigurator {
  Future<ConfigureResult> configure({
    String root = '.',
    required String domain,
    List<String> paths = const ['/*'],
  }) async {
    final changed = <String>[];
    final diagnostics = <Diagnostic>[];

    final manifest = File(
      p.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (await manifest.exists()) {
      final original = await manifest.readAsString();
      final updated = patchAndroidManifest(original, domain, paths: paths);
      if (updated == null) {
        diagnostics.add(
          const Diagnostic(
            severity: Severity.warning,
            code: 'ANDROID_ACTIVITY_NOT_FOUND',
            message:
                'AndroidManifest.xml has no activity that can receive App Links.',
            action:
                'Add an exported activity (Flutter: .MainActivity), then re-run configure.',
          ),
        );
      } else if (updated != original) {
        await _backup(manifest);
        await manifest.writeAsString(updated);
        changed.add(manifest.path);
      }
    }

    final iosChanged = await _configureIos(root, domain, diagnostics);
    changed.addAll(iosChanged);

    if (changed.isEmpty &&
        diagnostics.isEmpty &&
        !await manifest.exists() &&
        !await Directory(p.join(root, 'ios')).exists()) {
      diagnostics.add(
        const Diagnostic(
          severity: Severity.info,
          code: 'NO_PLATFORM_FILES',
          message: 'No AndroidManifest.xml or iOS project files were found.',
        ),
      );
    }

    return ConfigureResult(
      changed: List.unmodifiable(changed),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  /// Returns null when there is no safe activity to edit.
  static String? patchAndroidManifest(
    String text,
    String domain, {
    List<String> paths = const ['/*'],
  }) {
    final activities = _activities(text);
    if (activities.isEmpty) return null;

    if (activities.any((a) => _hasHost(a.body, domain))) return text;

    final target = _pickActivity(activities);
    final block = _androidBlock(domain, paths, '${target.closeIndent}    ');
    return text.replaceRange(target.closeStart, target.closeStart, block);
  }

  static String patchIosEntitlements(String text, String domain) {
    if (text.contains('applinks:$domain')) return text;

    if (text.contains('com.apple.developer.associated-domains')) {
      final keyAt = text.indexOf('com.apple.developer.associated-domains');
      final close = text.indexOf('</array>', keyAt);
      if (close < 0) return text;
      return '${text.substring(0, close)}    <string>applinks:$domain</string>\n${text.substring(close)}';
    }

    final closePlist = text.lastIndexOf('</dict>');
    if (closePlist < 0) return text;
    const block = '''
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:__DOMAIN__</string>
    </array>
''';
    return text.substring(0, closePlist) +
        block.replaceAll('__DOMAIN__', domain) +
        text.substring(closePlist);
  }

  Future<List<String>> _configureIos(
    String root,
    String domain,
    List<Diagnostic> diagnostics,
  ) async {
    final changed = <String>[];
    final runnerDir = Directory(p.join(root, 'ios', 'Runner'));
    var entitlementsPath = await _findEntitlements(root);

    if (entitlementsPath == null) {
      if (!await runnerDir.exists()) {
        if (await Directory(p.join(root, 'ios')).exists()) {
          diagnostics.add(
            const Diagnostic(
              severity: Severity.warning,
              code: 'IOS_ENTITLEMENTS_NOT_FOUND',
              message: 'No iOS entitlements file was found.',
              action:
                  'Add Associated Domains in Xcode, or create ios/Runner/Runner.entitlements.',
            ),
          );
        }
        return changed;
      }
      entitlementsPath = p.join(root, 'ios', 'Runner', 'Runner.entitlements');
      await File(entitlementsPath).writeAsString(_newEntitlements(domain));
      changed.add(entitlementsPath);
      final pbx = File(
        p.join(root, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
      );
      if (await pbx.exists()) {
        final original = await pbx.readAsString();
        final updated = _patchPbxproj(original);
        if (updated != original) {
          await _backup(pbx);
          await pbx.writeAsString(updated);
          changed.add(pbx.path);
        } else if (!RegExp(r'CODE_SIGN_ENTITLEMENTS\s*=').hasMatch(original)) {
          diagnostics.add(
            const Diagnostic(
              severity: Severity.warning,
              code: 'IOS_ENTITLEMENTS_UNREFERENCED',
              message:
                  'Created Runner.entitlements but could not set CODE_SIGN_ENTITLEMENTS.',
              action: 'In Xcode: Signing & Capabilities → Associated Domains.',
            ),
          );
        }
      } else {
        diagnostics.add(
          const Diagnostic(
            severity: Severity.warning,
            code: 'IOS_ENTITLEMENTS_UNREFERENCED',
            message:
                'Created Runner.entitlements. Enable Associated Domains in Xcode.',
          ),
        );
      }
      return changed;
    }

    final file = File(entitlementsPath);
    final original = await file.readAsString();
    final updated = patchIosEntitlements(original, domain);
    if (updated != original) {
      await _backup(file);
      await file.writeAsString(updated);
      changed.add(file.path);
    }
    return changed;
  }

  static String _newEntitlements(String domain) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:$domain</string>
    </array>
</dict>
</plist>
''';

  static String _patchPbxproj(String text) {
    if (RegExp(r'CODE_SIGN_ENTITLEMENTS\s*=').hasMatch(text)) return text;
    const needle = 'INFOPLIST_FILE = Runner/Info.plist;';
    if (!text.contains(needle)) return text;
    return text.replaceAll(
      needle,
      '$needle\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
    );
  }

  static String _androidBlock(
    String domain,
    List<String> paths,
    String indent,
  ) {
    final data = _dataTags(domain, paths, '$indent    ');
    return '''
$indent<!-- deeplink_setup:begin -->
$indent<intent-filter android:autoVerify="true">
$indent    <action android:name="android.intent.action.VIEW" />
$indent    <category android:name="android.intent.category.DEFAULT" />
$indent    <category android:name="android.intent.category.BROWSABLE" />
$data$indent</intent-filter>
$indent<!-- deeplink_setup:end -->
''';
  }

  static String _dataTags(String domain, List<String> paths, String indent) {
    final prefixes = <String>{};
    for (var path in paths) {
      var value = path.trim();
      if (value.isEmpty || value == '/*' || value == '*') continue;
      if (value.endsWith('/*')) {
        value = value.substring(0, value.length - 2);
      }
      if (value.isEmpty || value == '/') continue;
      if (!value.startsWith('/')) value = '/$value';
      prefixes.add(value);
    }
    if (prefixes.isEmpty) {
      return '$indent<data android:scheme="https" android:host="$domain" />\n';
    }
    return [
      for (final prefix in prefixes)
        '$indent<data android:scheme="https" android:host="$domain" android:pathPrefix="$prefix" />\n',
    ].join();
  }

  static List<_ActivitySpan> _activities(String text) {
    final spans = <_ActivitySpan>[];
    final openRe = RegExp(r'<activity\b[\s\S]*?>', caseSensitive: false);
    final closeRe = RegExp(r'</activity>', caseSensitive: false);
    for (final open in openRe.allMatches(text)) {
      final tag = open.group(0)!;
      if (tag.trimRight().endsWith('/>')) continue;
      RegExpMatch? close;
      for (final match in closeRe.allMatches(text)) {
        if (match.start >= open.end) {
          close = match;
          break;
        }
      }
      if (close == null) continue;
      final lineStart = text.lastIndexOf('\n', close.start) + 1;
      spans.add(
        _ActivitySpan(
          openTag: tag,
          body: text.substring(open.end, close.start),
          closeStart: close.start,
          closeIndent: text.substring(lineStart, close.start),
        ),
      );
    }
    return spans;
  }

  static _ActivitySpan _pickActivity(List<_ActivitySpan> activities) {
    for (final activity in activities) {
      if (RegExp(
        r'''android:name\s*=\s*["'][^"']*MainActivity["']''',
        caseSensitive: false,
      ).hasMatch(activity.openTag)) {
        return activity;
      }
    }
    for (final activity in activities) {
      if (activity.body.contains('android.intent.action.MAIN') &&
          activity.body.contains('android.intent.category.LAUNCHER')) {
        return activity;
      }
    }
    return activities.first;
  }

  static bool _hasHost(String body, String domain) =>
      body.contains('android:host="$domain"') ||
      body.contains("android:host='$domain'");

  Future<void> _backup(File file) async {
    final backup = File('${file.path}.deeplink_setup.bak');
    if (!await backup.exists()) {
      await backup.writeAsString(await file.readAsString());
    }
  }

  Future<String?> _findEntitlements(String root) async {
    final preferred =
        File(p.join(root, 'ios', 'Runner', 'Runner.entitlements'));
    if (await preferred.exists()) return preferred.path;
    final dir = Directory(p.join(root, 'ios'));
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.entitlements')) {
        return entity.path;
      }
    }
    return null;
  }
}

class _ActivitySpan {
  const _ActivitySpan({
    required this.openTag,
    required this.body,
    required this.closeStart,
    required this.closeIndent,
  });

  final String openTag;
  final String body;
  final int closeStart;
  final String closeIndent;
}
