import 'dart:io';
import 'package:args/command_runner.dart';
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
    print(e.message);
    return 64;
  } catch (e) {
    // ignore: avoid_print
    print('ERROR: $e');
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
      print(d);
    }
    final e = ds.where((d) => d.isError).length;
    final w = ds.where((d) => d.isWarning).length;
    // ignore: avoid_print
    print('\n$e error(s), $w warning(s).');
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
      print('ERROR: --domain is required for init.');
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
      print('Refusing to overwrite existing deeplink_config.yaml.');
      return 1;
    }
    await file.writeAsString(c.toYaml());
    // ignore: avoid_print
    print('✓ Created deeplink_config.yaml');
    if (info.androidPackage != null) {
      // ignore: avoid_print
      print('✓ Android package: ${info.androidPackage}');
    }
    if (info.androidSha256 != null) {
      // ignore: avoid_print
      print('✓ Android SHA-256 detected');
    }
    if (info.iosBundleId != null) {
      // ignore: avoid_print
      print('✓ iOS bundle ID: ${info.iosBundleId}');
    }
    if (info.iosTeamId != null) {
      // ignore: avoid_print
      print('✓ iOS team ID: ${info.iosTeamId}');
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
      print('✓ Generated ${f.path}');
    }
    if (!files.any((f) => f.path.endsWith('assetlinks.json'))) {
      // ignore: avoid_print
      print(
        'ℹ Skipped assetlinks.json (android.package and android.sha256 required).',
      );
    }
    if (!files.any((f) => f.path.endsWith('apple-app-site-association'))) {
      // ignore: avoid_print
      print(
        'ℹ Skipped apple-app-site-association (ios.bundle_id and ios.team_id required).',
      );
    }
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
      print('No safe project configuration changes were necessary.');
    } else {
      for (final f in result.changed) {
        // ignore: avoid_print
        print('✓ Updated $f');
      }
      // ignore: avoid_print
      print(
        'Backups use the .deeplink_setup.bak suffix. Review your git diff.',
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
    print('\nDevelopment endpoints:');
    print('  https://${c.domain}/.well-known/assetlinks.json');
    print('  https://${c.domain}/.well-known/apple-app-site-association');
    print(
      '\nThis checks the origin directly; it does not claim to bypass undocumented Apple CDN behavior.',
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
