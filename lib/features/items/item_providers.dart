import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/media/attachment_store.dart';
import '../../data/ocr/ocr_engine.dart';
import '../../data/providers.dart';
import '../capture/capture_providers.dart';

// Hand-written providers: they carry Drift row classes (see CLAUDE.md).

final attachmentStoreProvider = Provider<AttachmentStore>(
  (ref) => AttachmentStore(
    ref.watch(appDatabaseProvider),
    baseDir: ref.watch(captureBaseDirProvider),
  ),
);

final attachmentsForItemProvider = StreamProvider.family<List<Attachment>, String>(
  (ref, itemId) => ref.watch(appDatabaseProvider).itemsDao.watchAttachments(itemId),
);

final attachmentThumbPathProvider = FutureProvider.family<String, Attachment>(
  (ref, a) => ref.watch(attachmentStoreProvider).absolutePath(AttachmentStore.thumbPathFor(a.filePath)),
);

/// On-device OCR. Overridden with [FakeOcrEngine] in tests.
final ocrEngineProvider = Provider<OcrEngine>((ref) {
  final engine = MlKitOcrEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
