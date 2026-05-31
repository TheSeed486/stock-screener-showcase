import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'screener_models.dart';

class ScreenerIndicatorEditor extends StatefulWidget {
  final List<CustomIndicator> indicators;
  final ValueChanged<List<CustomIndicator>> onChanged;

  const ScreenerIndicatorEditor({
    super.key,
    required this.indicators,
    required this.onChanged,
  });

  @override
  State<ScreenerIndicatorEditor> createState() => _ScreenerIndicatorEditorState();
}

class _ScreenerIndicatorEditorState extends State<ScreenerIndicatorEditor> {
  late List<CustomIndicator> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.indicators);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.functions, size: 20, color: AppColors.brand),
          SizedBox(width: 8),
          Text('自定义指标', style: TextStyle(fontFamily: 'MiSans')),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _presetTemplates(),
            const SizedBox(height: 10),
            if (_items.isNotEmpty) ...[
              const Text('已定义指标：', style: _labelStyle),
              const SizedBox(height: 6),
              ...List.generate(_items.length, (i) => _indicatorRow(i)),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: () => _addNew(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建指标'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.onChanged(List.from(_items));
            Navigator.pop(context);
          },
          child: const Text('确认'),
        ),
      ],
    );
  }

  Widget _presetTemplates() {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _presetBtn('SMA', 'close 均线', () {
            _items.add(CustomIndicator(
              id: 'my_sma_${_items.length + 1}',
              paramNames: const ['period'],
              label: '自定义SMA',
              outputs: [
                IndicatorOutputDef(
                  colNameTemplate: 'my_sma_{period}',
                  formula: RollingMeanNode(
                    src: const ColNode('close'),
                    period: const ParamNode('period'),
                  ),
                ),
              ],
            ));
            setState(() {});
          }),
          const SizedBox(width: 8),
          _presetBtn('BOLL', '布林带', () {
            _items.add(CustomIndicator(
              id: 'my_boll_${_items.length + 1}',
              paramNames: const ['period', 'k'],
              label: '自定义BOLL',
              outputs: [
                IndicatorOutputDef(
                  colNameTemplate: 'my_boll_mid_{period}',
                  formula: RollingMeanNode(
                    src: const ColNode('close'),
                    period: const ParamNode('period'),
                  ),
                ),
                IndicatorOutputDef(
                  colNameTemplate: 'my_boll_upper_{period}',
                  formula: AddNode(
                    a: RollingMeanNode(src: const ColNode('close'), period: const ParamNode('period')),
                    b: MulNode(
                      a: RollingStdNode(src: const ColNode('close'), period: const ParamNode('period')),
                      b: const ParamNode('k'),
                    ),
                  ),
                ),
              ],
            ));
            setState(() {});
          }),
          const SizedBox(width: 8),
          _presetBtn('VOL_MA', '成交量均线', () {
            _items.add(CustomIndicator(
              id: 'my_vol_ma_${_items.length + 1}',
              paramNames: const ['period'],
              label: '自定义VOL_MA',
              outputs: [
                IndicatorOutputDef(
                  colNameTemplate: 'my_vol_ma_{period}',
                  formula: RollingMeanNode(
                    src: const ColNode('volume'),
                    period: const ParamNode('period'),
                  ),
                ),
              ],
            ));
            setState(() {});
          }),
        ],
      ),
    );
  }

  Widget _presetBtn(String label, String desc, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brand)),
            const SizedBox(width: 4),
            Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _indicatorRow(int index) {
    final item = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        leading: const Icon(Icons.functions, size: 18, color: AppColors.brand),
        title: Text('${item.label} (${item.id})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('参数: ${item.paramNames.join(", ")}，${item.outputs.length} 个输出列', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.delete, size: 16, color: AppColors.rise), onPressed: () { _items.removeAt(index); setState(() {}); }),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _IndicatorDetailEditor(
              indicator: item,
              onChanged: (v) {
                _items[index] = v;
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  void _addNew() {
    _items.add(CustomIndicator(
      id: 'indicator_${_items.length + 1}',
      paramNames: const ['period'],
      label: '新指标',
      outputs: [
        IndicatorOutputDef(
          colNameTemplate: 'custom_col',
          formula: RollingMeanNode(src: const ColNode('close'), period: const ParamNode('period')),
        ),
      ],
    ));
    setState(() {});
  }

  static const _labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'MiSans');
}

// ── Detail editor for a single indicator ───────────────────────

class _IndicatorDetailEditor extends StatefulWidget {
  final CustomIndicator indicator;
  final ValueChanged<CustomIndicator> onChanged;

  const _IndicatorDetailEditor({required this.indicator, required this.onChanged});

  @override
  State<_IndicatorDetailEditor> createState() => _IndicatorDetailEditorState();
}

class _IndicatorDetailEditorState extends State<_IndicatorDetailEditor> {
  late TextEditingController _idCtrl;
  late TextEditingController _labelCtrl;
  late List<TextEditingController> _paramCtrls;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.indicator.id);
    _labelCtrl = TextEditingController(text: widget.indicator.label);
    _paramCtrls = widget.indicator.paramNames.map((p) => TextEditingController(text: p)).toList();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _labelCtrl.dispose();
    for (final c in _paramCtrls) { c.dispose(); }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(widget.indicator.copyWith(
      id: _idCtrl.text.trim().isEmpty ? 'ind' : _idCtrl.text.trim(),
      label: _labelCtrl.text.trim().isEmpty ? '指标' : _labelCtrl.text.trim(),
      paramNames: _paramCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('ID：', style: _detailLabelStyle),
            SizedBox(width: 100, child: _tf(_idCtrl, '字母数字下划线', _emit)),
            const SizedBox(width: 12),
            const Text('标签：', style: _detailLabelStyle),
            SizedBox(width: 120, child: _tf(_labelCtrl, '中文名', _emit)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('参数：', style: _detailLabelStyle),
            ...List.generate(_paramCtrls.length, (i) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(width: 80, child: _tf(_paramCtrls[i], '参数名', _emit)),
            )),
            InkWell(
              onTap: () {
                _paramCtrls.add(TextEditingController());
                _emit();
                setState(() {});
              },
              child: const Icon(Icons.add_circle_outline, size: 18, color: AppColors.brand),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('输出列：', style: _detailLabelStyle),
        const SizedBox(height: 4),
        ...List.generate(widget.indicator.outputs.length, (i) {
          return _OutputEditor(
            output: widget.indicator.outputs[i],
            paramNames: widget.indicator.paramNames,
            onChanged: (o) {
              final newOutputs = widget.indicator.outputs.toList();
              newOutputs[i] = o;
              widget.onChanged(widget.indicator.copyWith(outputs: newOutputs));
              setState(() {});
            },
            onDelete: widget.indicator.outputs.length > 1 ? () {
              final newOutputs = widget.indicator.outputs.toList();
              newOutputs.removeAt(i);
              widget.onChanged(widget.indicator.copyWith(outputs: newOutputs));
              setState(() {});
            } : null,
          );
        }),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () {
            widget.onChanged(widget.indicator.copyWith(
              outputs: [
                ...widget.indicator.outputs,
                IndicatorOutputDef(
                  colNameTemplate: 'custom_col_${widget.indicator.outputs.length + 1}',
                  formula: const ColNode('close'),
                ),
              ],
            ));
            setState(() {});
          },
          icon: const Icon(Icons.add, size: 14),
          label: const Text('添加输出列', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  Widget _tf(TextEditingController ctrl, String hint, VoidCallback onChanged) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.brand)),
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: (_) => onChanged(),
    );
  }

  static const _detailLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary);
}

// ── Output editor ──────────────────────────────────────────────

class _OutputEditor extends StatefulWidget {
  final IndicatorOutputDef output;
  final List<String> paramNames;
  final ValueChanged<IndicatorOutputDef> onChanged;
  final VoidCallback? onDelete;

  const _OutputEditor({required this.output, required this.paramNames, required this.onChanged, this.onDelete});

  @override
  State<_OutputEditor> createState() => _OutputEditorState();
}

class _OutputEditorState extends State<_OutputEditor> {
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.output.colNameTemplate);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('列名模板：', style: _detailLabelStyle),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. ma_{period}',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  style: const TextStyle(fontSize: 11),
                  onChanged: (v) {
                    widget.onChanged(widget.output.copyWith(colNameTemplate: v));
                  },
                ),
              ),
              const Spacer(),
              if (widget.onDelete != null)
                InkWell(
                  onTap: widget.onDelete,
                  child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('公式：', style: _detailLabelStyle),
          const SizedBox(height: 4),
          _FormulaEditor(
            node: widget.output.formula,
            paramNames: widget.paramNames,
            onChanged: (f) => widget.onChanged(widget.output.copyWith(formula: f)),
            depth: 0,
          ),
        ],
      ),
    );
  }

  static const _detailLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary);
}

// ── Recursive formula editor ───────────────────────────────────

class _FormulaEditor extends StatelessWidget {
  final IndicatorFormulaNode node;
  final List<String> paramNames;
  final ValueChanged<IndicatorFormulaNode> onChanged;
  final int depth;

  const _FormulaEditor({required this.node, required this.paramNames, required this.onChanged, required this.depth});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: depth * 14.0),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _typeSelector(context),
          const SizedBox(height: 4),
          _content(context),
        ],
      ),
    );
  }

  String get _currentType {
    return switch (node) {
      ColNode() => 'Col',
      LitNode() => 'Lit',
      ParamNode() => 'Param',
      RollingMeanNode() => 'RollingMean',
      RollingStdNode() => 'RollingStd',
      RollingMaxNode() => 'RollingMax',
      RollingMinNode() => 'RollingMin',
      RollingSumNode() => 'RollingSum',
      ShiftNode() => 'Shift',
      AddNode() => 'Add',
      SubNode() => 'Sub',
      MulNode() => 'Mul',
      DivNode() => 'Div',
    };
  }

  static const _nodeTypes = <String>[
    'Col', 'Lit', 'Param',
    'RollingMean', 'RollingStd', 'RollingMax', 'RollingMin', 'RollingSum',
    'Shift', 'Add', 'Sub', 'Mul', 'Div',
  ];

  Widget _typeSelector(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: _currentType,
      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
      isDense: true,
      style: const TextStyle(fontSize: 11),
      items: _nodeTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 11)))).toList(),
      onChanged: (t) {
        if (t != null && t != _currentType) {
          onChanged(_createDefault(t));
        }
      },
    );
  }

  Widget _content(BuildContext context) {
    return switch (node) {
      ColNode(:final column) => Row(
        children: [
          const Text('字段：', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: column,
              isDense: true,
              style: const TextStyle(fontSize: 11),
              items: const ['open', 'high', 'low', 'close', 'volume', 'amount']
                  .map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontSize: 11))))
                  .toList(),
              onChanged: (v) { if (v != null) onChanged(ColNode(v)); },
            ),
          ),
        ],
      ),
      LitNode(:final value) => Row(
        children: [
          const Text('数值：', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: value.toString(),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
              style: const TextStyle(fontSize: 11),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final p = double.tryParse(v);
                if (p != null) onChanged(LitNode(p));
              },
            ),
          ),
        ],
      ),
      ParamNode(:final paramName) => Row(
        children: [
          const Text('参数：', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: paramNames.contains(paramName) ? paramName : null,
              isDense: true,
              style: const TextStyle(fontSize: 11),
              items: paramNames.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 11)))).toList(),
              onChanged: (v) { if (v != null) onChanged(ParamNode(v)); },
            ),
          ),
        ],
      ),
      RollingMeanNode(:final src, :final period) => _buildRolling('RollingMean', src, period),
      RollingStdNode(:final src, :final period) => _buildRolling('RollingStd', src, period),
      RollingMaxNode(:final src, :final period) => _buildRolling('RollingMax', src, period),
      RollingMinNode(:final src, :final period) => _buildRolling('RollingMin', src, period),
      RollingSumNode(:final src, :final period) => _buildRolling('RollingSum', src, period),
      ShiftNode(:final src, :final periods) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('源：', style: TextStyle(fontSize: 11)),
          _FormulaEditor(node: src, paramNames: paramNames, onChanged: (s) => onChanged(ShiftNode(src: s, periods: periods)), depth: depth + 1),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('偏移量：', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              SizedBox(
                width: 60,
                child: TextFormField(
                  initialValue: periods.toString(),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                  style: const TextStyle(fontSize: 11),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final p = int.tryParse(v);
                    if (p != null) onChanged(ShiftNode(src: src, periods: p));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      AddNode(:final a, :final b) => _buildBin('Add', a, b),
      SubNode(:final a, :final b) => _buildBin('Sub', a, b),
      MulNode(:final a, :final b) => _buildBin('Mul', a, b),
      DivNode(:final a, :final b) => _buildBin('Div', a, b),
    };
  }

  Widget _buildRolling(String type, IndicatorFormulaNode src, IndicatorFormulaNode period) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('源数据：', style: TextStyle(fontSize: 11)),
        _FormulaEditor(node: src, paramNames: paramNames, onChanged: (s) => onChanged(_makeRolling(type, s, period)), depth: depth + 1),
        const SizedBox(height: 4),
        _periodEditor(period, (p) => onChanged(_makeRolling(type, src, p))),
      ],
    );
  }

  Widget _periodEditor(IndicatorFormulaNode period, ValueChanged<IndicatorFormulaNode> cb) {
    // Period is typically a Lit or Param
    return Row(
      children: [
        const Text('周期：', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          child: DropdownButtonFormField<String>(
            value: _periodLabel(period),
            isDense: true,
            style: const TextStyle(fontSize: 11),
            items: [
              const DropdownMenuItem(value: '__lit__', child: Text('固定数值', style: TextStyle(fontSize: 11))),
              ...paramNames.map((p) => DropdownMenuItem(value: p, child: Text('参数：$p', style: TextStyle(fontSize: 11)))),
            ],
            onChanged: (v) {
              if (v == '__lit__') {
                cb(const LitNode(20));
              } else if (v != null) {
                cb(ParamNode(v));
              }
            },
          ),
        ),
        if (period is LitNode) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            child: TextFormField(
              initialValue: period.value.toInt().toString(),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
              style: const TextStyle(fontSize: 11),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final p = int.tryParse(v);
                if (p != null) cb(LitNode(p.toDouble()));
              },
            ),
          ),
        ],
      ],
    );
  }

  String _periodLabel(IndicatorFormulaNode p) {
    if (p is ParamNode) return p.paramName;
    return '__lit__';
  }

  Widget _buildBin(String type, IndicatorFormulaNode a, IndicatorFormulaNode b) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(type, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brand)),
            const SizedBox(width: 4),
            const Text('左操作数：', style: TextStyle(fontSize: 11)),
          ],
        ),
        _FormulaEditor(node: a, paramNames: paramNames, onChanged: (na) => onChanged(_makeBin(type, na, b)), depth: depth + 1),
        const SizedBox(height: 4),
        const Text('右操作数：', style: TextStyle(fontSize: 11)),
        _FormulaEditor(node: b, paramNames: paramNames, onChanged: (nb) => onChanged(_makeBin(type, a, nb)), depth: depth + 1),
      ],
    );
  }

  IndicatorFormulaNode _makeRolling(String type, IndicatorFormulaNode src, IndicatorFormulaNode period) {
    return switch (type) {
      'RollingMean' => RollingMeanNode(src: src, period: period),
      'RollingStd' => RollingStdNode(src: src, period: period),
      'RollingMax' => RollingMaxNode(src: src, period: period),
      'RollingMin' => RollingMinNode(src: src, period: period),
      'RollingSum' => RollingSumNode(src: src, period: period),
      _ => RollingMeanNode(src: src, period: period),
    };
  }

  IndicatorFormulaNode _makeBin(String type, IndicatorFormulaNode a, IndicatorFormulaNode b) {
    return switch (type) {
      'Add' => AddNode(a: a, b: b),
      'Sub' => SubNode(a: a, b: b),
      'Mul' => MulNode(a: a, b: b),
      'Div' => DivNode(a: a, b: b),
      _ => AddNode(a: a, b: b),
    };
  }

  IndicatorFormulaNode _createDefault(String type) {
    return switch (type) {
      'Col' => const ColNode('close'),
      'Lit' => const LitNode(0),
      'Param' => ParamNode(paramNames.isNotEmpty ? paramNames.first : 'period'),
      'RollingMean' => RollingMeanNode(src: const ColNode('close'), period: const LitNode(20)),
      'RollingStd' => RollingStdNode(src: const ColNode('close'), period: const LitNode(20)),
      'RollingMax' => RollingMaxNode(src: const ColNode('close'), period: const LitNode(20)),
      'RollingMin' => RollingMinNode(src: const ColNode('close'), period: const LitNode(20)),
      'RollingSum' => RollingSumNode(src: const ColNode('close'), period: const LitNode(20)),
      'Shift' => ShiftNode(src: const ColNode('close'), periods: 1),
      'Add' => AddNode(a: const ColNode('close'), b: const LitNode(0)),
      'Sub' => SubNode(a: const ColNode('close'), b: const LitNode(0)),
      'Mul' => MulNode(a: const ColNode('close'), b: const LitNode(1)),
      'Div' => DivNode(a: const ColNode('close'), b: const LitNode(1)),
      _ => const ColNode('close'),
    };
  }
}
