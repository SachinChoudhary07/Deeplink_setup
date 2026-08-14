import 'dart:io';

import 'diagnostics/diagnostic.dart';

/// Terminal colors and icons for CLI output.
class CliStyle {
  static bool get enabled {
    if (Platform.environment.containsKey('NO_COLOR')) return false;
    return stdout.supportsAnsiEscapes;
  }

  static String green(String text) => _wrap('\x1B[32m', text);
  static String yellow(String text) => _wrap('\x1B[33m', text);
  static String red(String text) => _wrap('\x1B[31m', text);
  static String cyan(String text) => _wrap('\x1B[36m', text);
  static String bold(String text) => _wrap('\x1B[1m', text);
  static String dim(String text) => _wrap('\x1B[2m', text);

  static String ok(String message) => '${green('✓')} $message';
  static String warn(String message) => '${yellow('!')} $message';
  static String info(String message) => '${cyan('ℹ')} $message';
  static String err(String message) => '${red('✗')} $message';

  static String diagnostic(Diagnostic d) {
    final icon = switch (d.severity) {
      Severity.success => green('✓'),
      Severity.info => cyan('ℹ'),
      Severity.warning => yellow('!'),
      Severity.error => red('✗'),
    };
    final code = switch (d.severity) {
      Severity.success => green('[${d.code}]'),
      Severity.info => cyan('[${d.code}]'),
      Severity.warning => yellow('[${d.code}]'),
      Severity.error => red('[${d.code}]'),
    };
    final action = d.action == null ? '' : '\n  ${dim('→')} ${d.action}';
    return '$icon $code ${d.message}$action';
  }

  static String summary(int errors, int warnings) {
    final e = errors == 0 ? green('$errors error(s)') : red('$errors error(s)');
    final w = warnings == 0
        ? green('$warnings warning(s)')
        : yellow('$warnings warning(s)');
    return '$e, $w.';
  }

  static String _wrap(String code, String text) {
    if (!enabled) return text;
    return '$code$text\x1B[0m';
  }
}
