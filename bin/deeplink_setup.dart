import 'package:deeplink_setup/deeplink_setup.dart';

Future<void> main(List<String> arguments) async {
  final code = await runCli(arguments);
  if (code != 0) {
    // ignore: avoid_print
    print('Command failed with exit code $code.');
  }
}
