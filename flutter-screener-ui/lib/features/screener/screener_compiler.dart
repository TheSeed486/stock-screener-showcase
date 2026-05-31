import 'dart:convert';
import 'screener_models.dart';

/// Compile a ScreenerProgram into (pipelineJson, registryJson).
/// registryJson merges the default registry with custom indicators.
({String pipelineJson, String registryJson}) compileScreener(
  ScreenerProgram program, {
  String defaultRegistryJson = '{}',
}) {
  // 1. Merge custom indicators into registry
  final registry = _mergeRegistry(defaultRegistryJson, program.customIndicators);
  final registryJson = jsonEncode(registry);

  // 2. Collect indicator calls needed by conditions
  final indicatorCalls = <String, Map<String, dynamic>>{};
  _collectIndicatorCalls(program, indicatorCalls);

  // 3. Build vars from indicator outputs (and custom indicator columns)
  final vars = <Map<String, dynamic>>[];
  for (final entry in indicatorCalls.entries) {
    vars.add({'name': entry.key, 'expr': {'t': 'Var', 'v': entry.key}});
  }

  // 4. Compile groups into conditions expression
  final groupExprs = <dynamic>[];
  for (final g in program.groups) {
    final expr = _compileGroup(g);
    if (expr != null) groupExprs.add(expr);
  }

  dynamic combinedExpr;
  if (groupExprs.isEmpty) {
    combinedExpr = _exprBool(true);
  } else if (groupExprs.length == 1) {
    combinedExpr = groupExprs.first;
  } else {
    final conn = program.groupLogic.exprTag;
    combinedExpr = groupExprs
        .skip(1)
        .fold(groupExprs.first, (a, b) => _exprBin(conn, a, b));
  }

  final stage = {
    'name': program.name,
    'timeframe': program.timeframe.toJson(),
    'start_date': null,
    'windowsize': {'Exact': program.windowSize},
    'prepare': {
      'indicators': indicatorCalls.values.toList(),
    },
    'kline_pattern': null,
    'vars': vars,
    'points': [],
    'conditions': [
      ['filter', combinedExpr],
    ],
    'marks': [],
    'extra_stocks': [],
  };

  return (
    pipelineJson: jsonEncode({'stages': [stage]}),
    registryJson: registryJson,
  );
}

// ── Registry merge ─────────────────────────────────────────────

Map<String, dynamic> _mergeRegistry(
  String defaultJson,
  List<CustomIndicator> customIndicators,
) {
  Map<String, dynamic> reg;
  try {
    reg = Map<String, dynamic>.from(jsonDecode(defaultJson) as Map);
  } catch (_) {
    reg = {'indicators': <String, dynamic>{}, 'intraday': <String, dynamic>{}};
  }
  final indicators = Map<String, dynamic>.from(reg['indicators'] as Map? ?? {});
  for (final ci in customIndicators) {
    indicators[ci.id] = ci.toModDefJson();
  }
  reg['indicators'] = indicators;
  if (!reg.containsKey('intraday')) {
    reg['intraday'] = <String, dynamic>{};
  }
  return reg;
}

// ── Indicator collection ──────────────────────────────────────

void _collectIndicatorCalls(
  ScreenerProgram program,
  Map<String, Map<String, dynamic>> calls,
) {
  for (final g in program.groups) {
    for (final c in g.conditions) {
      _collectMetricIndicators(c, calls);
    }
  }
  // Also collect custom indicator modules used by conditions
  final usedCustomIds = _collectCustomIndicatorRefs(program);
  for (final ci in program.customIndicators) {
    if (usedCustomIds.contains(ci.id)) {
      final params = <String, dynamic>{};
      for (final pn in ci.paramNames) {
        // Use default param values — user can adjust in UI later
        params[pn] = {'type': 'Int', 'value': 20};
      }
      calls[ci.id] = {'module_id': ci.id, 'params': params};
    }
  }
}

Set<String> _collectCustomIndicatorRefs(ScreenerProgram program) {
  final ids = <String>{};
  for (final g in program.groups) {
    for (final c in g.conditions) {
      _checkMetric(c, ids);
    }
  }
  return ids;
}

void _checkMetric(Condition c, Set<String> ids) {
  switch (c) {
    case CompareCondition(:final left, :final right):
      _addMetric(left, ids);
      if (!right.isLiteral) _addMetric(right.metric!, ids);
    case CrossCondition(:final left, :final right):
      _addMetric(left, ids);
      _addMetric(right, ids);
    default:
  }
}

void _addMetric(Metric m, Set<String> ids) {
  if (m.isCustom && m.customColumn != null) {
    // customColumn format: "indicator_id.column_name" or just "column_name"
    // Extract indicator id
    final parts = m.customColumn!.split('.');
    if (parts.length > 1) {
      ids.add(parts[0]);
    }
    // Also register the full column name as a var
  }
}

void _collectMetricIndicators(Condition c, Map<String, Map<String, dynamic>> calls) {
  void addSma(int w) {
    final key = 'sma_$w';
    calls[key] = {
      'module_id': 'sma',
      'params': {'period': {'type': 'Int', 'value': w}},
    };
  }

  void check(Metric m) {
    if (m.isCustom) return; // Handled separately
    switch (m.transform) {
      case MetricTransform.sma:
      case MetricTransform.ema:
        addSma(m.window);
      case MetricTransform.raw:
        break;
    }
  }

  switch (c) {
    case CompareCondition(:final left, :final right):
      check(left);
      if (!right.isLiteral) check(right.metric!);
    case CrossCondition(:final left, :final right):
      check(left);
      check(right);
    default:
  }
}

// ── Group compilation ──────────────────────────────────────────

dynamic _compileGroup(ConditionGroup g) {
  if (g.conditions.isEmpty) return null;
  final exprs = g.conditions.map(_compileCondition).toList();
  if (exprs.length == 1) return exprs.first;
  return exprs
      .skip(1)
      .fold(exprs.first, (a, b) => _exprBin(g.logic.exprTag, a, b));
}

// ── Condition compilation ─────────────────────────────────────

dynamic _compileCondition(Condition c) {
  return switch (c) {
    CompareCondition(:final left, :final op, :final right) =>
      _compileCompare(left, op, right),
    CrossCondition(:final direction, :final left, :final right) =>
      _compileCross(direction, left, right),
    CandleCondition(:final pattern) =>
      _compileCandle(pattern),
    GapCondition(:final direction, :final thresholdPct) =>
      _compileGap(direction, thresholdPct),
  };
}

dynamic _compileCompare(Metric left, CompareOp op, Operand right) {
  final lhs = _metricExpr(left);
  final rhs = _operandExpr(right);
  if (op == CompareOp.neq) {
    return _exprNot(_exprBin('Eq', lhs, rhs));
  }
  return _exprBin(_opTag(op), lhs, rhs);
}

dynamic _compileCross(CrossDirection dir, Metric left, Metric right) {
  return {
    't': dir.exprTag,
    'v': {
      'stock': _stockCurrent(),
      'at': _pathExpr('close'),
      'col': _crossField(left),
      'threshold': _metricExpr(right),
    },
  };
}

String _crossField(Metric m) {
  if (m.isCustom && m.customColumn != null) return m.customColumn!;
  return m.field.jsonKey;
}

dynamic _compileCandle(CandlePattern pattern) {
  return {
    't': 'CandleIs',
    'v': {
      'stock': _stockCurrent(),
      'at': _pathExpr('close'),
      'candle': pattern.exprValue,
    },
  };
}

dynamic _compileGap(GapDirection dir, double threshold) {
  final pctChange = {
    't': 'PctChange',
    'v': {
      'from': _exprPath('close', offset: -1),
      'to': _exprPath('close'),
    },
  };
  return _exprBin('Gt', pctChange, _exprNum(threshold));
}

// ── Metric / Operand → Expr ───────────────────────────────────

dynamic _metricExpr(Metric m) {
  if (m.isCustom && m.customColumn != null) {
    return _exprVar(m.customColumn!);
  }
  switch (m.transform) {
    case MetricTransform.raw:
      return _exprPath(m.field.jsonKey);
    case MetricTransform.sma:
    case MetricTransform.ema:
      return _exprVar('sma_${m.window}');
  }
}

dynamic _operandExpr(Operand o) {
  if (o.isLiteral) return _exprNum(o.literalValue!);
  final base = _metricExpr(o.metric!);
  if ((o.multiplier - 1.0).abs() < 0.000001) return base;
  return _exprBin('Mul', base, _exprNum(o.multiplier));
}

// ── Expr constructors ──────────────────────────────────────────

Map<String, dynamic> _stockCurrent() => {'t': 'Current', 'v': null};
Map<String, dynamic> _anchorWindowEnd() => {'t': 'WindowEnd', 'v': null};

Map<String, dynamic> _pathExpr(String field, {int offset = 0}) => {
  'stock': _stockCurrent(),
  'anchor': _anchorWindowEnd(),
  'offset': offset,
  'field': field,
};

Map<String, dynamic> _exprPath(String field, {int offset = 0}) => {
  't': 'Path',
  'v': _pathExpr(field, offset: offset),
};

Map<String, dynamic> _exprNum(double v) => {'t': 'Num', 'v': v};
Map<String, dynamic> _exprBool(bool v) => {'t': 'Bool', 'v': v};
Map<String, dynamic> _exprVar(String name) => {'t': 'Var', 'v': name};

Map<String, dynamic> _exprBin(String tag, dynamic lhs, dynamic rhs) => {
  't': tag,
  'v': [lhs, rhs],
};

Map<String, dynamic> _exprNot(dynamic inner) => {'t': 'Not', 'v': inner};

String _opTag(CompareOp op) {
  return switch (op) {
    CompareOp.gt => 'Gt',
    CompareOp.gte => 'Gte',
    CompareOp.lt => 'Lt',
    CompareOp.lte => 'Lte',
    CompareOp.eq => 'Eq',
    CompareOp.neq => 'Eq', // handled as Not(Eq)
  };
}
