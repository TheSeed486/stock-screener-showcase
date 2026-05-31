// K-line pattern models — mirrors crates/dsl/src/pattern.rs.

import 'enums.dart';

class KlinePatternModel {
  final String name;
  final List<PatternBlockModel> blocks;

  const KlinePatternModel({required this.name, required this.blocks});

  KlinePatternModel copyWith({String? name, List<PatternBlockModel>? blocks}) =>
      KlinePatternModel(name: name ?? this.name, blocks: blocks ?? this.blocks);

  Map<String, dynamic> toJson() => {
    'name': name,
    'pattern': blocks.map((b) => b.toJson()).toList(),
  };

  factory KlinePatternModel.fromJson(Map<String, dynamic> json) => KlinePatternModel(
    name: json['name'] as String,
    blocks: (json['pattern'] as List)
        .map((e) => PatternBlockModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  String get displayLabel => '$name (${blocks.length}块)';
}

class PatternBlockModel {
  final String blockName;
  final CandleTypeEnum pattern;
  final WindowSizeModel blockSize;
  final bool optional;
  final bool allowOverlapNext;

  const PatternBlockModel({
    required this.blockName,
    required this.pattern,
    required this.blockSize,
    this.optional = false,
    this.allowOverlapNext = false,
  });

  PatternBlockModel copyWith({
    String? blockName,
    CandleTypeEnum? pattern,
    WindowSizeModel? blockSize,
    bool? optional,
    bool? allowOverlapNext,
  }) => PatternBlockModel(
    blockName: blockName ?? this.blockName,
    pattern: pattern ?? this.pattern,
    blockSize: blockSize ?? this.blockSize,
    optional: optional ?? this.optional,
    allowOverlapNext: allowOverlapNext ?? this.allowOverlapNext,
  );

  Map<String, dynamic> toJson() => {
    'block_name': blockName,
    'pattern': pattern.toJson(),
    'block_size': blockSize.toJson(),
    'optional': optional,
    'allow_overlap_next': allowOverlapNext,
  };

  factory PatternBlockModel.fromJson(Map<String, dynamic> json) => PatternBlockModel(
    blockName: json['block_name'] as String,
    pattern: CandleTypeEnum.fromJson(json['pattern'] as String),
    blockSize: WindowSizeModel.fromJson(json['block_size']),
    optional: json['optional'] as bool? ?? false,
    allowOverlapNext: json['allow_overlap_next'] as bool? ?? false,
  );
}

// ── WindowSize ──────────────────────────────────────────────

sealed class WindowSizeModel {
  const WindowSizeModel();
  Map<String, dynamic> toJson();

  static WindowSizeModel exact(int n) => ExactWindowSize(n);
  static WindowSizeModel range({int? min, int? max}) =>
      RangeWindowSize(min: min, max: max);

  factory WindowSizeModel.fromJson(dynamic json) {
    if (json is Map) {
      if (json.containsKey('Exact')) return ExactWindowSize(json['Exact'] as int);
      if (json.containsKey('Range')) {
        final r = Map<String, dynamic>.from(json['Range'] as Map);
        return RangeWindowSize(min: r['min'] as int?, max: r['max'] as int?);
      }
    }
    if (json is int) return ExactWindowSize(json);
    return ExactWindowSize(20);
  }

  String get displayLabel;
}

class ExactWindowSize extends WindowSizeModel {
  final int n;
  ExactWindowSize(this.n);
  @override Map<String, dynamic> toJson() => {'Exact': n};
  @override String get displayLabel => '$n根';
}

class RangeWindowSize extends WindowSizeModel {
  final int? min;
  final int? max;
  RangeWindowSize({this.min, this.max});
  @override Map<String, dynamic> toJson() => {'Range': {'min': min, 'max': max}};
  @override String get displayLabel => '${min ?? ''}~${max ?? ''}根';
}
