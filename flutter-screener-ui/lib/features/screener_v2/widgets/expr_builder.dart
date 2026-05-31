// ExprBuilder — recursive visual editor for expression trees.
// This is the core widget for the screener visual builder.

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/expr_node.dart';
import '../models/enums.dart';
import '../models/path_ref.dart';
import 'path_ref_editor.dart';

// ── Node type catalog ───────────────────────────────────────

class _NodeTypeInfo {
  final String label;
  final String category;
  final ExprNode Function() createDefault;
  const _NodeTypeInfo(this.label, this.category, this.createDefault);
}

const _nodeTypes = <String, List<_NodeTypeInfo>>{
  '字面量': [
    _NodeTypeInfo('数值', '字面量', _defNum),
    _NodeTypeInfo('布尔值', '字面量', _defBool),
  ],
  '数据引用': [
    _NodeTypeInfo('路径引用', '数据引用', _defPath),
    _NodeTypeInfo('变量引用', '数据引用', _defVar),
    _NodeTypeInfo('点存在性', '数据引用', _defPointExists),
  ],
  '算术': [
    _NodeTypeInfo('加法 (+)', '算术', _defAdd),
    _NodeTypeInfo('减法 (-)', '算术', _defSub),
    _NodeTypeInfo('乘法 (*)', '算术', _defMul),
    _NodeTypeInfo('除法 (/)', '算术', _defDiv),
    _NodeTypeInfo('取反 (-)', '算术', _defNeg),
    _NodeTypeInfo('绝对值', '算术', _defAbs),
    _NodeTypeInfo('百分比变化', '算术', _defPctChange),
  ],
  '比较': [
    _NodeTypeInfo('大于 (>)', '比较', _defGt),
    _NodeTypeInfo('小于 (<)', '比较', _defLt),
    _NodeTypeInfo('大于等于 (>=)', '比较', _defGte),
    _NodeTypeInfo('小于等于 (<=)', '比较', _defLte),
    _NodeTypeInfo('等于 (==)', '比较', _defEq),
    _NodeTypeInfo('区间 (Between)', '比较', _defBetween),
  ],
  '逻辑': [
    _NodeTypeInfo('与 (And)', '逻辑', _defAnd),
    _NodeTypeInfo('或 (Or)', '逻辑', _defOr),
    _NodeTypeInfo('非 (Not)', '逻辑', _defNot),
    _NodeTypeInfo('蕴含 (Implies)', '逻辑', _defImplies),
  ],
  '范围': [
    _NodeTypeInfo('范围聚合 (Agg)', '范围', _defAgg),
    _NodeTypeInfo('全部满足 (All)', '范围', _defAll),
    _NodeTypeInfo('任一满足 (Any)', '范围', _defAny),
    _NodeTypeInfo('计数 (CountBars)', '范围', _defCountBars),
    _NodeTypeInfo('范围值 (RangeVal)', '范围', _defRangeVal),
  ],
  '事件': [
    _NodeTypeInfo('向上穿越 (CrossUp)', '事件', _defCrossUp),
    _NodeTypeInfo('向下穿越 (CrossDown)', '事件', _defCrossDown),
    _NodeTypeInfo('K线形态 (CandleIs)', '事件', _defCandleIs),
  ],
  '其他': [
    _NodeTypeInfo('单调性', '其他', _defMonotone),
    _NodeTypeInfo('与大盘同步', '其他', _defSyncWithMarket),
  ],
};

// ── Default constructors ────────────────────────────────────

ExprNode _defNum() => NumExpr(0);
ExprNode _defBool() => BoolExpr(true);
ExprNode _defPath() => PathExprNode(PathRef.close());
ExprNode _defVar() => VarExpr('sma_20');
ExprNode _defPointExists() => PointExistsExpr('A');
ExprNode _defAdd() => AddExpr(NumExpr(0), NumExpr(0));
ExprNode _defSub() => SubExpr(NumExpr(0), NumExpr(0));
ExprNode _defMul() => MulExpr(NumExpr(0), NumExpr(0));
ExprNode _defDiv() => DivExpr(NumExpr(0), NumExpr(0));
ExprNode _defNeg() => NegExpr(NumExpr(0));
ExprNode _defAbs() => AbsExpr(NumExpr(0));
ExprNode _defPctChange() => PctChangeExpr(
  PathExprNode(PathRef.close(offset: -1)),
  PathExprNode(PathRef.close()),
);
ExprNode _defGt() => GtExpr(PathExprNode(PathRef.close()), NumExpr(0));
ExprNode _defLt() => LtExpr(PathExprNode(PathRef.close()), NumExpr(0));
ExprNode _defGte() => GteExpr(PathExprNode(PathRef.close()), NumExpr(0));
ExprNode _defLte() => LteExpr(PathExprNode(PathRef.close()), NumExpr(0));
ExprNode _defEq() => EqExpr(PathExprNode(PathRef.close()), NumExpr(0));
ExprNode _defBetween() => BetweenExpr(PathExprNode(PathRef.close()), NumExpr(0), NumExpr(100));
ExprNode _defAnd() => AndExpr(BoolExpr(true), BoolExpr(true));
ExprNode _defOr() => OrExpr(BoolExpr(true), BoolExpr(true));
ExprNode _defNot() => NotExpr(BoolExpr(true));
ExprNode _defImplies() => ImpliesExpr(BoolExpr(true), BoolExpr(true));
ExprNode _defAgg() => AggExpr(
  stock: StockRef.current,
  from: PathRef.close(offset: -20),
  to: PathRef.close(),
  col: 'close',
  func: AggFuncEnum.max,
);
ExprNode _defAll() => AllExpr(
  stock: StockRef.current,
  from: PathRef.close(offset: -20),
  to: PathRef.close(),
  pred: GtExpr(PathExprNode(PathRef.each(field: 'close')), NumExpr(10)),
);
ExprNode _defAny() => AnyExpr(
  stock: StockRef.current,
  from: PathRef.close(offset: -20),
  to: PathRef.close(),
  pred: GtExpr(PathExprNode(PathRef.each(field: 'close')), NumExpr(10)),
);
ExprNode _defCountBars() => CountBarsExpr(
  from: PathRef.close(offset: -20),
  to: PathRef.close(),
  pred: GtExpr(PathExprNode(PathRef.each(field: 'close')), NumExpr(10)),
  op: CmpOpEnum.gte,
  n: 5,
);
ExprNode _defRangeVal() => RangeValExpr(
  stock: StockRef.current,
  from: PathRef.close(offset: -20),
  to: PathRef.close(),
  col: 'close',
  func: AggFuncEnum.min,
);
ExprNode _defCrossUp() => CrossUpExpr(
  stock: StockRef.current,
  at: PathRef.close(),
  col: 'close',
  threshold: VarExpr('sma_20'),
);
ExprNode _defCrossDown() => CrossDownExpr(
  stock: StockRef.current,
  at: PathRef.close(),
  col: 'close',
  threshold: VarExpr('sma_20'),
);
ExprNode _defCandleIs() => CandleIsExpr(
  stock: StockRef.current,
  at: PathRef.close(),
  candle: CandleTypeEnum.up,
);
ExprNode _defMonotone() => MonotoneExpr(
  stock: StockRef.current,
  from: PathRef.close(offset: -10),
  to: PathRef.close(),
  col: 'close',
  dir: MonotoneDirEnum.nonDec,
);
ExprNode _defSyncWithMarket() => SyncWithMarketExpr(
  PathRef.close(offset: -5),
  PathRef.close(),
);

// ── ExprBuilder widget ──────────────────────────────────────

class ExprBuilder extends StatelessWidget {
  final ExprNode node;
  final ValueChanged<ExprNode> onChanged;
  final int depth;

  const ExprBuilder({
    super.key,
    required this.node,
    required this.onChanged,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: depth * 8.0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
        color: depth.isEven ? AppColors.surface : AppColors.surfaceMuted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _typeSelector(context),
          const SizedBox(height: 6),
          _content(context),
        ],
      ),
    );
  }

  // ── Type selector ─────────────────────────────────────────

  Widget _typeSelector(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _currentTypeName,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
            ),
            isDense: true,
            style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
            items: _buildGroupedItems(),
            onChanged: (t) {
              if (t != null && t != _currentTypeName) {
                final info = _findTypeInfo(t);
                if (info != null) onChanged(info.createDefault());
              }
            },
          ),
        ),
      ],
    );
  }

  String get _currentTypeName {
    for (final entry in _nodeTypes.entries) {
      for (final info in entry.value) {
        if (_matchesType(node, info)) return info.label;
      }
    }
    return '数值';
  }

  _NodeTypeInfo? _findTypeInfo(String label) {
    for (final entry in _nodeTypes.entries) {
      for (final info in entry.value) {
        if (info.label == label) return info;
      }
    }
    return null;
  }

  List<DropdownMenuItem<String>> _buildGroupedItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final entry in _nodeTypes.entries) {
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__cat_${entry.key}__',
        child: Text(entry.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.brand)),
      ));
      for (final info in entry.value) {
        items.add(DropdownMenuItem<String>(
          value: info.label,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(info.label, style: const TextStyle(fontSize: 11)),
          ),
        ));
      }
    }
    return items;
  }

  bool _matchesType(ExprNode node, _NodeTypeInfo info) {
    return switch (node) {
      NumExpr() => info.label == '数值',
      BoolExpr() => info.label == '布尔值',
      PathExprNode() => info.label == '路径引用',
      VarExpr() => info.label == '变量引用',
      PointExistsExpr() => info.label == '点存在性',
      AddExpr() => info.label == '加法 (+)',
      SubExpr() => info.label == '减法 (-)',
      MulExpr() => info.label == '乘法 (*)',
      DivExpr() => info.label == '除法 (/)',
      NegExpr() => info.label == '取反 (-)',
      AbsExpr() => info.label == '绝对值',
      PctChangeExpr() => info.label == '百分比变化',
      GtExpr() => info.label == '大于 (>)',
      LtExpr() => info.label == '小于 (<)',
      GteExpr() => info.label == '大于等于 (>=)',
      LteExpr() => info.label == '小于等于 (<=)',
      EqExpr() => info.label == '等于 (==)',
      BetweenExpr() => info.label == '区间 (Between)',
      AndExpr() => info.label == '与 (And)',
      OrExpr() => info.label == '或 (Or)',
      NotExpr() => info.label == '非 (Not)',
      ImpliesExpr() => info.label == '蕴含 (Implies)',
      AggExpr() => info.label == '范围聚合 (Agg)',
      AllExpr() => info.label == '全部满足 (All)',
      AnyExpr() => info.label == '任一满足 (Any)',
      CountBarsExpr() => info.label == '计数 (CountBars)',
      RangeValExpr() => info.label == '范围值 (RangeVal)',
      CrossUpExpr() => info.label == '向上穿越 (CrossUp)',
      CrossDownExpr() => info.label == '向下穿越 (CrossDown)',
      CandleIsExpr() => info.label == 'K线形态 (CandleIs)',
      MonotoneExpr() => info.label == '单调性',
      SyncWithMarketExpr() => info.label == '与大盘同步',
    };
  }

  // ── Per-node-type content ─────────────────────────────────

  Widget _content(BuildContext context) {
    return switch (node) {
      NumExpr(:final value) => _numEditor(value),
      BoolExpr(:final value) => _boolEditor(value),
      PathExprNode(:final ref) => PathRefEditor(value: ref, onChanged: (r) => onChanged(PathExprNode(r))),
      VarExpr(:final name) => _varEditor(name),
      PointExistsExpr(:final name) => _pointExistsEditor(name),
      NegExpr(:final child) => _unaryEditor(child, (c) => NegExpr(c)),
      AbsExpr(:final child) => _unaryEditor(child, (c) => AbsExpr(c)),
      NotExpr(:final child) => _unaryEditor(child, (c) => NotExpr(c)),
      AddExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => AddExpr(l, r)),
      SubExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => SubExpr(l, r)),
      MulExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => MulExpr(l, r)),
      DivExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => DivExpr(l, r)),
      GtExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => GtExpr(l, r)),
      LtExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => LtExpr(l, r)),
      GteExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => GteExpr(l, r)),
      LteExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => LteExpr(l, r)),
      EqExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => EqExpr(l, r)),
      AndExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => AndExpr(l, r)),
      OrExpr(:final left, :final right) => _binaryEditor(left, right, (l, r) => OrExpr(l, r)),
      ImpliesExpr(:final antecedent, :final consequent) => _binaryEditor(antecedent, consequent, (a, c) => ImpliesExpr(a, c)),
      PctChangeExpr(:final from, :final to) => _binaryEditor(from, to, (f, t) => PctChangeExpr(f, t)),
      BetweenExpr(:final val, :final low, :final high) => _betweenEditor(val, low, high),
      AllExpr() => _rangePredEditor(node as AllExpr),
      AnyExpr() => _rangePredEditor(node as AnyExpr),
      CountBarsExpr() => _countBarsEditor(node as CountBarsExpr),
      AggExpr() => _aggEditor(node as AggExpr),
      RangeValExpr() => _rangeValEditor(node as RangeValExpr),
      CrossUpExpr() => _crossEditor(node as CrossUpExpr, true),
      CrossDownExpr() => _crossEditor(node as CrossDownExpr, false),
      CandleIsExpr() => _candleIsEditor(node as CandleIsExpr),
      MonotoneExpr() => _monotoneEditor(node as MonotoneExpr),
      SyncWithMarketExpr() => _syncWithMarketEditor(node as SyncWithMarketExpr),
    };
  }

  // ── Leaf editors ──────────────────────────────────────────

  Widget _numEditor(double value) {
    return Row(
      children: [
        const Text('数值:', style: _labelStyle),
        const SizedBox(width: 6),
        SizedBox(
          width: 100,
          child: TextFormField(
            initialValue: value.toString(),
            decoration: _inputDec('数字'),
            style: const TextStyle(fontSize: 12),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null) onChanged(NumExpr(n));
            },
          ),
        ),
      ],
    );
  }

  Widget _boolEditor(bool value) {
    return Row(
      children: [
        const Text('值:', style: _labelStyle),
        const SizedBox(width: 6),
        Switch(value: value, onChanged: (v) => onChanged(BoolExpr(v))),
        Text(value ? '真' : '假', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _varEditor(String name) {
    return Row(
      children: [
        const Text('变量名:', style: _labelStyle),
        const SizedBox(width: 6),
        SizedBox(
          width: 120,
          child: TextFormField(
            initialValue: name,
            decoration: _inputDec('变量名'),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) => onChanged(VarExpr(v)),
          ),
        ),
      ],
    );
  }

  Widget _pointExistsEditor(String name) {
    return Row(
      children: [
        const Text('点名称:', style: _labelStyle),
        const SizedBox(width: 6),
        SizedBox(
          width: 100,
          child: TextFormField(
            initialValue: name,
            decoration: _inputDec('点名'),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) => onChanged(PointExistsExpr(v)),
          ),
        ),
      ],
    );
  }

  // ── Unary editor ──────────────────────────────────────────

  Widget _unaryEditor(ExprNode child, ExprNode Function(ExprNode) rebuild) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('操作数:', style: _labelStyle),
        ExprBuilder(node: child, onChanged: (c) => onChanged(rebuild(c)), depth: depth + 1),
      ],
    );
  }

  // ── Binary editor ─────────────────────────────────────────

  Widget _binaryEditor(ExprNode left, ExprNode right, ExprNode Function(ExprNode, ExprNode) rebuild) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('左操作数:', style: _labelStyle),
        ExprBuilder(node: left, onChanged: (l) => onChanged(rebuild(l, right)), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('右操作数:', style: _labelStyle),
        ExprBuilder(node: right, onChanged: (r) => onChanged(rebuild(left, r)), depth: depth + 1),
      ],
    );
  }

  // ── Between editor ────────────────────────────────────────

  Widget _betweenEditor(ExprNode val, ExprNode low, ExprNode high) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('值:', style: _labelStyle),
        ExprBuilder(node: val, onChanged: (v) => onChanged(BetweenExpr(v, low, high)), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('下界:', style: _labelStyle),
        ExprBuilder(node: low, onChanged: (l) => onChanged(BetweenExpr(val, l, high)), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('上界:', style: _labelStyle),
        ExprBuilder(node: high, onChanged: (h) => onChanged(BetweenExpr(val, low, h)), depth: depth + 1),
      ],
    );
  }

  // ── Range predicate editor (All/Any) ──────────────────────

  Widget _rangePredEditor(dynamic node) {
    final stock = node.stock as StockRef;
    final from = node.from as PathRef;
    final to = node.to as PathRef;
    final pred = node.pred as ExprNode;
    final isAll = node is AllExpr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stockField(stock, (s) {
          if (isAll) onChanged(AllExpr(stock: s, from: from, to: to, pred: pred));
          else onChanged(AnyExpr(stock: s, from: from, to: to, pred: pred));
        }),
        const SizedBox(height: 4),
        const Text('起始:', style: _labelStyle),
        PathRefEditor(value: from, onChanged: (f) {
          if (isAll) onChanged(AllExpr(stock: stock, from: f, to: to, pred: pred));
          else onChanged(AnyExpr(stock: stock, from: f, to: to, pred: pred));
        }),
        const SizedBox(height: 4),
        const Text('终止:', style: _labelStyle),
        PathRefEditor(value: to, onChanged: (t) {
          if (isAll) onChanged(AllExpr(stock: stock, from: from, to: t, pred: pred));
          else onChanged(AnyExpr(stock: stock, from: from, to: t, pred: pred));
        }),
        const SizedBox(height: 4),
        const Text('谓词 (使用逐根遍历):', style: _labelStyle),
        ExprBuilder(node: pred, onChanged: (p) {
          if (isAll) onChanged(AllExpr(stock: stock, from: from, to: to, pred: p));
          else onChanged(AnyExpr(stock: stock, from: from, to: to, pred: p));
        }, depth: depth + 1),
      ],
    );
  }

  // ── CountBars editor ──────────────────────────────────────

  Widget _countBarsEditor(CountBarsExpr node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('起始:', style: _labelStyle),
        PathRefEditor(value: node.from, onChanged: (f) =>
            onChanged(CountBarsExpr(from: f, to: node.to, pred: node.pred, op: node.op, n: node.n))),
        const SizedBox(height: 4),
        const Text('终止:', style: _labelStyle),
        PathRefEditor(value: node.to, onChanged: (t) =>
            onChanged(CountBarsExpr(from: node.from, to: t, pred: node.pred, op: node.op, n: node.n))),
        const SizedBox(height: 4),
        const Text('谓词:', style: _labelStyle),
        ExprBuilder(node: node.pred, onChanged: (p) =>
            onChanged(CountBarsExpr(from: node.from, to: node.to, pred: p, op: node.op, n: node.n)), depth: depth + 1),
        const SizedBox(height: 4),
        Row(children: [
          const Text('比较:', style: _labelStyle),
          const SizedBox(width: 6),
          DropdownButton<CmpOpEnum>(
            value: node.op,
            items: CmpOpEnum.values.map((o) => DropdownMenuItem(value: o, child: Text('${o.symbol} ${o.label}', style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) { if (v != null) onChanged(CountBarsExpr(from: node.from, to: node.to, pred: node.pred, op: v, n: node.n)); },
          ),
          const SizedBox(width: 8),
          SizedBox(width: 60, child: TextFormField(
            initialValue: node.n.toString(),
            decoration: _inputDec('N'),
            style: const TextStyle(fontSize: 12),
            keyboardType: TextInputType.number,
            onChanged: (v) { final n = int.tryParse(v); if (n != null) onChanged(CountBarsExpr(from: node.from, to: node.to, pred: node.pred, op: node.op, n: n)); },
          )),
        ]),
      ],
    );
  }

  // ── Agg / RangeVal editor ─────────────────────────────────

  Widget _aggEditor(AggExpr node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stockField(node.stock, (s) => onChanged(AggExpr(stock: s, from: node.from, to: node.to, col: node.col, func: node.func))),
        const SizedBox(height: 4),
        const Text('起始:', style: _labelStyle),
        PathRefEditor(value: node.from, onChanged: (f) => onChanged(AggExpr(stock: node.stock, from: f, to: node.to, col: node.col, func: node.func))),
        const SizedBox(height: 4),
        const Text('终止:', style: _labelStyle),
        PathRefEditor(value: node.to, onChanged: (t) => onChanged(AggExpr(stock: node.stock, from: node.from, to: t, col: node.col, func: node.func))),
        const SizedBox(height: 4),
        Row(children: [
          const Text('列名:', style: _labelStyle),
          const SizedBox(width: 6),
          SizedBox(width: 80, child: TextFormField(initialValue: node.col, decoration: _inputDec('close'), style: const TextStyle(fontSize: 12), onChanged: (v) => onChanged(AggExpr(stock: node.stock, from: node.from, to: node.to, col: v, func: node.func)))),
          const SizedBox(width: 8),
          const Text('函数:', style: _labelStyle),
          const SizedBox(width: 6),
          DropdownButton<AggFuncEnum>(
            value: node.func,
            items: AggFuncEnum.values.map((f) => DropdownMenuItem(value: f, child: Text(f.label, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) { if (v != null) onChanged(AggExpr(stock: node.stock, from: node.from, to: node.to, col: node.col, func: v)); },
          ),
        ]),
      ],
    );
  }

  Widget _rangeValEditor(RangeValExpr node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stockField(node.stock, (s) => onChanged(RangeValExpr(stock: s, from: node.from, to: node.to, col: node.col, func: node.func))),
        const SizedBox(height: 4),
        const Text('起始:', style: _labelStyle),
        PathRefEditor(value: node.from, onChanged: (f) => onChanged(RangeValExpr(stock: node.stock, from: f, to: node.to, col: node.col, func: node.func))),
        const SizedBox(height: 4),
        const Text('终止:', style: _labelStyle),
        PathRefEditor(value: node.to, onChanged: (t) => onChanged(RangeValExpr(stock: node.stock, from: node.from, to: t, col: node.col, func: node.func))),
        const SizedBox(height: 4),
        Row(children: [
          const Text('列名:', style: _labelStyle),
          const SizedBox(width: 6),
          SizedBox(width: 80, child: TextFormField(initialValue: node.col, decoration: _inputDec('close'), style: const TextStyle(fontSize: 12), onChanged: (v) => onChanged(RangeValExpr(stock: node.stock, from: node.from, to: node.to, col: v, func: node.func)))),
          const SizedBox(width: 8),
          const Text('函数:', style: _labelStyle),
          const SizedBox(width: 6),
          DropdownButton<AggFuncEnum>(
            value: node.func,
            items: AggFuncEnum.values.map((f) => DropdownMenuItem(value: f, child: Text(f.label, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) { if (v != null) onChanged(RangeValExpr(stock: node.stock, from: node.from, to: node.to, col: node.col, func: v)); },
          ),
        ]),
      ],
    );
  }

  // ── Cross editor ──────────────────────────────────────────

  Widget _crossEditor(dynamic node, bool isUp) {
    final stock = node.stock as StockRef;
    final at = node.at as PathRef;
    final col = node.col as String;
    final threshold = node.threshold as ExprNode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stockField(stock, (s) {
          if (isUp) onChanged(CrossUpExpr(stock: s, at: at, col: col, threshold: threshold));
          else onChanged(CrossDownExpr(stock: s, at: at, col: col, threshold: threshold));
        }),
        const SizedBox(height: 4),
        const Text('在K线:', style: _labelStyle),
        PathRefEditor(value: at, onChanged: (a) {
          if (isUp) onChanged(CrossUpExpr(stock: stock, at: a, col: col, threshold: threshold));
          else onChanged(CrossDownExpr(stock: stock, at: a, col: col, threshold: threshold));
        }),
        const SizedBox(height: 4),
        Row(children: [
          const Text('穿越列:', style: _labelStyle),
          const SizedBox(width: 6),
          SizedBox(width: 80, child: TextFormField(initialValue: col, decoration: _inputDec('close'), style: const TextStyle(fontSize: 12), onChanged: (v) {
            if (isUp) onChanged(CrossUpExpr(stock: stock, at: at, col: v, threshold: threshold));
            else onChanged(CrossDownExpr(stock: stock, at: at, col: v, threshold: threshold));
          })),
        ]),
        const SizedBox(height: 4),
        const Text('阈值:', style: _labelStyle),
        ExprBuilder(node: threshold, onChanged: (t) {
          if (isUp) onChanged(CrossUpExpr(stock: stock, at: at, col: col, threshold: t));
          else onChanged(CrossDownExpr(stock: stock, at: at, col: col, threshold: t));
        }, depth: depth + 1),
      ],
    );
  }

  // ── CandleIs editor ───────────────────────────────────────

  Widget _candleIsEditor(CandleIsExpr node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stockField(node.stock, (s) => onChanged(CandleIsExpr(stock: s, at: node.at, candle: node.candle))),
        const SizedBox(height: 4),
        const Text('在K线:', style: _labelStyle),
        PathRefEditor(value: node.at, onChanged: (a) => onChanged(CandleIsExpr(stock: node.stock, at: a, candle: node.candle))),
        const SizedBox(height: 4),
        Row(children: [
          const Text('形态:', style: _labelStyle),
          const SizedBox(width: 6),
          DropdownButton<CandleTypeEnum>(
            value: node.candle,
            items: CandleTypeEnum.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) { if (v != null) onChanged(CandleIsExpr(stock: node.stock, at: node.at, candle: v)); },
          ),
        ]),
      ],
    );
  }

  // ── Monotone editor ───────────────────────────────────────

  Widget _monotoneEditor(MonotoneExpr node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stockField(node.stock, (s) => onChanged(MonotoneExpr(stock: s, from: node.from, to: node.to, col: node.col, dir: node.dir))),
        const SizedBox(height: 4),
        const Text('起始:', style: _labelStyle),
        PathRefEditor(value: node.from, onChanged: (f) => onChanged(MonotoneExpr(stock: node.stock, from: f, to: node.to, col: node.col, dir: node.dir))),
        const SizedBox(height: 4),
        const Text('终止:', style: _labelStyle),
        PathRefEditor(value: node.to, onChanged: (t) => onChanged(MonotoneExpr(stock: node.stock, from: node.from, to: t, col: node.col, dir: node.dir))),
        const SizedBox(height: 4),
        Row(children: [
          const Text('列名:', style: _labelStyle),
          const SizedBox(width: 6),
          SizedBox(width: 80, child: TextFormField(initialValue: node.col, decoration: _inputDec('close'), style: const TextStyle(fontSize: 12), onChanged: (v) => onChanged(MonotoneExpr(stock: node.stock, from: node.from, to: node.to, col: v, dir: node.dir)))),
          const SizedBox(width: 8),
          const Text('方向:', style: _labelStyle),
          const SizedBox(width: 6),
          DropdownButton<MonotoneDirEnum>(
            value: node.dir,
            items: MonotoneDirEnum.values.map((d) => DropdownMenuItem(value: d, child: Text(d.label, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) { if (v != null) onChanged(MonotoneExpr(stock: node.stock, from: node.from, to: node.to, col: node.col, dir: v)); },
          ),
        ]),
      ],
    );
  }

  // ── SyncWithMarket editor ─────────────────────────────────

  Widget _syncWithMarketEditor(SyncWithMarketExpr node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('起始:', style: _labelStyle),
        PathRefEditor(value: node.from, onChanged: (f) => onChanged(SyncWithMarketExpr(f, node.to))),
        const SizedBox(height: 4),
        const Text('终止:', style: _labelStyle),
        PathRefEditor(value: node.to, onChanged: (t) => onChanged(SyncWithMarketExpr(node.from, t))),
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────────

  Widget _stockField(StockRef stock, ValueChanged<StockRef> onChanged) {
    final currentVal = stock.stockType;
    final dropdownVal = currentVal == 'named' || currentVal == 'marketNamed' ? 'current' : currentVal;

    return Row(
      children: [
        const Text('股票:', style: _labelStyle),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: dropdownVal,
          items: const [
            DropdownMenuItem(value: 'current', child: Text('当前股票', style: TextStyle(fontSize: 11))),
            DropdownMenuItem(value: 'market', child: Text('大盘指数', style: TextStyle(fontSize: 11))),
          ],
          onChanged: (v) {
            if (v == 'current') onChanged(StockRef.current);
            else if (v == 'market') onChanged(StockRef.market);
          },
        ),
      ],
    );
  }

  static const _labelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary);

  InputDecoration _inputDec(String? hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
  );
}
