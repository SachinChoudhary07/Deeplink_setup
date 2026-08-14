import 'package:http/http.dart' as http;

import '../config/deeplink_config.dart';
import '../diagnostics/diagnostic.dart';
import 'validation_service.dart';

class CdnService {
  Future<List<Diagnostic>> check(
    DeeplinkConfig c, {
    http.Client? client,
  }) async {
    if (!c.hasCompleteIos) {
      return const [
        Diagnostic(
          severity: Severity.info,
          code: 'CDN_SKIPPED',
          message:
              'Apple CDN check skipped because iOS configuration is incomplete.',
        ),
      ];
    }

    final httpClient = client ?? http.Client();
    try {
      final originUri = Uri.https(
        c.domain,
        '/.well-known/apple-app-site-association',
      );
      final cdnUri = Uri.parse(
        'https://app-site-association.cdn-apple.com/a/v1/${c.domain}',
      );

      final origin = await _get(httpClient, originUri, origin: true);
      if (origin.error != null) return [origin.error!];
      final cdn = await _get(httpClient, cdnUri, origin: false);
      if (cdn.error != null) return [cdn.error!];

      final originJson =
          ValidationService.jsonEquivalent(origin.body!, origin.body!);
      final cdnJson = ValidationService.jsonEquivalent(cdn.body!, cdn.body!);
      final out = <Diagnostic>[];
      if (!originJson) {
        out.add(
          const Diagnostic(
            severity: Severity.error,
            code: 'ORIGIN_AASA_INVALID_JSON',
            message: 'Origin AASA is not valid JSON.',
          ),
        );
      }
      if (!cdnJson) {
        out.add(
          const Diagnostic(
            severity: Severity.error,
            code: 'APPLE_CDN_INVALID_JSON',
            message: 'Apple CDN AASA is not valid JSON.',
          ),
        );
      }
      if (out.isNotEmpty) return out;

      if (ValidationService.jsonEquivalent(origin.body!, cdn.body!)) {
        out.add(
          const Diagnostic(
            severity: Severity.success,
            code: 'APPLE_CDN_MATCH',
            message: 'Apple CDN AASA matches origin.',
          ),
        );
      } else {
        out.add(
          const Diagnostic(
            severity: Severity.warning,
            code: 'APPLE_CDN_ORIGIN_MISMATCH',
            message: 'Apple CDN AASA differs from origin.',
            action:
                'This may indicate propagation/cache delay. Re-check later; cache invalidation cannot be forced by this CLI.',
          ),
        );
      }
      return out;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Future<_Fetched> _get(http.Client client, Uri uri,
      {required bool origin}) async {
    final label = origin ? 'Origin AASA' : 'Apple CDN';
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response =
          await http.Response.fromStream(await client.send(request));
      if (response.statusCode >= 300 && response.statusCode < 400) {
        return _Fetched.error(
          Diagnostic(
            severity: Severity.error,
            code: origin ? 'ORIGIN_AASA_REDIRECT' : 'APPLE_CDN_REDIRECT',
            message: '$label returned HTTP ${response.statusCode}.',
            action: 'AASA must be served with HTTPS 200 and no redirects.',
          ),
        );
      }
      if (response.statusCode != 200) {
        return _Fetched.error(
          Diagnostic(
            severity: Severity.error,
            code: origin ? 'ORIGIN_AASA_UNAVAILABLE' : 'APPLE_CDN_HTTP_STATUS',
            message: '$label returned HTTP ${response.statusCode}.',
          ),
        );
      }
      return _Fetched.body(response.body);
    } catch (e) {
      return _Fetched.error(
        Diagnostic(
          severity: Severity.error,
          code: origin ? 'ORIGIN_AASA_FETCH_FAILED' : 'APPLE_CDN_FETCH_FAILED',
          message:
              'Could not fetch ${origin ? 'origin AASA' : 'Apple CDN AASA'}: $e',
        ),
      );
    }
  }
}

class _Fetched {
  const _Fetched.error(this.error) : body = null;
  const _Fetched.body(this.body) : error = null;

  final Diagnostic? error;
  final String? body;
}
