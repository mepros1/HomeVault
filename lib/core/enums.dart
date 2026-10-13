import 'package:json_annotation/json_annotation.dart';

/// Property types for a home. Stored in Drift by `.name`.
enum PropertyType {
  house,
  apartment,
  condo,
  townhouse,
  other;

  String get label => switch (this) {
        PropertyType.house => 'House',
        PropertyType.apartment => 'Apartment',
        PropertyType.condo => 'Condo',
        PropertyType.townhouse => 'Townhouse',
        PropertyType.other => 'Other',
      };
}

/// Preset room types (spec §3.1). `custom` is used when the user names a room
/// manually; the display name then lives in `rooms.name`.
enum RoomType {
  livingRoom('Living Room'),
  kitchen('Kitchen'),
  masterBedroom('Master Bedroom'),
  bedroom('Bedroom'),
  bathroom('Bathroom'),
  garage('Garage'),
  basement('Basement'),
  attic('Attic'),
  office('Office'),
  diningRoom('Dining Room'),
  hallway('Hallway'),
  closet('Closet'),
  outdoorShed('Outdoor/Shed'),
  custom('Custom');

  const RoomType(this.label);

  /// Human-readable name; also what the worker receives as `room_type`.
  final String label;

  static List<RoomType> get presets =>
      values.where((t) => t != RoomType.custom).toList(growable: false);
}

/// Room lifecycle (spec §3.1): empty → captured → analyzed → reviewed.
enum RoomStatus { empty, captured, analyzed, reviewed }

/// Fixed category list aligned with insurance policy logic (spec §3.6).
/// The `@JsonValue` strings are the exact values the worker returns.
enum ItemCategory {
  @JsonValue('Electronics')
  electronics('Electronics'),
  @JsonValue('Furniture')
  furniture('Furniture'),
  @JsonValue('Appliances')
  appliances('Appliances'),
  @JsonValue('Kitchenware')
  kitchenware('Kitchenware'),
  @JsonValue('Clothing & Accessories')
  clothingAccessories('Clothing & Accessories'),
  @JsonValue('Jewelry & Watches')
  jewelryWatches('Jewelry & Watches'),
  @JsonValue('Art & Collectibles')
  artCollectibles('Art & Collectibles'),
  @JsonValue('Tools & Equipment')
  toolsEquipment('Tools & Equipment'),
  @JsonValue('Sports & Outdoor')
  sportsOutdoor('Sports & Outdoor'),
  @JsonValue('Musical Instruments')
  musicalInstruments('Musical Instruments'),
  @JsonValue('Books & Media')
  booksMedia('Books & Media'),
  @JsonValue('Toys & Games')
  toysGames('Toys & Games'),
  @JsonValue('Home Decor')
  homeDecor('Home Decor'),
  @JsonValue('Bedding & Linens')
  beddingLinens('Bedding & Linens'),
  @JsonValue('Office & Stationery')
  officeStationery('Office & Stationery'),
  @JsonValue('Other')
  other('Other');

  const ItemCategory(this.label);

  final String label;

  /// Categories that standard policies usually sub-limit; used together with
  /// the price threshold to set `is_high_value`.
  bool get isSpecialCoverage =>
      this == ItemCategory.jewelryWatches || this == ItemCategory.artCollectibles;

  static ItemCategory fromLabel(String? label) => values.firstWhere(
        (c) => c.label == label,
        orElse: () => ItemCategory.other,
      );
}

/// Item condition (spec §3.5). `brandNew` maps to the wire value `new`.
enum ItemCondition {
  @JsonValue('new')
  brandNew('new'),
  @JsonValue('excellent')
  excellent('excellent'),
  @JsonValue('good')
  good('good'),
  @JsonValue('fair')
  fair('fair'),
  @JsonValue('poor')
  poor('poor');

  const ItemCondition(this.wire);

  final String wire;
}

/// Review state of an item on the review screen. Not in the original spec;
/// needed so that re-analysis can tell confirmed items from unconfirmed ones.
enum ReviewStatus { pending, accepted }

enum AttachmentKind { receipt, label, extra }

/// Persistent analysis queue state (spec §3.3).
enum AnalysisJobStatus { queued, running, done, failed }
