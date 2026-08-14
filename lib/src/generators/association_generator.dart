import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/deeplink_config.dart';

class AssociationGenerator {
  static String assetLinks(DeeplinkConfig c) {
    if (c.androidPackage == null || c.androidSha256 == null) {
      throw const FormatException('Android package and sha256 are required.');
    }
    final value = [
      {
        'relation': ['delegate_permission/common.handle_all_urls'],
        'target': {
          'namespace': 'android_app',
          'package_name': c.androidPackage,
          'sha256_cert_fingerprints': [_fingerprint(c.androidSha256!)],
        },
      },
    ];
    return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  }

  static String aasa(DeeplinkConfig c) {
    if (c.iosBundleId == null || c.iosTeamId == null) {
      throw const FormatException('iOS bundle_id and team_id are required.');
    }
    final value = {
      'applinks': {
        'details': [
          {
            'appIDs': ['${c.iosTeamId}.${c.iosBundleId}'],
            'components': [
              for (final path in c.paths) {'/': path},
            ],
          },
        ],
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  }

  static String _fingerprint(String value) =>
      DeeplinkConfig.normalizeSha256(value) ?? value;

  static Future<List<File>> write(DeeplinkConfig c, {String root = '.'}) async {
    if (c.hasPartialAndroid) {
      throw const FormatException(
        'Android package and sha256 must be provided together.',
      );
    }
    if (c.hasPartialIos) {
      throw const FormatException(
        'iOS bundle_id and team_id must be provided together.',
      );
    }
    if (!c.hasCompleteAndroid && !c.hasCompleteIos) {
      throw const FormatException(
        'Android and/or iOS configuration is required to generate association files.',
      );
    }

    final dir = Directory(p.join(root, '.well-known'));
    await dir.create(recursive: true);
    final files = <File>[];

    if (c.hasCompleteAndroid) {
      final asset = File(p.join(dir.path, 'assetlinks.json'));
      await asset.writeAsString(assetLinks(c));
      files.add(asset);
    }
    if (c.hasCompleteIos) {
      final aasaFile = File(p.join(dir.path, 'apple-app-site-association'));
      await aasaFile.writeAsString(aasa(c));
      files.add(aasaFile);
    }
    return files;
  }
}
