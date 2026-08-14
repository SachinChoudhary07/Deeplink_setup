import 'dart:io';
import 'package:args/command_runner.dart';
import 'cli_style.dart';
import 'config/deeplink_config.dart';
import 'diagnostics/diagnostic.dart';
import 'generators/association_generator.dart';
import 'services/cdn_service.dart';
import 'services/doctor_service.dart';
import 'services/project_configurator.dart';
import 'services/project_detector.dart';
import 'services/validation_service.dart';

Future<int> runCli(List<String> args) async {
  final runner = CommandRunner<int>(
    'deeplink_setup',
    'Deep Link generation, validation and diagnostics',
  )
    ..addCommand(_Init())
    ..addCommand(_Generate())
    ..addCommand(_Configure())
    ..addCommand(_Validate())
    ..addCommand(_Cdn())
    ..addCommand(_TestLive())
    ..addCommand(_Doctor());

  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    // ignore: avoid_print
    print(CliStyle.err(e.message));
    return 64;
  } catch (e) {
    // ignore: avoid_print
    print(CliStyle.err('$e'));
    return 1;
  }
}

abstract class Base extends Command<int> {
  String get config =>
      argResults?['config'] as String? ?? 'deeplink_config.yaml';
  void configOption() =>
      argParser.addOption('config', defaultsTo: 'deeplink_config.yaml');

  void output(List<Diagnostic> ds) {
    for (final d in ds) {
      // ignore: avoid_print
      print(CliStyle.diagnostic(d));
    }
    final e = ds.where((d) => d.isError).length;
    final w = ds.where((d) => d.isWarning).length;
    // ignore: avoid_print
    print('\n${CliStyle.summary(e, w)}');
  }
}

class _Init extends Base {
  @override
  String get name => 'init';
  @override
  String get description =>
      'Detect project values and create deeplink_config.yaml.';
  _Init() {
    argParser.addOption('domain', help: 'Domain, e.g. example.com');
  }

  @override
  Future<int> run() async {
    final info = await ProjectDetector().detect();
    final domain = argResults?['domain'] as String?;
    if (domain == null || domain.isEmpty) {
      // ignore: avoid_print
      print(CliStyle.err('--domain is required for init.'));
      return 64;
    }
    final c = DeeplinkConfig(
      domain: domain,
      androidPackage: info.androidPackage,
      androidSha256: info.androidSha256,
      iosBundleId: info.iosBundleId,
      iosTeamId: info.iosTeamId,
    );
    final file = File('deeplink_config.yaml');
    if (await file.exists()) {
      // ignore: avoid_print
      print(
          CliStyle.err('Refusing to overwrite existing deeplink_config.yaml.'));
      return 1;
    }
    await file.writeAsString(c.toYaml());
    // ignore: avoid_print
    print(CliStyle.ok('Created deeplink_config.yaml'));
    if (info.androidPackage != null) {
      // ignore: avoid_print
      print(CliStyle.ok('Android package: ${info.androidPackage}'));
    }
    if (info.androidSha256 != null) {
      // ignore: avoid_print
      print(CliStyle.ok('Android SHA-256 detected'));
    }
    if (info.iosBundleId != null) {
      // ignore: avoid_print
      print(CliStyle.ok('iOS bundle ID: ${info.iosBundleId}'));
    }
    if (info.iosTeamId != null) {
      // ignore: avoid_print
      print(CliStyle.ok('iOS team ID: ${info.iosTeamId}'));
    } else if (info.iosBundleId != null) {
      // ignore: avoid_print
      print(
        CliStyle.warn(
          'ios.team_id placeholder written as YOUR_TEAM_ID — replace it before production.',
        ),
      );
    }
    if (info.diagnostics.isNotEmpty) {
      output(info.diagnostics);
    }
    return 0;
  }
}

class _Generate extends Base {
  @override
  String get name => 'generate';
  @override
  String get description => 'Generate .well-known association files.';
  _Generate() {
    configOption();
    argParser.addOption('output', defaultsTo: '.');
  }

  @override
  Future<int> run() async {
    final c = await DeeplinkConfig.load(config);
    final files = await AssociationGenerator.write(
      c,
      root: argResults!['output'] as String,
    );
    for (final f in files) {
      // ignore: avoid_print
      print(CliStyle.ok('Generated ${f.path}'));
    }
    if (!files.any((f) => f.path.endsWith('assetlinks.json'))) {
      // ignore: avoid_print
      print(
        CliStyle.info(
          'Skipped assetlinks.json (android.package and android.sha256 required).',
        ),
      );
    }
    if (!files.any((f) => f.path.endsWith('apple-app-site-association'))) {
      // ignore: avoid_print
      print(
        CliStyle.info(
          'Skipped apple-app-site-association (ios.bundle_id and ios.team_id required).',
        ),
      );
    }

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(CliStyle.bold('Next step — host these on your website'));
    // ignore: avoid_print
    print(
      CliStyle.dim(
        'These files are for your server (backend / CDN / static host), not inside the app binary.',
      ),
    );
    if (files.any((f) => f.path.endsWith('assetlinks.json'))) {
      // ignore: avoid_print
      print(
        '  • Upload assetlinks.json → '
        '${CliStyle.cyan('https://${c.domain}/.well-known/assetlinks.json')}',
      );
    }
    if (files.any((f) => f.path.endsWith('apple-app-site-association'))) {
      // ignore: avoid_print
      print(
        '  • Upload apple-app-site-association → '
        '${CliStyle.cyan('https://${c.domain}/.well-known/apple-app-site-association')}',
      );
    }
    // ignore: avoid_print
    print(
      CliStyle.dim(
        'Serve over HTTPS with HTTP 200 and no redirects, then run: '
        'deeplink_setup validate --live',
      ),
    );
    return 0;
  }
}

class _Configure extends Base {
  @override
  String get name => 'configure';
  @override
  String get description => 'Safely add deep-link platform configuration.';
  _Configure() {
    configOption();
  }

  @override
  Future<int> run() async {
    final c = await DeeplinkConfig.load(config);
    final result = await ProjectConfigurator().configure(
      domain: c.domain,
      paths: c.paths,
    );
    if (result.changed.isEmpty) {
      // ignore: avoid_print
      print(CliStyle.info(
          'No safe project configuration changes were necessary.'));
    } else {
      for (final f in result.changed) {
        // ignore: avoid_print
        print(CliStyle.ok('Updated $f'));
      }
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print(
        CliStyle.info(
          'Backups saved as *.deeplink_setup.bak — review your git diff, then delete .bak if OK.',
        ),
      );
    }
    if (result.diagnostics.isNotEmpty) {
      output(result.diagnostics);
    }
    return result.diagnostics.any((d) => d.isError) ? 1 : 0;
  }
}

class _Validate extends Base {
  @override
  String get name => 'validate';
  @override
  String get description => 'Validate local and/or live configuration.';
  _Validate() {
    configOption();
    argParser.addFlag('local');
    argParser.addFlag('live');
  }

  @override
  Future<int> run() async {
    final local = argResults!['local'] as bool;
    final live = argResults!['live'] as bool;
    if (!local && !live) {
      throw UsageException('Use --local, --live, or both.', usage);
    }
    final c = await DeeplinkConfig.load(config);
    final service = ValidationService();
    final ds = <Diagnostic>[];
    if (local) ds.addAll(await service.local(c));
    if (live) ds.addAll(await service.live(c));
    output(ds);
    if (live && ds.any((d) => d.isError)) {
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print(CliStyle.bold('Tip'));
      // ignore: avoid_print
      print(
        CliStyle.dim(
          '1) Run generate  2) Upload .well-known files to https://${c.domain}/  '
          '3) Open the Checked: URL in a browser  4) Re-run validate --live',
        ),
      );
    }
    return ds.any((d) => d.isError) ? 1 : 0;
  }
}

class _Cdn extends Base {
  @override
  String get name => 'check-cdn';
  @override
  String get description => 'Compare origin AASA with Apple CDN.';
  _Cdn() {
    configOption();
  }

  @override
  Future<int> run() async {
    final c = await DeeplinkConfig.load(config);
    final ds = await CdnService().check(c);
    output(ds);
    return ds.any((d) => d.isError) ? 1 : 0;
  }
}

class _TestLive extends Base {
  @override
  String get name => 'test-live';
  @override
  String get description =>
      'Directly validate origin endpoints for development.';
  _TestLive() {
    configOption();
  }

  @override
  Future<int> run() async {
    final c = await DeeplinkConfig.load(config);
    final ds = await ValidationService().live(c);
    output(ds);
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print(CliStyle.bold('Development endpoints'));
    // ignore: avoid_print
    print(
        '  ${CliStyle.cyan('https://${c.domain}/.well-known/assetlinks.json')}');
    // ignore: avoid_print
    print(
      '  ${CliStyle.cyan('https://${c.domain}/.well-known/apple-app-site-association')}',
    );
    // ignore: avoid_print
    print(
      CliStyle.dim(
        'This checks the origin directly; it does not bypass Apple CDN cache.',
      ),
    );
    return ds.any((d) => d.isError) ? 1 : 0;
  }
}

class _Doctor extends Base {
  @override
  String get name => 'doctor';
  @override
  String get description => 'Run local, live and Apple CDN diagnostics.';
  _Doctor() {
    configOption();
  }

  @override
  Future<int> run() async {
    final c = await DeeplinkConfig.load(config);
    final ds = await DoctorService().run(c);
    output(ds);
    return ds.any((d) => d.isError) ? 1 : 0;
  }
}
