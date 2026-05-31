// Indicator models — ported from screener_models.dart with fixes.
// Mirrors crates/dsl/src/mod_def/indicator.rs.

// ── Indicator formula nodes (mirrors Rust IndicatorFormula) ──

sealed class IndicatorFormulaNode {
  Map<String, dynamic> toJson();
  String get displayLabel;

  static IndicatorFormulaNode fromJson(Map<String, dynamic> json) {
    final t = json['t'] as String;
    final v = json['v'];
    switch (t) {
      case 'Col': return ColNode(v as String);
      case 'Lit': return LitNode((v as num).toDouble());
      case 'Param': return ParamNode(v as String);
      case 'RollingMean': return RollingMeanNode(
        src: fromJson(Map<String, dynamic>.from((v as Map)['src'] as Map)),
        period: fromJson(Map<String, dynamic>.from(v['period'] as Map)),
      );
      case 'RollingStd': return RollingStdNode(
        src: fromJson(Map<String, dynamic>.from((v as Map)['src'] as Map)),
        period: fromJson(Map<String, dynamic>.from(v['period'] as Map)),
      );
      case 'RollingMax': return RollingMaxNode(
        src: fromJson(Map<String, dynamic>.from((v as Map)['src'] as Map)),
        period: fromJson(Map<String, dynamic>.from(v['period'] as Map)),
      );
      case 'RollingMin': return RollingMinNode(
        src: fromJson(Map<String, dynamic>.from((v as Map)['src'] as Map)),
        period: fromJson(Map<String, dynamic>.from(v['period'] as Map)),
      );
      case 'RollingSum': return RollingSumNode(
        src: fromJson(Map<String, dynamic>.from((v as Map)['src'] as Map)),
        period: fromJson(Map<String, dynamic>.from(v['period'] as Map)),
      );
      case 'Shift': return ShiftNode(
        src: fromJson(Map<String, dynamic>.from((v as Map)['src'] as Map)),
        periods: v['periods'] is Map && v['periods']['v'] is num
            ? (v['periods']['v'] as num).toInt()
            : 1,
      );
      case 'Add': return AddNode(
        a: _child(v, 0), b: _child(v, 1),
      );
      case 'Sub': return SubNode(
        a: _child(v, 0), b: _child(v, 1),
      );
      case 'Mul': return MulNode(
        a: _child(v, 0), b: _child(v, 1),
      );
      case 'Div': return DivNode(
        a: _child(v, 0), b: _child(v, 1),
      );
      case 'Abs': return AbsNode(fromJson(Map<String, dynamic>.from(v as Map)));
      case 'Neg': return NegNode(fromJson(Map<String, dynamic>.from(v as Map)));
      case 'IfElse': return IfElseNode(
        cond: fromJson(Map<String, dynamic>.from((v as Map)['cond'] as Map)),
        thenVal: fromJson(Map<String, dynamic>.from(v['then_val'] as Map)),
        elseVal: fromJson(Map<String, dynamic>.from(v['else_val'] as Map)),
      );
      default: return ColNode('close');
    }
  }

  static IndicatorFormulaNode _child(dynamic v, int i) =>
      fromJson(Map<String, dynamic>.from((v as List)[i] as Map));
}

class ColNode extends IndicatorFormulaNode {
  final String column;
  ColNode(this.column);
  @override Map<String, dynamic> toJson() => {'t': 'Col', 'v': column};
  @override String get displayLabel => column;
}

class LitNode extends IndicatorFormulaNode {
  final double value;
  LitNode(this.value);
  @override Map<String, dynamic> toJson() => {'t': 'Lit', 'v': value};
  @override String get displayLabel => _fmt(value);
}

class ParamNode extends IndicatorFormulaNode {
  final String paramName;
  ParamNode(this.paramName);
  @override Map<String, dynamic> toJson() => {'t': 'Param', 'v': paramName};
  @override String get displayLabel => '参数:$paramName';
}

class RollingMeanNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  RollingMeanNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingMean', 'v': {'src': src.toJson(), 'period': period.toJson()}};
  @override String get displayLabel => 'SMA(${src.displayLabel}, ${period.displayLabel})';
}

class RollingStdNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  RollingStdNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingStd', 'v': {'src': src.toJson(), 'period': period.toJson()}};
  @override String get displayLabel => 'StdDev(${src.displayLabel}, ${period.displayLabel})';
}

class RollingMaxNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  RollingMaxNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingMax', 'v': {'src': src.toJson(), 'period': period.toJson()}};
  @override String get displayLabel => 'Max(${src.displayLabel}, ${period.displayLabel})';
}

class RollingMinNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  RollingMinNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingMin', 'v': {'src': src.toJson(), 'period': period.toJson()}};
  @override String get displayLabel => 'Min(${src.displayLabel}, ${period.displayLabel})';
}

class RollingSumNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final IndicatorFormulaNode period;
  RollingSumNode({required this.src, required this.period});
  @override Map<String, dynamic> toJson() => {'t': 'RollingSum', 'v': {'src': src.toJson(), 'period': period.toJson()}};
  @override String get displayLabel => 'Sum(${src.displayLabel}, ${period.displayLabel})';
}

class ShiftNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode src;
  final int periods;
  ShiftNode({required this.src, required this.periods});
  @override Map<String, dynamic> toJson() => {'t': 'Shift', 'v': {'src': src.toJson(), 'periods': LitNode(periods.toDouble()).toJson()}};
  @override String get displayLabel => 'Shift(${src.displayLabel}, $periods)';
}

class AddNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode a, b;
  AddNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Add', 'v': [a.toJson(), b.toJson()]};
  @override String get displayLabel => '(${a.displayLabel} + ${b.displayLabel})';
}

class SubNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode a, b;
  SubNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Sub', 'v': [a.toJson(), b.toJson()]};
  @override String get displayLabel => '(${a.displayLabel} - ${b.displayLabel})';
}

class MulNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode a, b;
  MulNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Mul', 'v': [a.toJson(), b.toJson()]};
  @override String get displayLabel => '(${a.displayLabel} * ${b.displayLabel})';
}

class DivNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode a, b;
  DivNode({required this.a, required this.b});
  @override Map<String, dynamic> toJson() => {'t': 'Div', 'v': [a.toJson(), b.toJson()]};
  @override String get displayLabel => '(${a.displayLabel} / ${b.displayLabel})';
}

class AbsNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode child;
  AbsNode(this.child);
  @override Map<String, dynamic> toJson() => {'t': 'Abs', 'v': child.toJson()};
  @override String get displayLabel => 'abs(${child.displayLabel})';
}

class NegNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode child;
  NegNode(this.child);
  @override Map<String, dynamic> toJson() => {'t': 'Neg', 'v': child.toJson()};
  @override String get displayLabel => '-(${child.displayLabel})';
}

class IfElseNode extends IndicatorFormulaNode {
  final IndicatorFormulaNode cond, thenVal, elseVal;
  IfElseNode({required this.cond, required this.thenVal, required this.elseVal});
  @override Map<String, dynamic> toJson() => {'t': 'IfElse', 'v': {
    'cond': cond.toJson(),
    'then_val': thenVal.toJson(),
    'else_val': elseVal.toJson(),
  }};
  @override String get displayLabel => 'if(${cond.displayLabel}) ? ${thenVal.displayLabel} : ${elseVal.displayLabel}';
}

// ── Indicator output definition ─────────────────────────────

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
    formula: IndicatorFormulaNode.fromJson(Map<String, dynamic>.from(json['formula'] as Map)),
  );
}

// ── Custom indicator ────────────────────────────────────────

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

  Map<String, dynamic> toModDefJson() => {
    'id': id,
    'param_names': paramNames,
    'outputs': outputs.map((o) => {
      'col_name_template': o.colNameTemplate,
      'formula': o.formula.toJson(),
    }).toList(),
  };
}

// ── Indicator call (in a stage's prepare) ───────────────────

class IndicatorCallModel {
  final String moduleId;
  final Map<String, ParamValue> params;

  const IndicatorCallModel({required this.moduleId, required this.params});

  IndicatorCallModel copyWith({String? moduleId, Map<String, ParamValue>? params}) =>
      IndicatorCallModel(moduleId: moduleId ?? this.moduleId, params: params ?? this.params);

  Map<String, dynamic> toJson() => {
    'module_id': moduleId,
    'params': {for (final e in params.entries) e.key: e.value.toJson()},
  };

  factory IndicatorCallModel.fromJson(Map<String, dynamic> json) => IndicatorCallModel(
    moduleId: json['module_id'] as String,
    params: (json['params'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, ParamValue.fromJson(Map<String, dynamic>.from(v as Map))),
    ),
  );

  String get displayLabel => '$moduleId(${params.entries.map((e) => '${e.key}=${e.value.displayValue}').join(', ')})';
}

// ── Param value ─────────────────────────────────────────────

class ParamValue {
  final String type; // 'Int', 'Float', 'Str', 'Bool'
  final dynamic value;

  const ParamValue({required this.type, required this.value});

  Map<String, dynamic> toJson() => {'type': type, 'value': value};

  factory ParamValue.fromJson(Map<String, dynamic> json) =>
      ParamValue(type: json['type'] as String, value: json['value']);

  factory ParamValue.intVal(int v) => ParamValue(type: 'Int', value: v);
  factory ParamValue.floatVal(double v) => ParamValue(type: 'Float', value: v);
  factory ParamValue.strVal(String v) => ParamValue(type: 'Str', value: v);
  factory ParamValue.boolVal(bool v) => ParamValue(type: 'Bool', value: v);

  String get displayValue => '$value';
}

String _fmt(num x) {
  if (x == x.roundToDouble()) return x.toInt().toString();
  return x.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
