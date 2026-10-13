import 'package:drift/drift.dart';

import '../../core/enums.dart';

/// Drift table definitions mirroring spec §4. IDs are UUID v4 strings generated
/// on the client so rows can later be synced to Supabase without remapping.

@DataClassName('Home')
class Homes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get propertyType => textEnum<PropertyType>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Room')
class Rooms extends Table {
  TextColumn get id => text()();
  TextColumn get homeId =>
      text().references(Homes, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get roomType => textEnum<RoomType>()();
  IntColumn get orderIndex => integer()();
  TextColumn get status =>
      textEnum<RoomStatus>().withDefault(Constant(RoomStatus.empty.name))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Capture')
class Captures extends Table {
  TextColumn get id => text()();
  TextColumn get roomId =>
      text().references(Rooms, #id, onDelete: KeyAction.cascade)();

  /// Original file, stored as shot.
  TextColumn get filePath => text()();

  /// Small thumbnail for lists and the report table.
  TextColumn get thumbPath => text().nullable()();
  DateTimeColumn get takenAt => dateTime()();

  /// Collected in the schema from day one; GPS capture itself is deferred to v2.
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  /// SHA-256 of the original file, hex. Evidence chain + idempotency key input.
  TextColumn get sha256 => text()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  BoolColumn get analyzed => boolean().withDefault(const Constant(false))();

  /// Close-up of a single item (spec §3.2), sent along with the room shots.
  BoolColumn get isCloseup => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Item')
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get roomId =>
      text().references(Rooms, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceCaptureId =>
      text().nullable().references(Captures, #id, onDelete: KeyAction.setNull)();
  TextColumn get name => text()();
  TextColumn get category => textEnum<ItemCategory>()();
  TextColumn get brand => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get serial => text().nullable()();
  IntColumn get qty => integer().withDefault(const Constant(1))();
  TextColumn get condition => textEnum<ItemCondition>().nullable()();
  DateTimeColumn get purchaseDate => dateTime().nullable()();
  RealColumn get purchasePrice => real().nullable()();
  RealColumn get estLow => real().nullable()();
  RealColumn get estHigh => real().nullable()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  RealColumn get confidence => real().nullable()();

  /// Set once the user changes any field. Such rows are never overwritten by
  /// re-analysis (spec §3.3).
  BoolColumn get userEdited => boolean().withDefault(const Constant(false))();
  BoolColumn get isHighValue => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  /// Review-screen state; see [ReviewStatus].
  TextColumn get reviewStatus => textEnum<ReviewStatus>()
      .withDefault(Constant(ReviewStatus.pending.name))();

  /// Prompt version reported by the worker for this item. Lets the
  /// accepted/edited/deleted metric be attributed to a prompt revision.
  TextColumn get promptVersion => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Attachment')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<AttachmentKind>()();
  TextColumn get filePath => text()();

  /// On-device ML Kit OCR output (spec §3.5); never leaves the device.
  TextColumn get ocrText => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Report')
class Reports extends Table {
  TextColumn get id => text()();
  TextColumn get homeId =>
      text().references(Homes, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get generatedAt => dateTime()();
  TextColumn get pdfPath => text()();
  IntColumn get itemCount => integer()();
  RealColumn get totalLow => real()();
  RealColumn get totalHigh => real()();

  /// When the PDF reached the cloud backup; null = not uploaded yet. Schema v3.
  DateTimeColumn get backedUpAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Persistent analysis queue (spec §3.3). One job per room analysis attempt;
/// survives app restarts and offline periods.
@DataClassName('AnalysisJob')
class AnalysisJobs extends Table {
  TextColumn get id => text()();
  TextColumn get roomId =>
      text().references(Rooms, #id, onDelete: KeyAction.cascade)();

  /// SHA-256 over the sorted capture hashes; sent as X-Idempotency-Key.
  TextColumn get idempotencyKey => text()();
  TextColumn get status => textEnum<AnalysisJobStatus>()
      .withDefault(Constant(AnalysisJobStatus.queued.name))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recognition-quality counters (spec §10): accepted / edited / deleted per
/// prompt version. Counts only, never item content.
@DataClassName('ReviewStat')
class ReviewStats extends Table {
  TextColumn get promptVersion => text()();
  IntColumn get accepted => integer().withDefault(const Constant(0))();
  IntColumn get edited => integer().withDefault(const Constant(0))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  // Values already reported to the server (spec §10); the next upload sends
  // the difference. Added in schema v2.
  IntColumn get syncedAccepted => integer().withDefault(const Constant(0))();
  IntColumn get syncedEdited => integer().withDefault(const Constant(0))();
  IntColumn get syncedDeleted => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {promptVersion};
}
