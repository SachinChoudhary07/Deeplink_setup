import 'package:http/http.dart' as http;

import '../config/deeplink_config.dart';
import '../diagnostics/diagnostic.dart';
import 'cdn_service.dart';
import 'validation_service.dart';

class DoctorService {
  DoctorService({
    ValidationService? validation,
    CdnService? cdn,
  })  : validation = validation ?? ValidationService(),
        cdn = cdn ?? CdnService();

  final ValidationService validation;
  final CdnService cdn;

  Future<List<Diagnostic>> run(
    DeeplinkConfig c, {
    String root = '.',
    http.Client? client,
  }) async {
    final ds = <Diagnostic>[];
    ds.addAll(await validation.local(c, root: root));
    ds.addAll(await validation.live(c, client: client));
    ds.addAll(await cdn.check(c, client: client));
    return ds;
  }
}
