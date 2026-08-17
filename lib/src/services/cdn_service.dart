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
              'Skipped Apple CDN check — iOS Universal Links are not fully configured.',
          action:
              'Set ios.bundle_id and ios.team_id in deeplink_config.yaml. This check is only for iOS Universal Links.',
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
          Diagnostic(
            severity: Severity.error,
            code: 'ORIGIN_AASA_INVALID_JSON',
            message:
                'Your website Universal Links file is not valid JSON.\n  Checked: $originUri',
            action:
                'Re-upload apple-app-site-association from `deeplink_setup generate`. Open the URL in a browser — you should see JSON, not HTML.',
          ),
        );
      }
      if (!cdnJson) {
        out.add(
          Diagnostic(
            severity: Severity.error,
            code: 'APPLE_CDN_INVALID_JSON',
            message:
                'Apple CDN did not return valid JSON for Universal Links.\n  Checked: $cdnUri',
            action:
                'Confirm your website file is valid first (`validate --live`). Then wait and re-run check-cdn.',
          ),
        );
      }
      if (out.isNotEmpty) return out;

      if (ValidationService.jsonEquivalent(origin.body!, cdn.body!)) {
        out.add(
          Diagnostic(
            severity: Severity.success,
            code: 'APPLE_CDN_MATCH',
            message: 'Apple CDN matches your website Universal Links file.\n'
                '  Your server:  $originUri\n'
                '  Apple CDN:    $cdnUri',
          ),
        );
      } else {
        out.add(
          Diagnostic(
            severity: Severity.warning,
            code: 'APPLE_CDN_ORIGIN_MISMATCH',
            message:
                'Apple is still serving a different Universal Links file than your website.\n'
                '  Your server:  $originUri\n'
                '  Apple CDN:    $cdnUri',
            action:
                'Upload looks fine on your server. Apple’s CDN typically re-crawls in a few hours, '
                'and often within 24 hours. In rare cases it can take several days (TTL). '
                'You cannot clear this cache. Re-run check-cdn later.',
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
    final who = origin ? 'Your website Universal Links file' : 'Apple CDN';
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response =
          await http.Response.fromStream(await client.send(request));
      if (response.statusCode >= 300 && response.statusCode < 400) {
        return _Fetched.error(
          Diagnostic(
            severity: Severity.error,
            code: origin ? 'ORIGIN_AASA_REDIRECT' : 'APPLE_CDN_REDIRECT',
            message:
                '$who redirected (HTTP ${response.statusCode}).\n  Checked: $uri',
            action: origin
                ? 'Serve apple-app-site-association at this exact URL with HTTPS 200 and no redirects.'
                : 'Apple CDN redirected. Re-run check-cdn later.',
          ),
        );
      }
      if (response.statusCode != 200) {
        return _Fetched.error(
          Diagnostic(
            severity: Severity.error,
            code: origin ? 'ORIGIN_AASA_UNAVAILABLE' : 'APPLE_CDN_HTTP_STATUS',
            message:
                '$who returned HTTP ${response.statusCode}.\n  Checked: $uri',
            action: origin
                ? 'Upload apple-app-site-association from `deeplink_setup generate` to this URL, then re-run check-cdn.'
                : 'Apple may not have cached the file yet. Typical refresh is a few hours up to 24 hours; rarely several days (TTL). Re-run check-cdn later.',
          ),
        );
      }
      return _Fetched.body(response.body);
    } catch (e) {
      return _Fetched.error(
        Diagnostic(
          severity: Severity.error,
          code: origin ? 'ORIGIN_AASA_FETCH_FAILED' : 'APPLE_CDN_FETCH_FAILED',
          message: 'Could not reach $who.\n  Checked: $uri\n  $e',
          action: origin
              ? 'Check domain spelling, DNS, and HTTPS in a browser.'
              : 'Network error talking to Apple. Retry check-cdn in a few minutes.',
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
