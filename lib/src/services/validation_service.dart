import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../config/deeplink_config.dart';
import '../diagnostics/diagnostic.dart';
import '../generators/association_generator.dart';

class ValidationService {
  Future<List<Diagnostic>> local(DeeplinkConfig c, {String root = '.'}) async {
    final out = <Diagnostic>[];
    _config(c, out);

    if (c.hasCompleteAndroid) {
      await _compareLocal(
        out,
        root,
        'assetlinks.json',
        () => AssociationGenerator.assetLinks(c),
        'ASSETLINKS_CONFIG',
      );
    }
    if (c.hasCompleteIos) {
      await _compareLocal(
        out,
        root,
        'apple-app-site-association',
        () => AssociationGenerator.aasa(c),
        'AASA_CONFIG',
      );
    }

    if (!out.any((d) => d.isError)) {
      out.add(
        const Diagnostic(
          severity: Severity.success,
          code: 'LOCAL_VALID',
          message: 'Local configuration passed validation.',
        ),
      );
    }
    return out;
  }

  Future<List<Diagnostic>> live(DeeplinkConfig c, {http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final out = <Diagnostic>[];
      final targets = <String, String Function()>{
        if (c.hasCompleteAndroid)
          'assetlinks.json': () => AssociationGenerator.assetLinks(c),
        if (c.hasCompleteIos)
          'apple-app-site-association': () => AssociationGenerator.aasa(c),
      };
      if (targets.isEmpty) {
        out.add(
          const Diagnostic(
            severity: Severity.error,
            code: 'NO_PLATFORM_CONFIG',
            message: 'Android and/or iOS configuration is required.',
            action: 'Add android and/or ios values in deeplink_config.yaml.',
          ),
        );
        return out;
      }

      for (final entry in targets.entries) {
        final name = entry.key;
        final uri = Uri.https(c.domain, '/.well-known/$name');
        late final String expected;
        try {
          expected = entry.value();
        } catch (e) {
          out.add(
            Diagnostic(
              severity: Severity.error,
              code: 'LIVE_CONFIG',
              message: '$name could not be generated from config: $e',
            ),
          );
          continue;
        }

        try {
          final response = await _fetch(httpClient, uri);
          final checked = 'Checked: $uri';
          if (response.statusCode >= 300 && response.statusCode < 400) {
            final location = response.headers['location'];
            out.add(
              Diagnostic(
                severity: Severity.error,
                code: 'HTTP_REDIRECT',
                message:
                    '$name redirected (HTTP ${response.statusCode}). $checked'
                    '${location == null ? '' : '\n  Redirected to: $location'}',
                action:
                    'Host the file at this exact URL with HTTPS 200 and no redirects. '
                    'Google/Apple will not follow redirects for association files.',
              ),
            );
            continue;
          }
          if (response.statusCode != 200) {
            out.add(
              Diagnostic(
                severity: Severity.error,
                code: 'HTTP_STATUS',
                message: _httpStatusMessage(name, response.statusCode, uri),
                action: _httpStatusAction(name, response.statusCode),
              ),
            );
            continue;
          }
          final type = response.headers['content-type']?.toLowerCase() ?? '';
          if (!type.contains('application/json') &&
              !type.contains('application/pkcs7-mime')) {
            out.add(
              Diagnostic(
                severity: Severity.warning,
                code: 'CONTENT_TYPE',
                message: '$name at $uri returned Content-Type "$type".',
                action: 'Prefer application/json for the association files.',
              ),
            );
          }
          try {
            jsonDecode(response.body);
          } catch (_) {
            out.add(
              Diagnostic(
                severity: Severity.error,
                code: 'INVALID_JSON',
                message: '$name at $uri is not valid JSON.',
                action:
                    'Re-upload the file from `deeplink_setup generate` without HTML wrapping.',
              ),
            );
            continue;
          }
          if (jsonEquivalent(response.body, expected)) {
            out.add(
              Diagnostic(
                severity: Severity.success,
                code: 'ORIGIN_MATCH',
                message:
                    '$name on the origin matches generated config output.\n  $checked',
              ),
            );
          } else {
            out.add(
              Diagnostic(
                severity: Severity.error,
                code: 'ORIGIN_MISMATCH',
                message:
                    '$name on the server does not match your deeplink_config.yaml.\n  $checked',
                action:
                    'Run `deeplink_setup generate`, then upload the new file to that URL via your backend/CDN.',
              ),
            );
          }
        } catch (e) {
          out.add(
            Diagnostic(
              severity: Severity.error,
              code: 'NETWORK_ERROR',
              message: 'Could not reach $name at $uri\n  $e',
              action:
                  'Check domain spelling, DNS, and that HTTPS works in a browser.',
            ),
          );
        }
      }
      return out;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<http.Response> _fetch(http.Client client, Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    return http.Response.fromStream(await client.send(request));
  }

  /// Semantic JSON equality so pretty vs minified origin files still match.
  static bool jsonEquivalent(String a, String b) {
    try {
      return jsonEncode(_canon(jsonDecode(a))) ==
          jsonEncode(_canon(jsonDecode(b)));
    } catch (_) {
      return false;
    }
  }

  static Object? _canon(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canon(value[k])};
    }
    if (value is List) {
      return [for (final item in value) _canon(item)];
    }
    return value;
  }

  void _config(DeeplinkConfig c, List<Diagnostic> out) {
    if (!RegExp(r'^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$').hasMatch(c.domain)) {
      out.add(
        const Diagnostic(
          severity: Severity.error,
          code: 'INVALID_DOMAIN',
          message: 'Domain format looks invalid.',
        ),
      );
    }
    if (c.androidPackage != null &&
        !RegExp(
          r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$',
        ).hasMatch(c.androidPackage!)) {
      out.add(
        const Diagnostic(
          severity: Severity.error,
          code: 'INVALID_ANDROID_PACKAGE',
          message: 'Android package name format is invalid.',
        ),
      );
    }
    if (c.androidSha256 != null &&
        !RegExp(
          r'^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$',
        ).hasMatch(c.androidSha256!)) {
      out.add(
        const Diagnostic(
          severity: Severity.error,
          code: 'INVALID_SHA256',
          message:
              'SHA-256 fingerprint must contain 32 hexadecimal byte pairs.',
        ),
      );
    }
    if (c.hasPartialAndroid) {
      out.add(
        const Diagnostic(
          severity: Severity.error,
          code: 'INCOMPLETE_ANDROID',
          message: 'Android package and sha256 must be provided together.',
        ),
      );
    }
    if (c.hasPartialIos) {
      out.add(
        const Diagnostic(
          severity: Severity.error,
          code: 'INCOMPLETE_IOS',
          message: 'iOS bundle_id and team_id must be provided together.',
        ),
      );
    }
    if (!c.hasCompleteAndroid &&
        !c.hasCompleteIos &&
        !c.hasPartialAndroid &&
        !c.hasPartialIos) {
      out.add(
        const Diagnostic(
          severity: Severity.error,
          code: 'NO_PLATFORM_CONFIG',
          message: 'Android and/or iOS configuration is required.',
          action: 'Add android and/or ios values in deeplink_config.yaml.',
        ),
      );
    }
  }

  static String _httpStatusMessage(String name, int status, Uri uri) {
    if (status == 404) {
      return '$name was not found on the server (HTTP 404).\n'
          '  Checked: $uri';
    }
    if (status == 401 || status == 403) {
      return '$name is blocked (HTTP $status).\n'
          '  Checked: $uri';
    }
    return '$name returned HTTP $status.\n'
        '  Checked: $uri';
  }

  static String _httpStatusAction(String name, int status) {
    if (status == 404) {
      return 'Upload `.well-known/$name` from `deeplink_setup generate` to your '
          'backend/CDN/static host. Open that URL in a browser — you should see JSON, not a 404 page.';
    }
    if (status == 401 || status == 403) {
      return 'Make this URL public (no login). App Links / Universal Links cannot read private files.';
    }
    return 'Fix the server so this URL returns HTTPS 200 with JSON and no redirects.';
  }

  Future<void> _compareLocal(
    List<Diagnostic> out,
    String root,
    String name,
    String Function() expected,
    String configCode,
  ) async {
    late final String want;
    try {
      want = expected();
    } catch (e) {
      out.add(Diagnostic(
          severity: Severity.error, code: configCode, message: '$e'));
      return;
    }

    final file = File(p.join(root, '.well-known', name));
    if (!await file.exists()) {
      out.add(
        Diagnostic(
          severity: Severity.error,
          code: 'FILE_MISSING',
          message: '$name is not generated locally.',
          action: 'Run: deeplink_setup generate',
        ),
      );
      return;
    }
    final actual = await file.readAsString();
    if (actual.trim() == want.trim()) {
      out.add(
        Diagnostic(
          severity: Severity.success,
          code: 'LOCAL_MATCH',
          message: '$name matches generated output.',
        ),
      );
    } else {
      out.add(
        Diagnostic(
          severity: Severity.error,
          code: 'LOCAL_MISMATCH',
          message: '$name differs from generated output.',
          action: 'Run: deeplink_setup generate',
        ),
      );
    }
  }
}
