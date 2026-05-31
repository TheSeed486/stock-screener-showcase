// Screener data models — mirrors the crates/dsl Pipeline + ModuleRegistry types.

// ── Enums ──────────────────────────────────────────────────────

enum FieldName {
  open, high, low, close, volume, amount,
  pctChange, amplitude, turnover;

  String get label {
    switch (this) {
      case FieldName.open: return '开盘价';
      case FieldName.high: return '最高价';
      case FieldName.low: return '最低价';
      case FieldName.close: return '收盘价';
      case FieldName.volume: return '成交量';
      case FieldName.amount: return '成交额';
      case FieldName.pctChange: return '涨跌幅';
      case FieldName.amplitude: return '振幅';
      case FieldName.turnover: return '换手率';
    }
  }

  String get jsonKey {
    switch (this) {
      case FieldName.pctChange: return 'pct_change';
      default: return name;
    }
  }
}

enum MetricTransform { raw, sma, ema }

extension MetricTransformX on MetricTransform {
  String get label {
    switch (this) {
      case MetricTransform.raw: return '原始值';
      case MetricTransform.sma: return '均线(SMA)';
      case MetricTransform.ema: return '均线(EMA)';
    }
  }

  bool get requiresWindow => this != MetricTransform.raw;
}

enum CompareOp {
  gt, gte, lt, lte, eq, neq;

  String get symbol {
    switch (this) {
      case CompareOp.gt: return '>';
      case CompareOp.gte: return '>=';
      case CompareOp.lt: return '<';
      case CompareOp.lte: return '<=';
      case CompareOp.eq: return '==';
      case CompareOp.neq: return '!=';
    }
  }

  String get label {
    switch (this) {
      case CompareOp.gt: return '大于';
      case CompareOp.gte: return '大于等于';
      case CompareOp.lt: return '小于';
      case CompareOp.lte: return '小于等于';
      case CompareOp.eq: return '等于';
      case CompareOp.neq: return '不等于';
    }
  }
}

enum CrossDirection {
  up, down;

  String get label {
    switch (this) {
      case CrossDirection.up: return '向上穿越';
      case CrossDirection.down: return '向下穿越';
    }
  }

  String get exprTag {
    switch (this) {
      case CrossDirection.up: return 'CrossUp';
      case CrossDirection.down: return 'CrossDown';
    }
  }
}

enum CandlePattern {
  bullishEngulfing, bearishEngulfing;

  String get label {
    switch (this) {
      case CandlePattern.bullishEngulfing: return '看涨吞没';
      case CandlePattern.bearishEngulfing: return '看跌吞没';
    }
  }

  String get exprValue {
    switch (this) {
      case CandlePattern.bullishEngulfing: return 'Up';
      case CandlePattern.bearishEngulfing: return 'Down';
    }
  }
}

enum GapDirection {
  up, down;

  String get label {
    switch (this) {
      case GapDirection.up: return '向上跳空';
      case GapDirection.down: return '向下跳空';
    }
  }
}

enum GroupLogic {
  and, or;

  String get label {
    switch (this) {
      case GroupLogic.and: return 'AND';
      case GroupLogic.or: return 'OR';
    }
  }

  String get exprTag => name == 'and' ? 'And' : 'Or';
}

enum Timeframe {
  daily, weekly, monthly;

  String get label {
    switch (this) {
      case Timeframe.daily: return '日线';
      case Timeframe.weekly: return '周线';
      case Timeframe.monthly: return '月线';
    }
  }

  String toJson() {
    switch (this) {
      case Timeframe.daily: return 'Daily';
      case Timeframe.weekly: return 'Weekly';
      case Timeframe.monthly: return 'Monthly';
    }
  }

  static Timeframe fromJson(String s) {
    switch (s) {
      case 'weekly': return Timeframe.weekly;
      case 'monthly': return Timeframe.monthly;
      default: return Timeframe.daily;
    }
  }
}

enum ConditionKind { compare, cross, candle, gap }

// ── Metric ─────────────────────────────────────────────────────

class Metric {
  final FieldName field;
  final MetricTransform transform;
  final int window;
  /// 引用自定义指标的输出列名（如 "my_boll_upper_20"），非 null 时忽略 field/transform/window
  final String? customColumn;

  const Metric({
    required this.field,
    this.transform = MetricTransform.raw,
    this.window = 20,
    this.customColumn,
  });

  Metric copyWith({
    FieldName? field,
    MetricTransform? transform,
    int? window,
    String? customColumn,
  }) => Metric(
    field: field ?? this.field,
    transform: transform ?? this.transform,
    window: window ?? this.window,
    customColumn: customColumn ?? this.customColumn,
  );

  bool get isCustom => customColumn != null;

  String get label {
    if (customColumn != null) return customColumn!;
    final base = field.label;
    switch (transform) {
      case MetricTransform.raw: return base;
      case MetricTransform.sma: return '$base SMA($window)';
      case MetricTransform.ema: return '$base EMA($window)';
    }
  }

  Map<String, dynamic> toJson() => {
    'field': field.name,
    'transform': transform.name,
    'window': window,
    if (customColumn != null) 'customColumn': customColumn,
  };

  factory Metric.fromJson(Map<String, dynamic> json) => Metric(
    field: FieldName.values.firstWhere((e) => e.name == json['field']),
    transform: MetricTransform.values.firstWhere((e) => e.name == json['transform']),
    window: json['window'] as int,
    customColumn: json['customColumn'] as String?,
  );
}

// ── Operand ────────────────────────────────────────────────────

class Operand {
  final double? literalValue;
  final Metric? metric;
  final double multiplier;

  const Operand.literal(this.literalValue)
    : metric = null, multiplier = 1.0;

  const Operand.metric(this.metric, {this.multiplier = 1.0})
    : literalValue = null;

  bool get isLiteral => literalValue != null;

  Operand copyWith({
    double? literalValue,
    Metric? metric,
    double? multiplier,
    bool? useLiteral,
  }) {
    if (useLiteral ?? isLiteral) {
      return Operand.literal(literalValue ?? this.literalValue ?? 0);
    }
    return Operand.metric(
      metric ?? this.metric ?? const Metric(field: FieldName.close),
      multiplier: multiplier ?? this.multiplier,
    );
  }

  String get label {
    if (isLiteral) return _fmt(literalValue!);
    final base = metric!.label;
    if ((multiplier - 1.0).abs() < 0.000001) return base;
    return '$base × ${_fmt(multiplier)}';
  }

  Map<String, dynamic> toJson() => {
    'isLiteral': isLiteral,
    if (isLiteral) 'literalValue': literalValue,
    if (!isLiteral) 'metric': metric!.toJson(),
    'multiplier': multiplier,
  };

  factory Operand.fromJson(Map<String, dynamic> json) {
    if (json['isLiteral'] as bool) {
      return Operand.literal((json['literalValue'] as num).toDouble());
    }
    return Operand.metric(
      Metric.fromJson(Map<String, dynamic>.from(json['metric'] as Map)),
      multiplier: (json['multiplier'] as num).toDouble(),
    );
  }
}

// ── Condition (sealed) ─────────────────────────────────────────

sealed class Condition {
  ConditionKind get kind;
  String get summary;
  Map<String, dynamic> toJson();

  factory Condition.fromJson(Map<String, dynamic> json) {
    return switch (json['kind'] as String) {
      'compare' => CompareCondition.fromJson(json),
      'cross' => CrossCondition.fromJson(json),
      'candle' => CandleCondition.fromJson(json),
      'gap' => GapCondition.fromJson(json),
      _ => throw ArgumentError('Unknown Condition kind: ${json['kind']}'),
    };
  }
}

class CompareCondition implements Condition {
  @override final ConditionKind kind = ConditionKind.compare;
  final Metric left;
  final CompareOp op;
  final Operand right;

  const CompareCondition({required this.left, required this.op, required this.right});

  CompareCondition copyWith({Metric? left, CompareOp? op, Operand? right}) =>
      CompareCondition(left: left ?? this.left, op: op ?? this.op, right: right ?? this.right);

  @override String get summary => '${left.label} ${op.label} ${right.label}';

  @override Map<String, dynamic> toJson() => {
    'kind': 'compare',
    'left': left.toJson(),
    'op': op.name,
    'right': right.toJson(),
  };

  factory CompareCondition.fromJson(Map<String, dynamic> json) => CompareCondition(
    left: Metric.fromJson(Map<String, dynamic>.from(json['left'] as Map)),
    op: CompareOp.values.firstWhere((e) => e.name == json['op']),
    right: Operand.fromJson(Map<String, dynamic>.from(json['right'] as Map)),
  );
}

class CrossCondition implements Condition {
  @override final ConditionKind kind = ConditionKind.cross;
  final CrossDirection direction;
  final Metric left;
  final Metric right;

  const CrossCondition({required this.direction, required this.left, required this.right});

  CrossCondition copyWith({CrossDirection? direction, Metric? left, Metric? right}) =>
      CrossCondition(direction: direction ?? this.direction, left: left ?? this.left, right: right ?? this.right);

  @override String get summary => '${left.label} ${direction.label} ${right.label}';

  @override Map<String, dynamic> toJson() => {
    'kind': 'cross',
    'direction': direction.name,
    'left': left.toJson(),
    'right': right.toJson(),
  };

  factory CrossCondition.fromJson(Map<String, dynamic> json) => CrossCondition(
    direction: CrossDirection.values.firstWhere((e) => e.name == json['direction']),
    left: Metric.fromJson(Map<String, dynamic>.from(json['left'] as Map)),
    right: Metric.fromJson(Map<String, dynamic>.from(json['right'] as Map)),
  );
}

class CandleCondition implements Condition {
  @override final ConditionKind kind = ConditionKind.candle;
  final CandlePattern pattern;

  const CandleCondition({required this.pattern});

  CandleCondition copyWith({CandlePattern? pattern}) =>
      CandleCondition(pattern: pattern ?? this.pattern);

  @override String get summary => pattern.label;

  @override Map<String, dynamic> toJson() => {
    'kind': 'candle',
    'pattern': pattern.name,
  };

  factory CandleCondition.fromJson(Map<String, dynamic> json) => CandleCondition(
    pattern: CandlePattern.values.firstWhere((e) => e.name == json['pattern']),
  );
}

class GapCondition implements Condition {
  @override final ConditionKind kind = ConditionKind.gap;
  final GapDirection direction;
  final double thresholdPct;

  const GapCondition({required this.direction, required this.thresholdPct});

  GapCondition copyWith({GapDirection? direction, double? thresholdPct}) =>
      GapCondition(direction: direction ?? this.direction, thresholdPct: thresholdPct ?? this.thresholdPct);

  @override String get summary => '${direction.label} ${_fmt(thresholdPct)}%';

  @override Map<String, dynamic> toJson() => {
    'kind': 'gap',
    'direction': direction.name,
    'thresholdPct': thresholdPct,
  };

  factory GapCondition.fromJson(Map<String, dynamic> json) => GapCondition(
    direction: GapDirection.values.firstWhere((e) => e.name == json['direction']),
    thresholdPct: (json['thresholdPct'] as num).toDouble(),
  );
}

// ── ConditionGroup ─────────────────────────────────────────────

class ConditionGroup {
  final String id;
  final String name;
  final GroupLogic logic;
  final List<Condition> conditions;

  const ConditionGroup({
    required this.id,
    required this.name,
    required this.logic,
    required this.conditions,
  });

  ConditionGroup copyWith({
    String? id,
    String? name,
    GroupLogic? logic,
    List<Condition>? conditions,
  }) => ConditionGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    logic: logic ?? this.logic,
    conditions: conditions ?? this.conditions,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'logic': logic.name,
    'conditions': conditions.map((c) => c.toJson()).toList(),
  };

  factory ConditionGroup.fromJson(Map<String, dynamic> json) => ConditionGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    logic: GroupLogic.values.firstWhere((e) => e.name == json['logic']),
    conditions: (json['conditions'] as List)
        .map((e) => Condition.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

// ── Indicator formula nodes (mirrors Rust IndicatorFormula) ────

sealed class IndicatorFormulaNode {
  Map<String, dynamic> toJson();
}

class ColNode implements IndicatorFormulaNode {
  final String column;
  const ColNode(this.column);
  @override Map<String, dynamic> toJson() => {'t': 'Col', 'v': column};
}

class LitNode implements IndicatorFormulaNode {
  final double value;
  const LitNode(this.value);
  @override Map<String, dynamic> toJson() => {'t': 'Lit', 'v': value};
}

class ParamNode implements IndicatorFormulaNode {
  final String paramName;
  const ParamNode(this.paramName);
  @override Map<String, dynamic> toJson() => {'t': 'Param', 'v': paramName};
}

class RollingMeanNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  const RollingMeanNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingMean', 'v': {'src': src.toJson(), 'period': period.toJson()}};
}

class RollingStdNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  const RollingStdNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingStd', 'v': {'src': src.toJson(), 'period': period.toJson()}};
}

class RollingMaxNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  const RollingMaxNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingMax', 'v': {'src': src.toJson(), 'period': period.toJson()}};
}

class RollingMinNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  const RollingMinNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingMin', 'v': {'src': src.toJson(), 'period': period.toJson()}};
}

class RollingSumNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  const RollingSumNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingSum', 'v': {'src': src.toJson(), 'period': period.toJson()}};
}

class ShiftNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final int periods;
  const ShiftNode({required this.src, required this.periods});
  @override Map<String, dynamic> toJson() => {'t': 'Shift', 'v': {'src': src.toJson(), 'periods': LitNode(periods.toDouble()).toJson()}};
}

class AddNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode a;
  final IndicatorFormulaNode b;
  const AddNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Add', 'v': [a.toJson(), b.toJson()]};
}

class SubNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode a;
  final IndicatorFormulaNode b;
  const SubNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Sub', 'v': [a.toJson(), b.toJson()]};
}

class MulNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode a;
  final IndicatorFormulaNode b;
  const MulNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Mul', 'v': [a.toJson(), b.toJson()]};
}

class DivNode implements IndicatorFormulaNode {
  final IndicatorFormulaNode a;
  final IndicatorFormulaNode b;
  const DivNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Div', 'v': [a.toJson(), b.toJson()]};
}

// ── Custom indicator ───────────────────────────────────────────

class IndicatorOutputDef {
  final String colNameTemplate;
  final IndicatorFormulaNode formula;

  const IndicatorOutputDef({required this.colNameTemplate, required this.formula});

  IndicatorOutputDef copyWith({String? colNameTemplate, IndicatorFormulaNode? formula}) =>
      IndicatorOutputDef(colNameTemplate: colNameTemplate ?? this.colNameTemplate, formula: formula ?? this.formula);

  String renderColumnName(Map<String, String> paramValues) {
    String out = colNameTemplate;
    for (final entry in paramValues.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'colNameTemplate': colNameTemplate,
    'formula': formula.toJson(),
  };

  factory IndicatorOutputDef.fromJson(Map<String, dynamic> json) => IndicatorOutputDef(
    colNameTemplate: json['colNameTemplate'] as String,
    formula: _formulaFromJson(json['formula'] as Map<String, dynamic>),
  );
}

class CustomIndicator {
  final String id;
  final List<String> paramNames;
  final String label;
  final List<IndicatorOutputDef> outputs;

  const CustomIndicator({
    required this.id,
    required this.paramNames,
    required this.label,
    required this.outputs,
  });

  CustomIndicator copyWith({
    String? id,
    List<String>? paramNames,
    String? label,
    List<IndicatorOutputDef>? outputs,
  }) => CustomIndicator(
    id: id ?? this.id,
    paramNames: paramNames ?? this.paramNames,
    label: label ?? this.label,
    outputs: outputs ?? this.outputs,
  );

  /// 用给定参数值渲染所有输出列名
  List<String> renderColumnNames(Map<String, String> paramValues) =>
      outputs.map((o) => o.renderColumnName(paramValues)).toList();

  Map<String, dynamic> toJson() => {
    'id': id,
    'paramNames': paramNames,
    'label': label,
    'outputs': outputs.map((o) => o.toJson()).toList(),
  };

  factory CustomIndicator.fromJson(Map<String, dynamic> json) => CustomIndicator(
    id: json['id'] as String,
    paramNames: (json['paramNames'] as List).cast<String>(),
    label: json['label'] as String,
    outputs: (json['outputs'] as List)
        .map((e) => IndicatorOutputDef.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  /// 编译为 ModuleRegistry 中的 IndicatorModDef JSON
  Map<String, dynamic> toModDefJson() => {
    'id': id,
    'param_names': paramNames,
    'outputs': outputs.map((o) => {
      'col_name_template': o.colNameTemplate,
      'formula': o.formula.toJson(),
    }).toList(),
  };
}

// ── ScreenerProgram ────────────────────────────────────────────

class ScreenerProgram {
  final String name;
  final String universe;
  final Timeframe timeframe;
  final int windowSize;
  final GroupLogic groupLogic;
  final int resultLimit;
  final List<ConditionGroup> groups;
  final List<CustomIndicator> customIndicators;

  const ScreenerProgram({
    required this.name,
    this.universe = 'all_a',
    this.timeframe = Timeframe.daily,
    this.windowSize = 60,
    this.groupLogic = GroupLogic.and,
    this.resultLimit = 100,
    this.groups = const [],
    this.customIndicators = const [],
  });

  ScreenerProgram copyWith({
    String? name,
    String? universe,
    Timeframe? timeframe,
    int? windowSize,
    GroupLogic? groupLogic,
    int? resultLimit,
    List<ConditionGroup>? groups,
    List<CustomIndicator>? customIndicators,
  }) => ScreenerProgram(
    name: name ?? this.name,
    universe: universe ?? this.universe,
    timeframe: timeframe ?? this.timeframe,
    windowSize: windowSize ?? this.windowSize,
    groupLogic: groupLogic ?? this.groupLogic,
    resultLimit: resultLimit ?? this.resultLimit,
    groups: groups ?? this.groups,
    customIndicators: customIndicators ?? this.customIndicators,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'universe': universe,
    'timeframe': timeframe.name,
    'windowSize': windowSize,
    'groupLogic': groupLogic.name,
    'resultLimit': resultLimit,
    'groups': groups.map((g) => g.toJson()).toList(),
    'customIndicators': customIndicators.map((ci) => ci.toJson()).toList(),
  };

  factory ScreenerProgram.fromJson(Map<String, dynamic> json) => ScreenerProgram(
    name: json['name'] as String,
    universe: json['universe'] as String? ?? 'all_a',
    timeframe: Timeframe.values.firstWhere(
      (e) => e.name == json['timeframe'],
      orElse: () => Timeframe.daily,
    ),
    windowSize: json['windowSize'] as int? ?? 60,
    groupLogic: GroupLogic.values.firstWhere(
      (e) => e.name == json['groupLogic'],
      orElse: () => GroupLogic.and,
    ),
    resultLimit: json['resultLimit'] as int? ?? 100,
    groups: (json['groups'] as List?)
        ?.map((e) => ConditionGroup.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
    customIndicators: (json['customIndicators'] as List?)
        ?.map((e) => CustomIndicator.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
  );

  static ScreenerProgram createDefault() => ScreenerProgram(
    name: '趋势突破',
    groups: [
      ConditionGroup(
        id: 'group_1',
        name: '日线信号组',
        logic: GroupLogic.and,
        conditions: [
          CrossCondition(
            direction: CrossDirection.up,
            left: const Metric(field: FieldName.close),
            right: const Metric(field: FieldName.close, transform: MetricTransform.sma, window: 20),
          ),
          CompareCondition(
            left: const Metric(field: FieldName.volume),
            op: CompareOp.gt,
            right: Operand.metric(
              const Metric(field: FieldName.volume, transform: MetricTransform.sma, window: 5),
              multiplier: 1.8,
            ),
          ),
        ],
      ),
    ],
  );
}

// ── Helpers ────────────────────────────────────────────────────

String _fmt(num x) {
  if (x == x.roundToDouble()) return x.toInt().toString();
  return x.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

IndicatorFormulaNode _formulaFromJson(Map<String, dynamic> json) {
  return switch (json['t'] as String) {
    'Col' => ColNode(json['v'] as String),
    'Lit' => LitNode((json['v'] as num).toDouble()),
    'Param' => ParamNode(json['v'] as String),
    'RollingMean' => RollingMeanNode(
      src: _formulaFromJson(Map<String, dynamic>.from(json['v']['src'] as Map)),
      period: _formulaFromJson(Map<String, dynamic>.from(json['v']['period'] as Map)),
    ),
    'RollingStd' => RollingStdNode(
      src: _formulaFromJson(Map<String, dynamic>.from(json['v']['src'] as Map)),
      period: _formulaFromJson(Map<String, dynamic>.from(json['v']['period'] as Map)),
    ),
    'RollingMax' => RollingMaxNode(
      src: _formulaFromJson(Map<String, dynamic>.from(json['v']['src'] as Map)),
      period: _formulaFromJson(Map<String, dynamic>.from(json['v']['period'] as Map)),
    ),
    'RollingMin' => RollingMinNode(
      src: _formulaFromJson(Map<String, dynamic>.from(json['v']['src'] as Map)),
      period: _formulaFromJson(Map<String, dynamic>.from(json['v']['period'] as Map)),
    ),
    'RollingSum' => RollingSumNode(
      src: _formulaFromJson(Map<String, dynamic>.from(json['v']['src'] as Map)),
      period: _formulaFromJson(Map<String, dynamic>.from(json['v']['period'] as Map)),
    ),
    'Shift' => ShiftNode(
      src: _formulaFromJson(Map<String, dynamic>.from(json['v']['src'] as Map)),
      periods: (json['v']['periods']['v'] as num).toInt(),
    ),
    'Add' => AddNode(
      a: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[0] as Map)),
      b: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[1] as Map)),
    ),
    'Sub' => SubNode(
      a: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[0] as Map)),
      b: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[1] as Map)),
    ),
    'Mul' => MulNode(
      a: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[0] as Map)),
      b: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[1] as Map)),
    ),
    'Div' => DivNode(
      a: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[0] as Map)),
      b: _formulaFromJson(Map<String, dynamic>.from((json['v'] as List)[1] as Map)),
    ),
    _ => throw ArgumentError('Unknown formula node: ${json['t']}'),
  };
}

const fieldNameOptions = <FieldName>[
  FieldName.open, FieldName.high, FieldName.low, FieldName.close,
  FieldName.volume, FieldName.amount, FieldName.pctChange,
  FieldName.amplitude, FieldName.turnover,
];

const windowOptions = <int>[3, 5, 10, 20, 30, 60, 120];
