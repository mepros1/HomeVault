import 'package:json_annotation/json_annotation.dart';

import '../../core/enums.dart';

part 'analyze_room_models.g.dart';

/// Wire model of one recognised item (spec §5.1).
@JsonSerializable()
class AnalyzedItem {
  const AnalyzedItem({
    required this.name,
    required this.category,
    this.brand,
    this.model,
    this.serial,
    this.qty = 1,
    this.condition,
    required this.estLow,
    required this.estHigh,
    this.currency = 'USD',
    required this.confidence,
    required this.sourceImageIndex,
    this.note,
  });

  factory AnalyzedItem.fromJson(Map<String, dynamic> json) =>
      _$AnalyzedItemFromJson(json);

  final String name;

  @JsonKey(unknownEnumValue: ItemCategory.other)
  final ItemCategory category;
  final String? brand;
  final String? model;
  final String? serial;
  final int qty;

  @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
  final ItemCondition? condition;

  @JsonKey(name: 'est_low')
  final double estLow;

  @JsonKey(name: 'est_high')
  final double estHigh;
  final String currency;
  final double confidence;

  /// Index into the `images[]` array of the request; maps back to a capture.
  @JsonKey(name: 'source_image_index')
  final int sourceImageIndex;
  final String? note;

  Map<String, dynamic> toJson() => _$AnalyzedItemToJson(this);
}

@JsonSerializable()
class AnalyzeUsage {
  const AnalyzeUsage({required this.inputTokens, required this.outputTokens});

  factory AnalyzeUsage.fromJson(Map<String, dynamic> json) =>
      _$AnalyzeUsageFromJson(json);

  @JsonKey(name: 'input_tokens')
  final int inputTokens;

  @JsonKey(name: 'output_tokens')
  final int outputTokens;

  Map<String, dynamic> toJson() => _$AnalyzeUsageToJson(this);
}

/// Successful `POST /v1/analyze-room` body.
@JsonSerializable()
class AnalyzeRoomResponse {
  const AnalyzeRoomResponse({
    required this.requestId,
    required this.model,
    this.promptVersion,
    required this.items,
    required this.usage,
    this.warnings = const [],
  });

  factory AnalyzeRoomResponse.fromJson(Map<String, dynamic> json) =>
      _$AnalyzeRoomResponseFromJson(json);

  @JsonKey(name: 'request_id')
  final String requestId;
  final String model;

  /// Server-side prompt revision; stored on each item for quality metrics.
  @JsonKey(name: 'prompt_version')
  final String? promptVersion;
  final List<AnalyzedItem> items;
  final AnalyzeUsage usage;
  final List<String> warnings;

  Map<String, dynamic> toJson() => _$AnalyzeRoomResponseToJson(this);
}

/// Body of a 429 response.
@JsonSerializable()
class QuotaExceededBody {
  const QuotaExceededBody({required this.limit, required this.resetsAt});

  factory QuotaExceededBody.fromJson(Map<String, dynamic> json) =>
      _$QuotaExceededBodyFromJson(json);

  final int limit;

  @JsonKey(name: 'resets_at')
  final DateTime resetsAt;

  Map<String, dynamic> toJson() => _$QuotaExceededBodyToJson(this);
}
