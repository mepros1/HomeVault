import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/db/database.dart';
import '../../data/media/capture_store.dart';
import '../../data/media/storage_janitor.dart';
import '../../data/providers.dart';

// Hand-written providers: they carry Drift row classes (see CLAUDE.md).

/// Root directory for capture files. Overridden in tests with a temp dir.
final captureBaseDirProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);

final captureStoreProvider = Provider<CaptureStore>(
  (ref) => CaptureStore(
    ref.watch(appDatabaseProvider),
    baseDir: ref.watch(captureBaseDirProvider),
  ),
);

final capturesForRoomProvider = StreamProvider.family<List<Capture>, String>(
  (ref, roomId) => ref.watch(appDatabaseProvider).capturesDao.watchForRoom(roomId),
);

/// Absolute thumbnail path for a capture, resolved once per row.
final captureThumbPathProvider = FutureProvider.family<String?, Capture>(
  (ref, capture) async {
    final rel = capture.thumbPath;
    if (rel == null) return null;
    return ref.watch(captureStoreProvider).absolutePath(rel);
  },
);

/// Absolute path of the original photo, for full-width previews. Decode with
/// `cacheWidth` so a 12 MP file does not go through memory at full size.
final captureOriginalPathProvider = FutureProvider.family<String, Capture>(
  (ref, capture) => ref.watch(captureStoreProvider).absolutePath(capture.filePath),
);

final storageJanitorProvider = Provider<StorageJanitor>(
  (ref) => StorageJanitor(
    ref.watch(appDatabaseProvider),
    baseDir: ref.watch(captureBaseDirProvider),
  ),
);
