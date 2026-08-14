import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/deeplink_config.dart';
import '../diagnostics/diagnostic.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class ProjectInfo {
  const ProjectInfo({
    this.androidPackage,
    this.androidSha256,
    this.iosBundleId,
    this.iosTeamId,
    this.androidManifest,
    this.iosInfoPlist,
    this.iosEntitlements,
    this.diagnostics = const [],
  });

  final String? androidPackage;
  final String? androidSha256;
  final String? iosBundleId;
  final String? iosTeamId;
  final String? androidManifest;
  final String? iosInfoPlist;
  final String? iosEntitlements;
  final List<Diagnostic> diagnostics;
}

class ProjectDetector {
  ProjectDetector({
    Map<String, String>? environment,
    ProcessRunner? runProcess,
  })  : environment = environment ?? Platform.environment,
        runProcess = runProcess ?? ((exe, args) => Process.run(exe, args));

  final Map<String, String> environment;
  final ProcessRunner runProcess;

  Future<ProjectInfo> detect({String root = '.'}) async {
    final diagnostics = <Diagnostic>[];
    final hasAndroid = await _hasAndroid(root);
    final hasIos = await Directory(p.join(root, 'ios')).exists();

    final androidPackage =
        hasAndroid ? await _detectAndroidPackage(root, diagnostics) : null;
    final sha = hasAndroid ? await _detectSha(root, diagnostics) : null;
    final manifest = await _findFirst(root, [
      'android/app/src/main/AndroidManifest.xml',
    ]);
    final plist = await _findFirst(root, [
      'ios/Runner/Info.plist',
    ]);
    final entitlements = await _findEntitlements(root);
    final bundle =
        hasIos ? await _detectBundleId(root, plist, diagnostics) : null;
    final team = hasIos ? await _detectTeamId(root, diagnostics) : null;

    if (!hasAndroid && !hasIos) {
      diagnostics.add(
        const Diagnostic(
          severity: Severity.info,
          code: 'NO_MOBILE_PROJECT',
          message: 'No Android or iOS project files were found.',
          action: 'Fill deeplink_config.yaml manually, then run generate.',
        ),
      );
    }

    return ProjectInfo(
      androidPackage: androidPackage,
      androidSha256: sha,
      iosBundleId: bundle,
      iosTeamId: team,
      androidManifest: manifest,
      iosInfoPlist: plist,
      iosEntitlements: entitlements,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  Future<bool> _hasAndroid(String root) async {
    return await File(p.join(root, 'android/app/build.gradle')).exists() ||
        await File(p.join(root, 'android/app/build.gradle.kts')).exists();
  }

  Future<String?> _detectAndroidPackage(
    String root,
    List<Diagnostic> diagnostics,
  ) async {
    final candidates = [
      p.join(root, 'android/app/build.gradle'),
      p.join(root, 'android/app/build.gradle.kts'),
    ];
    for (final path in candidates) {
      final f = File(path);
      if (!await f.exists()) continue;
      final text = await f.readAsString();
      final applicationId = _firstResolved(
        RegExp(r'''applicationId\s*(?:=)?\s*["']([^"']+)["']'''),
        text,
      );
      if (applicationId != null) return applicationId;
      final namespace = _firstResolved(
        RegExp(r'''namespace\s*(?:=)?\s*["']([^"']+)["']'''),
        text,
      );
      if (namespace != null) return namespace;
    }
    diagnostics.add(
      const Diagnostic(
        severity: Severity.warning,
        code: 'ANDROID_PACKAGE_NOT_FOUND',
        message: 'Could not detect an Android applicationId.',
        action: 'Set android.package in deeplink_config.yaml.',
      ),
    );
    return null;
  }

  Future<String?> _detectSha(String root, List<Diagnostic> diagnostics) async {
    final keystore = await _findDebugKeystore(root);
    if (keystore == null) {
      diagnostics.add(
        const Diagnostic(
          severity: Severity.warning,
          code: 'DEBUG_KEYSTORE_NOT_FOUND',
          message: 'Android debug keystore was not found.',
          action:
              'Paste the debug or release SHA-256 into deeplink_config.yaml under android.sha256.',
        ),
      );
      return null;
    }

    ProcessException? lastMissing;
    for (final exe in _keytoolExecutables()) {
      try {
        final result = await runProcess(exe, [
          '-list',
          '-v',
          '-keystore',
          keystore.path,
          '-alias',
          'androiddebugkey',
          '-storepass',
          'android',
          '-keypass',
          'android',
        ]);
        final text = '${result.stdout}\n${result.stderr}';
        final match = RegExp(r'SHA-?256:\s*([0-9A-Fa-f: -]+)').firstMatch(text);
        final sha = DeeplinkConfig.normalizeSha256(match?.group(1));
        if (sha != null && sha.split(':').length == 32) {
          return sha;
        }
        diagnostics.add(
          Diagnostic(
            severity: Severity.warning,
            code: 'SHA256_DETECT_FAILED',
            message: 'keytool ran but a SHA-256 fingerprint was not found.',
            action:
                'Paste android.sha256 into deeplink_config.yaml. keytool exit ${result.exitCode}.',
          ),
        );
        return null;
      } on ProcessException catch (e) {
        lastMissing = e;
      }
    }

    if (lastMissing != null) {
      diagnostics.add(
        const Diagnostic(
          severity: Severity.warning,
          code: 'KEYTOOL_NOT_FOUND',
          message: 'keytool was not found on PATH or JAVA_HOME.',
          action:
              'Install a JDK and add its bin directory to PATH, then re-run init. Or paste android.sha256 into deeplink_config.yaml.',
        ),
      );
    }
    return null;
  }

  Future<File?> _findDebugKeystore(String root) async {
    final home =
        _nonEmpty(environment['HOME']) ?? _nonEmpty(environment['USERPROFILE']);
    final candidates = <String>[
      p.join(root, 'android/app/debug.keystore'),
      p.join(root, 'android/debug.keystore'),
      if (home != null) p.join(home, '.android', 'debug.keystore'),
    ];
    for (final path in candidates) {
      final f = File(path);
      if (await f.exists()) return f;
    }
    return null;
  }

  List<String> _keytoolExecutables() {
    final javaHome = _nonEmpty(environment['JAVA_HOME']);
    final name = Platform.isWindows ? 'keytool.exe' : 'keytool';
    return [
      'keytool',
      if (Platform.isWindows) 'keytool.exe',
      if (javaHome != null) p.join(javaHome, 'bin', name),
    ];
  }

  Future<String?> _detectBundleId(
    String root,
    String? plistPath,
    List<Diagnostic> diagnostics,
  ) async {
    if (plistPath != null) {
      final text = await File(plistPath).readAsString();
      final match = RegExp(
        r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>',
      ).firstMatch(text);
      final fromPlist = _resolved(match?.group(1));
      if (fromPlist != null) return fromPlist;
    }
    final pbx = File(p.join(root, 'ios/Runner.xcodeproj/project.pbxproj'));
    if (await pbx.exists()) {
      final text = await pbx.readAsString();
      for (final match in RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);',
      ).allMatches(text)) {
        final value = _resolved(match.group(1));
        if (value != null) return value;
      }
    }
    diagnostics.add(
      const Diagnostic(
        severity: Severity.warning,
        code: 'BUNDLE_ID_NOT_FOUND',
        message: 'Could not detect an iOS bundle identifier.',
        action: 'Set ios.bundle_id in deeplink_config.yaml.',
      ),
    );
    return null;
  }

  Future<String?> _detectTeamId(
      String root, List<Diagnostic> diagnostics) async {
    final pbx = File(p.join(root, 'ios/Runner.xcodeproj/project.pbxproj'));
    if (await pbx.exists()) {
      final text = await pbx.readAsString();
      for (final match
          in RegExp(r'DEVELOPMENT_TEAM\s*=\s*([^;]+);').allMatches(text)) {
        final value = _resolved(match.group(1));
        if (value != null) return value;
      }
    }
    diagnostics.add(
      const Diagnostic(
        severity: Severity.warning,
        code: 'TEAM_ID_NOT_FOUND',
        message: 'Could not detect an iOS DEVELOPMENT_TEAM.',
        action: 'Set ios.team_id in deeplink_config.yaml.',
      ),
    );
    return null;
  }

  Future<String?> _findEntitlements(String root) async {
    final dir = Directory(p.join(root, 'ios'));
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.entitlements')) {
        return entity.path;
      }
    }
    return null;
  }

  Future<String?> _findFirst(String root, List<String> paths) async {
    for (final path in paths) {
      final f = File(p.join(root, path));
      if (await f.exists()) return f.path;
    }
    return null;
  }

  String? _firstResolved(RegExp pattern, String text) =>
      _resolved(pattern.firstMatch(text)?.group(1));

  String? _resolved(String? value) {
    if (value == null) return null;
    var v = value.trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1).trim();
    }
    if (v.isEmpty || v.contains(r'$') || v.startsWith('flutter.')) return null;
    return v;
  }

  String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
