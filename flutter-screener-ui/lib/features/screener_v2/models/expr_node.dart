// ExprNode mirrors crates/dsl/src/expr.rs Expr enum.
// Every variant produces serde-compatible {"t":"...", "v":...} JSON.

import 'enums.dart';
import 'path_ref.dart';

// ── ExprNode sealed class hierarchy ─────────────────────────

sealed class ExprNode {
  String get displayLabel;
  Map<String, dynamic> toJson();

  // Factory for deserialization (from saved JSON)
  static ExprNode fromJson(Map<String, dynamic> json) {
    final t = json['t'] as String;
    final v = json['v'];
    switch (t) {
      case 'Num': return NumExpr((v as num).toDouble());
      case 'Bool': return BoolExpr(v as bool);
      case 'Path': return PathExprNode(PathRef.fromJson(Map<String, dynamic>.from(v as Map)));
      case 'Var': return VarExpr(v as String);
      case 'Neg': return NegExpr(fromJson(Map<String, dynamic>.from(v as Map)));
      case 'Abs': return AbsExpr(fromJson(Map<String, dynamic>.from(v as Map)));
      case 'Not': return NotExpr(fromJson(Map<String, dynamic>.from(v as Map)));
      case 'Add': return AddExpr(_child(v, 0), _child(v, 1));
      case 'Sub': return SubExpr(_child(v, 0), _child(v, 1));
      case 'Mul': return MulExpr(_child(v, 0), _child(v, 1));
      case 'Div': return DivExpr(_child(v, 0), _child(v, 1));
      case 'Gt': return GtExpr(_child(v, 0), _child(v, 1));
      case 'Lt': return LtExpr(_child(v, 0), _child(v, 1));
      case 'Gte': return GteExpr(_child(v, 0), _child(v, 1));
      case 'Lte': return LteExpr(_child(v, 0), _child(v, 1));
      case 'Eq': return EqExpr(_child(v, 0), _child(v, 1));
      case 'And': return AndExpr(_child(v, 0), _child(v, 1));
      case 'Or': return OrExpr(_child(v, 0), _child(v, 1));
      case 'PctChange': return PctChangeExpr(
        fromJson(Map<String, dynamic>.from((v as Map)['from'] as Map)),
        fromJson(Map<String, dynamic>.from(v['to'] as Map)),
      );
      case 'Between': return BetweenExpr(
        fromJson(Map<String, dynamic>.from((v as Map)['val'] as Map)),
        fromJson(Map<String, dynamic>.from(v['low'] as Map)),
        fromJson(Map<String, dynamic>.from(v['high'] as Map)),
      );
      case 'Implies': return ImpliesExpr(
        fromJson(Map<String, dynamic>.from((v as Map)['antecedent'] as Map)),
        fromJson(Map<String, dynamic>.from(v['consequent'] as Map)),
      );
      case 'Agg': return _parseAgg(v as Map);
      case 'All': return _parseAll(v as Map);
      case 'Any': return _parseAny(v as Map);
      case 'CountBars': return _parseCountBars(v as Map);
      case 'RangeVal': return _parseRangeVal(v as Map);
      case 'CrossUp': return _parseCrossUp(v as Map);
      case 'CrossDown': return _parseCrossDown(v as Map);
      case 'CandleIs': return _parseCandleIs(v as Map);
      case 'PointExists': return PointExistsExpr(v as String);
      case 'Monotone': return _parseMonotone(v as Map);
      case 'SyncWithMarket': return SyncWithMarketExpr(
        PathRef.fromJson(Map<String, dynamic>.from((v as Map)['from'] as Map)),
        PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
      );
      default: return NumExpr(0); // fallback
    }
  }

  static ExprNode _child(dynamic v, int i) =>
      fromJson(Map<String, dynamic>.from((v as List)[i] as Map));

  static AggExpr _parseAgg(Map v) => AggExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    from: PathRef.fromJson(Map<String, dynamic>.from(v['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
    col: v['col'] as String,
    func: AggFuncEnum.fromJson(v['func'] as String),
  );
  static AllExpr _parseAll(Map v) => AllExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    from: PathRef.fromJson(Map<String, dynamic>.from(v['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
    pred: fromJson(Map<String, dynamic>.from(v['pred'] as Map)),
  );
  static AnyExpr _parseAny(Map v) => AnyExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    from: PathRef.fromJson(Map<String, dynamic>.from(v['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
    pred: fromJson(Map<String, dynamic>.from(v['pred'] as Map)),
  );
  static CountBarsExpr _parseCountBars(Map v) => CountBarsExpr(
    from: PathRef.fromJson(Map<String, dynamic>.from(v['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
    pred: fromJson(Map<String, dynamic>.from(v['pred'] as Map)),
    op: CmpOpEnum.fromJson(v['op'] as String),
    n: (v['n'] as num).toInt(),
  );
  static RangeValExpr _parseRangeVal(Map v) => RangeValExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    from: PathRef.fromJson(Map<String, dynamic>.from(v['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
    col: v['col'] as String,
    func: AggFuncEnum.fromJson(v['func'] as String),
  );
  static CrossUpExpr _parseCrossUp(Map v) => CrossUpExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    at: PathRef.fromJson(Map<String, dynamic>.from(v['at'] as Map)),
    col: v['col'] as String,
    threshold: fromJson(Map<String, dynamic>.from(v['threshold'] as Map)),
  );
  static CrossDownExpr _parseCrossDown(Map v) => CrossDownExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    at: PathRef.fromJson(Map<String, dynamic>.from(v['at'] as Map)),
    col: v['col'] as String,
    threshold: fromJson(Map<String, dynamic>.from(v['threshold'] as Map)),
  );
  static CandleIsExpr _parseCandleIs(Map v) => CandleIsExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    at: PathRef.fromJson(Map<String, dynamic>.from(v['at'] as Map)),
    candle: CandleTypeEnum.fromJson(v['candle'] as String),
  );
  static MonotoneExpr _parseMonotone(Map v) => MonotoneExpr(
    stock: StockRef.fromJson(Map<String, dynamic>.from(v['stock'] as Map)),
    from: PathRef.fromJson(Map<String, dynamic>.from(v['from'] as Map)),
    to: PathRef.fromJson(Map<String, dynamic>.from(v['to'] as Map)),
    col: v['col'] as String,
    dir: MonotoneDirEnum.fromJson(v['dir'] as String),
  );
}

// ── Leaf nodes ──────────────────────────────────────────────

class NumExpr extends ExprNode {
  final double value;
  NumExpr(this.value);
  @override String get displayLabel => _fmt(value);
  @override Map<String, dynamic> toJson() => {'t': 'Num', 'v': value};
}

class BoolExpr extends ExprNode {
  final bool value;
  BoolExpr(this.value);
  @override String get displayLabel => value ? '真' : '假';
  @override Map<String, dynamic> toJson() => {'t': 'Bool', 'v': value};
}

class PathExprNode extends ExprNode {
  final PathRef ref;
  PathExprNode(this.ref);
  @override String get displayLabel => ref.displayLabel;
  @override Map<String, dynamic> toJson() => {'t': 'Path', 'v': ref.toJson()};
}

class VarExpr extends ExprNode {
  final String name;
  VarExpr(this.name);
  @override String get displayLabel => '变量:$name';
  @override Map<String, dynamic> toJson() => {'t': 'Var', 'v': name};
}

class PointExistsExpr extends ExprNode {
  final String name;
  PointExistsExpr(this.name);
  @override String get displayLabel => '点存在:$name';
  @override Map<String, dynamic> toJson() => {'t': 'PointExists', 'v': name};
}

// ── Unary nodes ─────────────────────────────────────────────

class NegExpr extends ExprNode {
  final ExprNode child;
  NegExpr(this.child);
  @override String get displayLabel => '-(${child.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Neg', 'v': child.toJson()};
}

class AbsExpr extends ExprNode {
  final ExprNode child;
  AbsExpr(this.child);
  @override String get displayLabel => 'abs(${child.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Abs', 'v': child.toJson()};
}

class NotExpr extends ExprNode {
  final ExprNode child;
  NotExpr(this.child);
  @override String get displayLabel => '非(${child.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Not', 'v': child.toJson()};
}

// ── Binary arithmetic ───────────────────────────────────────

class AddExpr extends ExprNode {
  final ExprNode left, right;
  AddExpr(this.left, this.right);
  @override String get displayLabel => '(${left.displayLabel} + ${right.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Add', 'v': [left.toJson(), right.toJson()]};
}

class SubExpr extends ExprNode {
  final ExprNode left, right;
  SubExpr(this.left, this.right);
  @override String get displayLabel => '(${left.displayLabel} - ${right.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Sub', 'v': [left.toJson(), right.toJson()]};
}

class MulExpr extends ExprNode {
  final ExprNode left, right;
  MulExpr(this.left, this.right);
  @override String get displayLabel => '(${left.displayLabel} * ${right.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Mul', 'v': [left.toJson(), right.toJson()]};
}

class DivExpr extends ExprNode {
  final ExprNode left, right;
  DivExpr(this.left, this.right);
  @override String get displayLabel => '(${left.displayLabel} / ${right.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Div', 'v': [left.toJson(), right.toJson()]};
}

// ── Comparison ──────────────────────────────────────────────

class GtExpr extends ExprNode {
  final ExprNode left, right;
  GtExpr(this.left, this.right);
  @override String get displayLabel => '${left.displayLabel} > ${right.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Gt', 'v': [left.toJson(), right.toJson()]};
}

class LtExpr extends ExprNode {
  final ExprNode left, right;
  LtExpr(this.left, this.right);
  @override String get displayLabel => '${left.displayLabel} < ${right.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Lt', 'v': [left.toJson(), right.toJson()]};
}

class GteExpr extends ExprNode {
  final ExprNode left, right;
  GteExpr(this.left, this.right);
  @override String get displayLabel => '${left.displayLabel} >= ${right.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Gte', 'v': [left.toJson(), right.toJson()]};
}

class LteExpr extends ExprNode {
  final ExprNode left, right;
  LteExpr(this.left, this.right);
  @override String get displayLabel => '${left.displayLabel} <= ${right.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Lte', 'v': [left.toJson(), right.toJson()]};
}

class EqExpr extends ExprNode {
  final ExprNode left, right;
  EqExpr(this.left, this.right);
  @override String get displayLabel => '${left.displayLabel} == ${right.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Eq', 'v': [left.toJson(), right.toJson()]};
}

// ── Boolean ─────────────────────────────────────────────────

class AndExpr extends ExprNode {
  final ExprNode left, right;
  AndExpr(this.left, this.right);
  @override String get displayLabel => '(${left.displayLabel} 且 ${right.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'And', 'v': [left.toJson(), right.toJson()]};
}

class OrExpr extends ExprNode {
  final ExprNode left, right;
  OrExpr(this.left, this.right);
  @override String get displayLabel => '(${left.displayLabel} 或 ${right.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Or', 'v': [left.toJson(), right.toJson()]};
}

class ImpliesExpr extends ExprNode {
  final ExprNode antecedent, consequent;
  ImpliesExpr(this.antecedent, this.consequent);
  @override String get displayLabel => '(${antecedent.displayLabel} → ${consequent.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Implies', 'v': {
    'antecedent': antecedent.toJson(),
    'consequent': consequent.toJson(),
  }};
}

// ── Structured ──────────────────────────────────────────────

class PctChangeExpr extends ExprNode {
  final ExprNode from, to;
  PctChangeExpr(this.from, this.to);
  @override String get displayLabel => '涨幅(${from.displayLabel} → ${to.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'PctChange', 'v': {
    'from': from.toJson(),
    'to': to.toJson(),
  }};
}

class BetweenExpr extends ExprNode {
  final ExprNode val, low, high;
  BetweenExpr(this.val, this.low, this.high);
  @override String get displayLabel => '${val.displayLabel} 在 ${low.displayLabel}~${high.displayLabel} 之间';
  @override Map<String, dynamic> toJson() => {'t': 'Between', 'v': {
    'val': val.toJson(),
    'low': low.toJson(),
    'high': high.toJson(),
  }};
}

// ── Range nodes ─────────────────────────────────────────────

class AggExpr extends ExprNode {
  final StockRef stock;
  final PathRef from, to;
  final String col;
  final AggFuncEnum func;
  AggExpr({required this.stock, required this.from, required this.to, required this.col, required this.func});
  @override String get displayLabel => '${func.label}($col) 在 ${from.displayLabel}..${to.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'Agg', 'v': {
    'stock': stock.toJson(),
    'from': from.toJson(),
    'to': to.toJson(),
    'col': col,
    'func': func.toJson(),
  }};
}

class AllExpr extends ExprNode {
  final StockRef stock;
  final PathRef from, to;
  final ExprNode pred;
  AllExpr({required this.stock, required this.from, required this.to, required this.pred});
  @override String get displayLabel => '全部满足(${pred.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'All', 'v': {
    'stock': stock.toJson(),
    'from': from.toJson(),
    'to': to.toJson(),
    'pred': pred.toJson(),
  }};
}

class AnyExpr extends ExprNode {
  final StockRef stock;
  final PathRef from, to;
  final ExprNode pred;
  AnyExpr({required this.stock, required this.from, required this.to, required this.pred});
  @override String get displayLabel => '任一满足(${pred.displayLabel})';
  @override Map<String, dynamic> toJson() => {'t': 'Any', 'v': {
    'stock': stock.toJson(),
    'from': from.toJson(),
    'to': to.toJson(),
    'pred': pred.toJson(),
  }};
}

class CountBarsExpr extends ExprNode {
  final PathRef from, to;
  final ExprNode pred;
  final CmpOpEnum op;
  final int n;
  CountBarsExpr({required this.from, required this.to, required this.pred, required this.op, required this.n});
  @override String get displayLabel => '满足条件K线数 ${op.symbol} $n';
  @override Map<String, dynamic> toJson() => {'t': 'CountBars', 'v': {
    'from': from.toJson(),
    'to': to.toJson(),
    'pred': pred.toJson(),
    'op': op.toJson(),
    'n': n,
  }};
}

class RangeValExpr extends ExprNode {
  final StockRef stock;
  final PathRef from, to;
  final String col;
  final AggFuncEnum func;
  RangeValExpr({required this.stock, required this.from, required this.to, required this.col, required this.func});
  @override String get displayLabel => '${func.label}($col) 范围值';
  @override Map<String, dynamic> toJson() => {'t': 'RangeVal', 'v': {
    'stock': stock.toJson(),
    'from': from.toJson(),
    'to': to.toJson(),
    'col': col,
    'func': func.toJson(),
  }};
}

// ── Event nodes ─────────────────────────────────────────────

class CrossUpExpr extends ExprNode {
  final StockRef stock;
  final PathRef at;
  final String col;
  final ExprNode threshold;
  CrossUpExpr({required this.stock, required this.at, required this.col, required this.threshold});
  @override String get displayLabel => '$col 向上穿越 ${threshold.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'CrossUp', 'v': {
    'stock': stock.toJson(),
    'at': at.toJson(),
    'col': col,
    'threshold': threshold.toJson(),
  }};
}

class CrossDownExpr extends ExprNode {
  final StockRef stock;
  final PathRef at;
  final String col;
  final ExprNode threshold;
  CrossDownExpr({required this.stock, required this.at, required this.col, required this.threshold});
  @override String get displayLabel => '$col 向下穿越 ${threshold.displayLabel}';
  @override Map<String, dynamic> toJson() => {'t': 'CrossDown', 'v': {
    'stock': stock.toJson(),
    'at': at.toJson(),
    'col': col,
    'threshold': threshold.toJson(),
  }};
}

class CandleIsExpr extends ExprNode {
  final StockRef stock;
  final PathRef at;
  final CandleTypeEnum candle;
  CandleIsExpr({required this.stock, required this.at, required this.candle});
  @override String get displayLabel => 'K线形态: ${candle.label}';
  @override Map<String, dynamic> toJson() => {'t': 'CandleIs', 'v': {
    'stock': stock.toJson(),
    'at': at.toJson(),
    'candle': candle.toJson(),
  }};
}

// ── Meta nodes ──────────────────────────────────────────────

class MonotoneExpr extends ExprNode {
  final StockRef stock;
  final PathRef from, to;
  final String col;
  final MonotoneDirEnum dir;
  MonotoneExpr({required this.stock, required this.from, required this.to, required this.col, required this.dir});
  @override String get displayLabel => '$col ${dir.label}';
  @override Map<String, dynamic> toJson() => {'t': 'Monotone', 'v': {
    'stock': stock.toJson(),
    'from': from.toJson(),
    'to': to.toJson(),
    'col': col,
    'dir': dir.toJson(),
  }};
}

class SyncWithMarketExpr extends ExprNode {
  final PathRef from, to;
  SyncWithMarketExpr(this.from, this.to);
  @override String get displayLabel => '与大盘同步';
  @override Map<String, dynamic> toJson() => {'t': 'SyncWithMarket', 'v': {
    'from': from.toJson(),
    'to': to.toJson(),
  }};
}

// ── Helpers ─────────────────────────────────────────────────

String _fmt(num x) {
  if (x == x.roundToDouble()) return x.toInt().toString();
  return x.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
