// Stage model — mirrors crates/dsl/src/pipeline.rs Stage, PointDef, VarDef, Mark.

import 'enums.dart';
import 'expr_node.dart';
import 'indicator_model.dart';
import 'path_ref.dart';
import 'pattern_model.dart';

// ── Condition ───────────────────────────────────────────────

class ConditionModel {
  final String name;
  final ExprNode expr;

  const ConditionModel({required this.name, required this.expr});

  ConditionModel copyWith({String? name, ExprNode? expr}) =>
      ConditionModel(name: name ?? this.name, expr: expr ?? this.expr);

  Map<String, dynamic> toJson() => {
    'name': name,
    'expr': expr.toJson(),
  };

  factory ConditionModel.fromJson(Map<String, dynamic> json) => ConditionModel(
    name: json['name'] as String,
    expr: ExprNode.fromJson(Map<String, dynamic>.from(json['expr'] as Map)),
  );
}

// ── Named Point ─────────────────────────────────────────────

class NamedPointModel {
  final String name;
  final PointDefModel def;

  const NamedPointModel({required this.name, required this.def});

  NamedPointModel copyWith({String? name, PointDefModel? def}) =>
      NamedPointModel(name: name ?? this.name, def: def ?? this.def);

  Map<String, dynamic> toJson() => {
    'name': name,
    'def': def.toJson(),
  };

  factory NamedPointModel.fromJson(Map<String, dynamic> json) => NamedPointModel(
    name: json['name'] as String,
    def: PointDefModel.fromJson(Map<String, dynamic>.from(json['def'] as Map)),
  );

  String get displayLabel => '$name: ${def.displayLabel}';
}

// ── PointDef ────────────────────────────────────────────────

sealed class PointDefModel {
  const PointDefModel();
  Map<String, dynamic> toJson();
  String get displayLabel;

  factory PointDefModel.fromJson(Map<String, dynamic> json) {
    final t = json['t'] as String;
    final v = json['v'];
    switch (t) {
      case 'Where': return WherePointDef.fromJson(Map<String, dynamic>.from(v as Map));
      case 'Offset': return OffsetPointDef(
        fromPoint: (v as Map)['from'] as String,
        delta: (v['delta'] as num).toInt(),
      );
      case 'BlockStart': return BlockStartPointDef(v as String);
      case 'BlockEnd': return BlockEndPointDef(v as String);
      default: return OffsetPointDef(fromPoint: '', delta: 0);
    }
  }
}

class WherePointDef extends PointDefModel {
  final StockRef stock;
  final PathRef from, to;
  final ExprNode pred;
  final PointSelectModel select;

  WherePointDef({
    required this.stock,
    required this.from,
    required this.to,
    required this.pred,
    required this.select,
  });

  @override String get displayLabel => '在 ${from.displayLabel}..${to.displayLabel} 找 ${pred.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Where', 'v': {
    'stock': stock.toJson(),
    'from': from.toJson(),
    'to': to.toJson(),
    'pred': pred.toJson(),
    'select': select.toJson(),
  }};

  factory WherePointDef.fromJson(Map<String, dynamic> json) => WherePointDef(
    stock: StockRef.fromJson(Map<String, dynamic>.from(json['stock'] as Map)),
    from: PathRef.fromJson(Map<String, dynamic>.from(json['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(json['to'] as Map)),
    pred: ExprNode.fromJson(Map<String, dynamic>.from(json['pred'] as Map)),
    select: PointSelectModel.fromJson(json['select']),
  );
}

class OffsetPointDef extends PointDefModel {
  final String fromPoint;
  final int delta;
  OffsetPointDef({required this.fromPoint, required this.delta});
  @override String get displayLabel => '$fromPoint ${delta >= 0 ? '+' : ''}$delta';
  @override Map<String, dynamic> toJson() => {'t': 'Offset', 'v': {'from': fromPoint, 'delta': delta}};
}

class BlockStartPointDef extends PointDefModel {
  final String blockName;
  BlockStartPointDef(this.blockName);
  @override String get displayLabel => '形态块起点: $blockName';
  @override Map<String, dynamic> toJson() => {'t': 'BlockStart', 'v': blockName};
}

class BlockEndPointDef extends PointDefModel {
  final String blockName;
  BlockEndPointDef(this.blockName);
  @override String get displayLabel => '形态块终点: $blockName';
  @override Map<String, dynamic> toJson() => {'t': 'BlockEnd', 'v': blockName};
}

// ── PointSelect ─────────────────────────────────────────────

class PointSelectModel {
  final PointSelectKind kind;
  final int? n;

  const PointSelectModel({required this.kind, this.n});

  dynamic toJson() {
    switch (kind) {
      case PointSelectKind.first: return 'First';
      case PointSelectKind.last: return 'Last';
      case PointSelectKind.nth: return {'Nth': n ?? 0};
      case PointSelectKind.nthFromEnd: return {'NthFromEnd': n ?? 0};
    }
  }

  factory PointSelectModel.fromJson(dynamic json) {
    if (json is String) {
      return PointSelectModel(kind: json == 'First' ? PointSelectKind.first : PointSelectKind.last);
    }
    if (json is Map) {
      if (json.containsKey('Nth')) return PointSelectModel(kind: PointSelectKind.nth, n: json['Nth'] as int);
      if (json.containsKey('NthFromEnd')) return PointSelectModel(kind: PointSelectKind.nthFromEnd, n: json['NthFromEnd'] as int);
    }
    return const PointSelectModel(kind: PointSelectKind.last);
  }

  String get displayLabel {
    switch (kind) {
      case PointSelectKind.first: return '第一个';
      case PointSelectKind.last: return '最后一个';
      case PointSelectKind.nth: return '第${n ?? 0}个';
      case PointSelectKind.nthFromEnd: return '倒数第${n ?? 0}个';
    }
  }
}

// ── VarDef ──────────────────────────────────────────────────

class VarDefModel {
  final String name;
  final ExprNode expr;

  const VarDefModel({required this.name, required this.expr});

  VarDefModel copyWith({String? name, ExprNode? expr}) =>
      VarDefModel(name: name ?? this.name, expr: expr ?? this.expr);

  Map<String, dynamic> toJson() => {
    'name': name,
    'expr': expr.toJson(),
  };

  factory VarDefModel.fromJson(Map<String, dynamic> json) => VarDefModel(
    name: json['name'] as String,
    expr: ExprNode.fromJson(Map<String, dynamic>.from(json['expr'] as Map)),
  );

  String get displayLabel => '$name = ${expr.displayLabel}';
}

// ── Mark ────────────────────────────────────────────────────

class MarkModel {
  final String name;
  final PathRef anchor;
  final ExprNode? value;
  final String? label;

  const MarkModel({required this.name, required this.anchor, this.value, this.label});

  MarkModel copyWith({String? name, PathRef? anchor, ExprNode? value, String? label}) =>
      MarkModel(
        name: name ?? this.name,
        anchor: anchor ?? this.anchor,
        value: value ?? this.value,
        label: label ?? this.label,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'anchor': anchor.toJson(),
    'value': value?.toJson(),
    'label': label,
  };

  factory MarkModel.fromJson(Map<String, dynamic> json) => MarkModel(
    name: json['name'] as String,
    anchor: PathRef.fromJson(Map<String, dynamic>.from(json['anchor'] as Map)),
    value: json['value'] != null ? ExprNode.fromJson(Map<String, dynamic>.from(json['value'] as Map)) : null,
    label: json['label'] as String?,
  );

  String get displayLabel => name;
}

// ── Stage ───────────────────────────────────────────────────

class StageModel {
  final String name;
  final TimeframeEnum timeframe;
  final String? startDate;
  final WindowSizeModel? windowSize;
  final List<IndicatorCallModel> prepare;
  final KlinePatternModel? klinePattern;
  final List<VarDefModel> vars;
  final List<NamedPointModel> points;
  final List<ConditionModel> conditions;
  final List<MarkModel> marks;
  final List<String> extraStocks;

  const StageModel({
    required this.name,
    this.timeframe = TimeframeEnum.daily,
    this.startDate,
    this.windowSize,
    this.prepare = const [],
    this.klinePattern,
    this.vars = const [],
    this.points = const [],
    this.conditions = const [],
    this.marks = const [],
    this.extraStocks = const [],
  });

  StageModel copyWith({
    String? name,
    TimeframeEnum? timeframe,
    String? startDate,
    WindowSizeModel? windowSize,
    List<IndicatorCallModel>? prepare,
    KlinePatternModel? klinePattern,
    List<VarDefModel>? vars,
    List<NamedPointModel>? points,
    List<ConditionModel>? conditions,
    List<MarkModel>? marks,
    List<String>? extraStocks,
    bool clearKlinePattern = false,
    bool clearStartDate = false,
    bool clearWindowSize = false,
  }) => StageModel(
    name: name ?? this.name,
    timeframe: timeframe ?? this.timeframe,
    startDate: clearStartDate ? null : (startDate ?? this.startDate),
    windowSize: clearWindowSize ? null : (windowSize ?? this.windowSize),
    prepare: prepare ?? this.prepare,
    klinePattern: clearKlinePattern ? null : (klinePattern ?? this.klinePattern),
    vars: vars ?? this.vars,
    points: points ?? this.points,
    conditions: conditions ?? this.conditions,
    marks: marks ?? this.marks,
    extraStocks: extraStocks ?? this.extraStocks,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'timeframe': timeframe.toJson(),
    'start_date': startDate,
    'windowsize': windowSize?.toJson(),
    'prepare': {'indicators': prepare.map((c) => c.toJson()).toList()},
    'kline_pattern': klinePattern?.toJson(),
    'vars': vars.map((v) => v.toJson()).toList(),
    'points': points.map((p) => p.toJson()).toList(),
    'conditions': conditions.map((c) => [c.name, c.expr.toJson()]).toList(),
    'marks': marks.map((m) => m.toJson()).toList(),
    'extra_stocks': extraStocks,
  };

  factory StageModel.fromJson(Map<String, dynamic> json) => StageModel(
    name: json['name'] as String,
    timeframe: TimeframeEnum.fromJson(json['timeframe'] as String),
    startDate: json['start_date'] as String?,
    windowSize: json['windowsize'] != null ? WindowSizeModel.fromJson(json['windowsize']) : null,
    prepare: ((json['prepare'] as Map?)?['indicators'] as List?)
        ?.map((e) => IndicatorCallModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
    klinePattern: json['kline_pattern'] != null
        ? KlinePatternModel.fromJson(Map<String, dynamic>.from(json['kline_pattern'] as Map))
        : null,
    vars: (json['vars'] as List?)
        ?.map((e) => VarDefModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
    points: (json['points'] as List?)
        ?.map((e) => NamedPointModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
    conditions: (json['conditions'] as List?)
        ?.map((e) {
          final pair = e as List;
          return ConditionModel(
            name: pair[0] as String,
            expr: ExprNode.fromJson(Map<String, dynamic>.from(pair[1] as Map)),
          );
        }).toList() ?? const [],
    marks: (json['marks'] as List?)
        ?.map((e) => MarkModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList() ?? const [],
    extraStocks: (json['extra_stocks'] as List?)?.cast<String>() ?? const [],
  );

  static StageModel createDefault({String name = '筛选阶段'}) => StageModel(
    name: name,
    windowSize: WindowSizeModel.exact(60),
    conditions: const [],
  );
}
