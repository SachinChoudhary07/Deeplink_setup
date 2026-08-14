enum Severity { success, info, warning, error }

class Diagnostic {
  const Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.action,
  });

  final Severity severity;
  final String code;
  final String message;
  final String? action;

  bool get isError => severity == Severity.error;
  bool get isWarning => severity == Severity.warning;

  String get symbol => switch (severity) {
        Severity.success => '✓',
        Severity.info => 'ℹ',
        Severity.warning => '⚠',
        Severity.error => '✗',
      };

  @override
  String toString() {
    final next = action == null ? '' : '\n  → $action';
    return '$symbol [$code] $message$next';
  }
}
