// Custom indicator editor — dialog for creating/editing custom indicators.
// Supports the full IndicatorFormula tree (Col, Lit, Param, Rolling*, Shift, arithmetic, IfElse).

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/indicator_model.dart';

// ── Formula node type catalog ────────────────────────────────

class _FormulaTypeInfo {
  final String label;
  final IndicatorFormulaNode Function() createDefault;
  const _FormulaTypeInfo(this.label, this.createDefault);
}

const _formulaTypes = <_FormulaTypeInfo>[
  _FormulaTypeInfo('列引用', _defCol),
  _FormulaTypeInfo('数值', _defLit),
  _FormulaTypeInfo('参数', _defParam),
  _FormulaTypeInfo('滚动均值 (SMA)', _defRollingMean),
  _FormulaTypeInfo('滚动标准差', _defRollingStd),
  _FormulaTypeInfo('滚动最大值', _defRollingMax),
  _FormulaTypeInfo('滚动最小值', _defRollingMin),
  _FormulaTypeInfo('滚动求和', _defRollingSum),
  _FormulaTypeInfo('偏移', _defShift),
  _FormulaTypeInfo('加法', _defAdd),
  _FormulaTypeInfo('减法', _defSub),
  _FormulaTypeInfo('乘法', _defMul),
  _FormulaTypeInfo('除法', _defDiv),
  _FormulaTypeInfo('绝对值', _defAbs),
  _FormulaTypeInfo('取反', _defNeg),
  _FormulaTypeInfo('条件分支', _defIfElse),
];

IndicatorFormulaNode _defCol() => ColNode('close');
IndicatorFormulaNode _defLit() => LitNode(0);
IndicatorFormulaNode _defParam() => ParamNode('period');
IndicatorFormulaNode _defRollingMean() => RollingMeanNode(src: ColNode('close'), period: ParamNode('period'));
IndicatorFormulaNode _defRollingStd() => RollingStdNode(src: ColNode('close'), period: ParamNode('period'));
IndicatorFormulaNode _defRollingMax() => RollingMaxNode(src: ColNode('close'), period: ParamNode('period'));
IndicatorFormulaNode _defRollingMin() => RollingMinNode(src: ColNode('close'), period: ParamNode('period'));
IndicatorFormulaNode _defRollingSum() => RollingSumNode(src: ColNode('close'), period: ParamNode('period'));
IndicatorFormulaNode _defShift() => ShiftNode(src: ColNode('close'), periods: 1);
IndicatorFormulaNode _defAdd() => AddNode(a: LitNode(0), b: LitNode(0));
IndicatorFormulaNode _defSub() => SubNode(a: LitNode(0), b: LitNode(0));
IndicatorFormulaNode _defMul() => MulNode(a: LitNode(0), b: LitNode(0));
IndicatorFormulaNode _defDiv() => DivNode(a: LitNode(0), b: LitNode(0));
IndicatorFormulaNode _defAbs() => AbsNode(LitNode(0));
IndicatorFormulaNode _defNeg() => NegNode(LitNode(0));
IndicatorFormulaNode _defIfElse() => IfElseNode(cond: LitNode(1), thenVal: LitNode(1), elseVal: LitNode(0));

// ── Recursive formula tree editor ────────────────────────────

class FormulaEditor extends StatelessWidget {
  final IndicatorFormulaNode node;
  final ValueChanged<IndicatorFormulaNode> onChanged;
  final int depth;

  const FormulaEditor({
    super.key,
    required this.node,
    required this.onChanged,
    this.depth = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: depth * 6.0),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
        color: depth.isEven ? AppColors.surface : AppColors.surfaceMuted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _typeSelector(),
          const SizedBox(height: 4),
          _content(),
        ],
      ),
    );
  }

  Widget _typeSelector() {
    return DropdownButtonFormField<String>(
      value: _currentTypeName,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
      ),
      isDense: true,
      style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
      items: _formulaTypes.map((t) => DropdownMenuItem(
        value: t.label,
        child: Text(t.label, style: const TextStyle(fontSize: 11)),
      )).toList(),
      onChanged: (t) {
        if (t != null && t != _currentTypeName) {
          final info = _formulaTypes.firstWhere((f) => f.label == t);
          onChanged(info.createDefault());
        }
      },
    );
  }

  String get _currentTypeName {
    return switch (node) {
      ColNode() => '列引用',
      LitNode() => '数值',
      ParamNode() => '参数',
      RollingMeanNode() => '滚动均值 (SMA)',
      RollingStdNode() => '滚动标准差',
      RollingMaxNode() => '滚动最大值',
      RollingMinNode() => '滚动最小值',
      RollingSumNode() => '滚动求和',
      ShiftNode() => '偏移',
      AddNode() => '加法',
      SubNode() => '减法',
      MulNode() => '乘法',
      DivNode() => '除法',
      AbsNode() => '绝对值',
      NegNode() => '取反',
      IfElseNode() => '条件分支',
    };
  }

  Widget _content() {
    return switch (node) {
      ColNode(:final column) => _stringEditor('列名', column, (v) => onChanged(ColNode(v))),
      LitNode(:final value) => _numEditor('数值', value, (v) => onChanged(LitNode(v))),
      ParamNode(:final paramName) => _stringEditor('参数名', paramName, (v) => onChanged(ParamNode(v))),
      RollingMeanNode(:final src, :final period) => _rollingEditor(src, period, (s, p) => onChanged(RollingMeanNode(src: s, period: p))),
      RollingStdNode(:final src, :final period) => _rollingEditor(src, period, (s, p) => onChanged(RollingStdNode(src: s, period: p))),
      RollingMaxNode(:final src, :final period) => _rollingEditor(src, period, (s, p) => onChanged(RollingMaxNode(src: s, period: p))),
      RollingMinNode(:final src, :final period) => _rollingEditor(src, period, (s, p) => onChanged(RollingMinNode(src: s, period: p))),
      RollingSumNode(:final src, :final period) => _rollingEditor(src, period, (s, p) => onChanged(RollingSumNode(src: s, period: p))),
      ShiftNode(:final src, :final periods) => _shiftEditor(src, periods),
      AddNode(:final a, :final b) => _binaryEditor(a, b, (x, y) => onChanged(AddNode(a: x, b: y))),
      SubNode(:final a, :final b) => _binaryEditor(a, b, (x, y) => onChanged(SubNode(a: x, b: y))),
      MulNode(:final a, :final b) => _binaryEditor(a, b, (x, y) => onChanged(MulNode(a: x, b: y))),
      DivNode(:final a, :final b) => _binaryEditor(a, b, (x, y) => onChanged(DivNode(a: x, b: y))),
      AbsNode(:final child) => _unaryEditor(child, (c) => onChanged(AbsNode(c))),
      NegNode(:final child) => _unaryEditor(child, (c) => onChanged(NegNode(c))),
      IfElseNode(:final cond, :final thenVal, :final elseVal) => _ifElseEditor(cond, thenVal, elseVal),
    };
  }

  Widget _stringEditor(String label, String value, ValueChanged<String> onChanged) {
    return Row(
      children: [
        Text('$label:', style: _labelStyle),
        const SizedBox(width: 6),
        SizedBox(
          width: 100,
          child: TextFormField(
            initialValue: value,
            decoration: _inputDec(label),
            style: const TextStyle(fontSize: 11),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _numEditor(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        Text('$label:', style: _labelStyle),
        const SizedBox(width: 6),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: value.toString(),
            decoration: _inputDec(label),
            style: const TextStyle(fontSize: 11),
            keyboardType: TextInputType.number,
            onChanged: (v) { final n = double.tryParse(v); if (n != null) onChanged(n); },
          ),
        ),
      ],
    );
  }

  Widget _rollingEditor(IndicatorFormulaNode src, IndicatorFormulaNode period,
      void Function(IndicatorFormulaNode src, IndicatorFormulaNode period) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('数据源:', style: _labelStyle),
        FormulaEditor(node: src, onChanged: (s) => onChanged(s, period), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('周期:', style: _labelStyle),
        FormulaEditor(node: period, onChanged: (p) => onChanged(src, p), depth: depth + 1),
      ],
    );
  }

  Widget _shiftEditor(IndicatorFormulaNode src, int periods) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('数据源:', style: _labelStyle),
        FormulaEditor(node: src, onChanged: (s) => onChanged(ShiftNode(src: s, periods: periods)), depth: depth + 1),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('偏移量:', style: _labelStyle),
            const SizedBox(width: 6),
            SizedBox(
              width: 60,
              child: TextFormField(
                initialValue: periods.toString(),
                decoration: _inputDec('N'),
                style: const TextStyle(fontSize: 11),
                keyboardType: TextInputType.number,
                onChanged: (v) { final n = int.tryParse(v); if (n != null) onChanged(ShiftNode(src: src, periods: n)); },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _unaryEditor(IndicatorFormulaNode child, ValueChanged<IndicatorFormulaNode> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('操作数:', style: _labelStyle),
        FormulaEditor(node: child, onChanged: onChanged, depth: depth + 1),
      ],
    );
  }

  Widget _binaryEditor(IndicatorFormulaNode a, IndicatorFormulaNode b,
      void Function(IndicatorFormulaNode, IndicatorFormulaNode) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('左:', style: _labelStyle),
        FormulaEditor(node: a, onChanged: (x) => onChanged(x, b), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('右:', style: _labelStyle),
        FormulaEditor(node: b, onChanged: (y) => onChanged(a, y), depth: depth + 1),
      ],
    );
  }

  Widget _ifElseEditor(IndicatorFormulaNode cond, IndicatorFormulaNode thenVal, IndicatorFormulaNode elseVal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('条件:', style: _labelStyle),
        FormulaEditor(node: cond, onChanged: (c) => onChanged(IfElseNode(cond: c, thenVal: thenVal, elseVal: elseVal)), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('为真时:', style: _labelStyle),
        FormulaEditor(node: thenVal, onChanged: (t) => onChanged(IfElseNode(cond: cond, thenVal: t, elseVal: elseVal)), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('为假时:', style: _labelStyle),
        FormulaEditor(node: elseVal, onChanged: (e) => onChanged(IfElseNode(cond: cond, thenVal: thenVal, elseVal: e)), depth: depth + 1),
      ],
    );
  }

  static const _labelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary);

  InputDecoration _inputDec(String? hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
  );
}

// ── Custom Indicator Editor Dialog ───────────────────────────

class CustomIndicatorEditorDialog extends StatefulWidget {
  final CustomIndicator? existing;
  const CustomIndicatorEditorDialog({super.key, this.existing});

  @override
  State<CustomIndicatorEditorDialog> createState() => _CustomIndicatorEditorDialogState();
}

class _CustomIndicatorEditorDialogState extends State<CustomIndicatorEditorDialog> {
  late TextEditingController _idCtrl;
  late TextEditingController _labelCtrl;
  late TextEditingController _paramsCtrl;
  late List<IndicatorOutputDef> _outputs;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idCtrl = TextEditingController(text: e?.id ?? '');
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _paramsCtrl = TextEditingController(text: e?.paramNames.join(', ') ?? '');
    _outputs = e?.outputs.toList() ?? [
      IndicatorOutputDef(colNameTemplate: '{id}_{period}', formula: ColNode('close')),
    ];
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _labelCtrl.dispose();
    _paramsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? '编辑指标' : '创建自定义指标',
        style: const TextStyle(fontFamily: 'MiSans')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _idCtrl, decoration: _inputDec('指标ID (如 boll, ema)'), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: _labelCtrl, decoration: _inputDec('显示名称 (如 布林带)'), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: _paramsCtrl, decoration: _inputDec('参数名 (逗号分隔, 如 period, k)'), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('输出列:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _outputs.add(
                      IndicatorOutputDef(colNameTemplate: '', formula: ColNode('close')))),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 12, color: AppColors.textSecondary),
                          SizedBox(width: 2),
                          Text('添加输出', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ..._outputs.asMap().entries.map((e) => _outputRow(e.key, e.value)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final id = _idCtrl.text.trim();
            if (id.isEmpty) return;
            final params = _paramsCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            final indicator = CustomIndicator(
              id: id,
              paramNames: params,
              label: _labelCtrl.text.trim().isEmpty ? id : _labelCtrl.text.trim(),
              outputs: _outputs,
            );
            Navigator.pop(context, indicator);
          },
          child: const Text('确认'),
        ),
      ],
    );
  }

  Widget _outputRow(int index, IndicatorOutputDef output) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: output.colNameTemplate),
                  decoration: _inputDec('列名模板 (如 boll_mid_{period})'),
                  style: const TextStyle(fontSize: 11),
                  onChanged: (v) {
                    final newOutputs = [..._outputs];
                    newOutputs[index] = output.copyWith(colNameTemplate: v);
                    setState(() => _outputs = newOutputs);
                  },
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() {
                  final newOutputs = [..._outputs]..removeAt(index);
                  _outputs = newOutputs;
                }),
                child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('公式:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          FormulaEditor(
            node: output.formula,
            onChanged: (f) {
              final newOutputs = [..._outputs];
              newOutputs[index] = output.copyWith(formula: f);
              setState(() => _outputs = newOutputs);
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String? hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: AppColors.brand)),
  );
}
