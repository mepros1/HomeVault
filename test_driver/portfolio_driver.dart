import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('artifacts/portfolio');
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      if (data?['portfolio_pdf'] case final String encoded) {
        await File('${output.path}/homevault-demo-report.pdf').writeAsBytes(base64Decode(encoded));
      }
      await writeResponseData(data, destinationDirectory: output.path);
    },
    writeResponseOnFailure: true,
  );
}
