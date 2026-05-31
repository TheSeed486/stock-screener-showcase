// Program model — top-level screener program.

import 'indicator_model.dart';
import 'stage_model.dart';

class ScreenerV2Program {
  final String name;
  final String universe;
  final List<StageModel> stages;
  final List<CustomIndicator> customIndicators;

  const ScreenerV2Program({
    required this.name,
    this.universe = 'all_a',
    this.stages = const [],
    this.customIndicators = const [],
  });

  ScreenerV2Program copyWith({
    String? name,
    String? universe,
    List<StageModel>? stages,
    List<CustomIndicator>? customIndicators,
  }) => ScreenerV2Program(
    name: name ?? this.name,
    universe: universe ?? this.universe,
    stages: stages ?? this.stages,
    customIndicators: customIndicators ?? this.customIndicators,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'universe': universe,
    'stages': stages.map((s) => s.toJson()).toList(),
    'customIndicators': customIndicators.map((ci) => ci.toJson()).toList(),
  };

  factory ScreenerV2Program.fromJson(Map<String, dynamic> json) => ScreenerV2Program(
    name: json['name'] as String? ?? '未命名策略',
    universe: json['universe'] as String? ?? 'all_a',
    stages: (json['stages'] as List?)
        ?.map((e) => StageModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
    customIndicators: (json['customIndicators'] as List?)
        ?.map((e) => CustomIndicator.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
  );

  static ScreenerV2Program createDefault() => ScreenerV2Program(
    name: '新策略',
    stages: [StageModel.createDefault()],
  );
}
