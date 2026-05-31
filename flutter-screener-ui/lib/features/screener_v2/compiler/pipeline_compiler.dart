// Pipeline compiler — transforms ScreenerV2Program into Pipeline JSON + Registry JSON.
// Pure functions, no UI dependencies.

import 'dart:convert';

import '../models/program_model.dart';
import '../models/stage_model.dart';
import '../models/expr_node.dart';
import 'expr_compiler.dart';
import 'registry_compiler.dart';

/// Compile a ScreenerV2Program into (pipelineJson, registryJson).
({String pipelineJson, String registryJson}) compileScreenerV2(
  ScreenerV2Program program, {
  String defaultRegistryJson = '{}',
}) {
  // 1. Merge custom indicators into registry
  final registryJson = mergeRegistry(defaultRegistryJson, program.customIndicators);

  // 2. Compile each stage
  final stages = program.stages.map(_compileStage).toList();

  // 3. Produce pipeline JSON
  final pipeline = {'stages': stages};
  final pipelineJson = jsonEncode(pipeline);

  return (pipelineJson: pipelineJson, registryJson: registryJson);
}

Map<String, dynamic> _compileStage(StageModel s) {
  // Collect indicator calls from all expression trees in the stage
  final indicatorCalls = <String, Map<String, dynamic>>{};
  _collectIndicatorCalls(s, indicatorCalls);

  // Build vars
  final vars = s.vars.map((v) => {
    'name': v.name,
    'expr': compileExpr(v.expr),
  }).toList();

  // Compile conditions as [name, expr] pairs
  final conditions = s.conditions.map((c) => [c.name, compileExpr(c.expr)]).toList();

  // Compile points
  final points = s.points.map((p) => {
    'name': p.name,
    'def': compilePointDef(p.def),
  }).toList();

  // Compile marks
  final marks = s.marks.map((m) {
    final mark = <String, dynamic>{
      'name': m.name,
      'anchor': m.anchor.toJson(),
      'value': m.value != null ? compileExpr(m.value!) : null,
      'label': m.label,
    };
    return mark;
  }).toList();

  return {
    'name': s.name,
    'timeframe': s.timeframe.toJson(),
    'start_date': s.startDate,
    'windowsize': s.windowSize?.toJson(),
    'prepare': {
      'indicators': indicatorCalls.values.toList(),
    },
    'kline_pattern': s.klinePattern?.toJson(),
    'vars': vars,
    'points': points,
    'conditions': conditions,
    'marks': marks,
    'extra_stocks': s.extraStocks,
  };
}

/// Collect indicator calls from all expression trees in a stage.
void _collectIndicatorCalls(StageModel s, Map<String, Map<String, dynamic>> calls) {
  // From conditions
  for (final c in s.conditions) {
    _scanExprForIndicators(c.expr, calls);
  }
  // From vars
  for (final v in s.vars) {
    _scanExprForIndicators(v.expr, calls);
  }
  // From points
  for (final p in s.points) {
    _scanPointDefForIndicators(p.def, calls);
  }
  // From marks
  for (final m in s.marks) {
    if (m.value != null) _scanExprForIndicators(m.value!, calls);
  }

  // Add explicit indicator calls from prepare
  for (final ic in s.prepare) {
    calls[ic.moduleId] = ic.toJson();
  }
}

void _scanExprForIndicators(ExprNode expr, Map<String, Map<String, dynamic>> calls) {
  // Look for VarExpr references that look like indicator output columns
  // e.g., "sma_20" -> needs indicator call sma with period=20
  if (expr is VarExpr) {
    _tryParseIndicatorRef(expr.name, calls);
  }
  // Recurse into children
  switch (expr) {
    case NegExpr(:final child): _scanExprForIndicators(child, calls);
    case AbsExpr(:final child): _scanExprForIndicators(child, calls);
    case NotExpr(:final child): _scanExprForIndicators(child, calls);
    case AddExpr(:final left, :final right): _scanBoth(left, right, calls);
    case SubExpr(:final left, :final right): _scanBoth(left, right, calls);
    case MulExpr(:final left, :final right): _scanBoth(left, right, calls);
    case DivExpr(:final left, :final right): _scanBoth(left, right, calls);
    case GtExpr(:final left, :final right): _scanBoth(left, right, calls);
    case LtExpr(:final left, :final right): _scanBoth(left, right, calls);
    case GteExpr(:final left, :final right): _scanBoth(left, right, calls);
    case LteExpr(:final left, :final right): _scanBoth(left, right, calls);
    case EqExpr(:final left, :final right): _scanBoth(left, right, calls);
    case AndExpr(:final left, :final right): _scanBoth(left, right, calls);
    case OrExpr(:final left, :final right): _scanBoth(left, right, calls);
    case ImpliesExpr(:final antecedent, :final consequent): _scanBoth(antecedent, consequent, calls);
    case PctChangeExpr(:final from, :final to): _scanBoth(from, to, calls);
    case BetweenExpr(:final val, :final low, :final high):
      _scanExprForIndicators(val, calls);
      _scanExprForIndicators(low, calls);
      _scanExprForIndicators(high, calls);
    case AllExpr(:final pred): _scanExprForIndicators(pred, calls);
    case AnyExpr(:final pred): _scanExprForIndicators(pred, calls);
    case CountBarsExpr(:final pred): _scanExprForIndicators(pred, calls);
    case CrossUpExpr(:final threshold): _scanExprForIndicators(threshold, calls);
    case CrossDownExpr(:final threshold): _scanExprForIndicators(threshold, calls);
    default: break;
  }
}

void _scanBoth(ExprNode a, ExprNode b, Map<String, Map<String, dynamic>> calls) {
  _scanExprForIndicators(a, calls);
  _scanExprForIndicators(b, calls);
}

void _scanPointDefForIndicators(PointDefModel def, Map<String, Map<String, dynamic>> calls) {
  if (def is WherePointDef) {
    _scanExprForIndicators(def.pred, calls);
  }
}

/// Try to parse a variable name like "sma_20" into an indicator call.
void _tryParseIndicatorRef(String name, Map<String, Map<String, dynamic>> calls) {
  // Common patterns: sma_N, vol_ma_N, boll_mid_N, boll_upper_N
  final smaMatch = RegExp(r'^sma_(\d+)$').firstMatch(name);
  if (smaMatch != null) {
    final period = int.parse(smaMatch.group(1)!);
    calls['sma'] ??= {
      'module_id': 'sma',
      'params': {'period': {'type': 'Int', 'value': period}},
    };
    return;
  }

  final volMaMatch = RegExp(r'^vol_ma_(\d+)$').firstMatch(name);
  if (volMaMatch != null) {
    final period = int.parse(volMaMatch.group(1)!);
    calls['vol_ma'] ??= {
      'module_id': 'vol_ma',
      'params': {'period': {'type': 'Int', 'value': period}},
    };
    return;
  }

  final bollMatch = RegExp(r'^boll_(?:mid|upper|lower)_(\d+)$').firstMatch(name);
  if (bollMatch != null) {
    final period = int.parse(bollMatch.group(1)!);
    calls['boll'] ??= {
      'module_id': 'boll',
      'params': {
        'period': {'type': 'Int', 'value': period},
        'k': {'type': 'Float', 'value': 2.0},
      },
    };
    return;
  }
}
