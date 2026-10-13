import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device text recognition (spec §3.5: OCR never leaves the device).
abstract interface class OcrEngine {
  /// Full recognised text, lines separated by newlines. Empty when nothing
  /// was found.
  Future<String> recognizeFile(String path);

  void dispose();
}

/// ML Kit implementation. The Latin model is bundled with the app, so it
/// works offline and needs no download.
class MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<String> recognizeFile(String path) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(path));
    return result.blocks
        .expand((b) => b.lines)
        .map((l) => l.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n');
  }

  @override
  void dispose() => _recognizer.close();
}

/// Test double.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine(this.text);

  final String text;

  @override
  Future<String> recognizeFile(String path) async => text;

  @override
  void dispose() {}
}
