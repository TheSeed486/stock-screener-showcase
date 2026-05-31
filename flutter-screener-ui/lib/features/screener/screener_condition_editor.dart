import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'screener_models.dart';

class ScreenerConditionEditor extends StatefulWidget {
  final Condition? condition;
  final List<CustomIndicator> customIndicators;
  final ValueChanged<Condition> onSave;

  const ScreenerConditionEditor({
    super.key,
    this.condition,
    this.customIndicators = const [],
    required this.onSave,
  });

  @override
  State<ScreenerConditionEditor> createState() => _ScreenerConditionEditorState();
}

class _ScreenerConditionEditorState extends State<ScreenerConditionEditor> {
  late ConditionKind _kind;

  // compare
  late Metric _left;
  late CompareOp _op;
  late Operand _right;

  // cross
  late CrossDirection _crossDir;
  late Metric _crossLeft, _crossRight;

  // candle
  late CandlePattern _candle;

  // gap
  late GapDirection _gapDir;
  double _gapPct = 2.0;

  List<CustomIndicator> get _indicators => widget.customIndicators;

  @override
  void initState() {
    super.initState();
    final c = widget.condition;
    _kind = c?.kind ?? ConditionKind.compare;

    if (c is CompareCondition) {
      _left = c.left;
      _op = c.op;
      _right = c.right;
    } else {
      _left = const Metric(field: FieldName.close);
      _op = CompareOp.gt;
      _right = const Operand.metric(Metric(field: FieldName.close, transform: MetricTransform.sma, window: 20));
    }

    if (c is CrossCondition) {
      _crossDir = c.direction;
      _crossLeft = c.left;
      _crossRight = c.right;
    } else {
      _crossDir = CrossDirection.up;
      _crossLeft = const Metric(field: FieldName.close);
      _crossRight = const Metric(field: FieldName.close, transform: MetricTransform.sma, window: 20);
    }

    _candle = (c is CandleCondition) ? c.pattern : CandlePattern.bullishEngulfing;
    _gapDir = (c is GapCondition) ? c.direction : GapDirection.up;
    _gapPct = (c is GapCondition) ? c.thresholdPct : 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _result();
    return AlertDialog(
      title: const Text('编辑条件', style: TextStyle(fontFamily: 'MiSans')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kindSelector(),
              const SizedBox(height: 14),
              if (_kind == ConditionKind.compare) ..._compareEditor(),
              if (_kind == ConditionKind.cross) ..._crossEditor(),
              if (_kind == ConditionKind.candle) ..._candleEditor(),
              if (_kind == ConditionKind.gap) ..._gapEditor(),
              const SizedBox(height: 12),
              _previewSection(preview),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.onSave(_result());
            Navigator.pop(context);
          },
          child: const Text('确认'),
        ),
      ],
    );
  }

  Widget _kindSelector() {
    return Row(
      children: [
        const Text('条件类型：', style: _labelStyle),
        const SizedBox(width: 8),
        SegmentedButton<ConditionKind>(
          segments: const [
            ButtonSegment(value: ConditionKind.compare, label: Text('比较')),
            ButtonSegment(value: ConditionKind.cross, label: Text('穿越')),
            ButtonSegment(value: ConditionKind.candle, label: Text('K线形态')),
            ButtonSegment(value: ConditionKind.gap, label: Text('跳空')),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }

  // ── Compare ──────────────────────────────────────────────────

  List<Widget> _compareEditor() => [
    _section('左操作数'),
    _metricEditor(_left, (v) => setState(() => _left = v)),
    const SizedBox(height: 10),
    _section('比较符'),
    _dd<CompareOp>(
      value: _op,
      items: CompareOp.values.map((o) => DropdownMenuItem(value: o, child: Text('${o.symbol} ${o.label}'))).toList(),
      onChanged: (v) => setState(() => _op = v!),
    ),
    const SizedBox(height: 10),
    _section('右操作数'),
    _operandEditor(_right, (v) => setState(() => _right = v)),
  ];

  // ── Cross ────────────────────────────────────────────────────

  List<Widget> _crossEditor() => [
    _section('方向'),
    _dd<CrossDirection>(
      value: _crossDir,
      items: CrossDirection.values.map((d) => DropdownMenuItem(value: d, child: Text(d.label))).toList(),
      onChanged: (v) => setState(() => _crossDir = v!),
    ),
    const SizedBox(height: 10),
    _section('左线'),
    _metricEditor(_crossLeft, (v) => setState(() => _crossLeft = v)),
    const SizedBox(height: 10),
    _section('右线'),
    _metricEditor(_crossRight, (v) => setState(() => _crossRight = v)),
  ];

  // ── Candle ───────────────────────────────────────────────────

  List<Widget> _candleEditor() => [
    _section('形态'),
    _dd<CandlePattern>(
      value: _candle,
      items: CandlePattern.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
      onChanged: (v) => setState(() => _candle = v!),
    ),
  ];

  // ── Gap ──────────────────────────────────────────────────────

  List<Widget> _gapEditor() => [
    _section('方向'),
    _dd<GapDirection>(
      value: _gapDir,
      items: GapDirection.values.map((d) => DropdownMenuItem(value: d, child: Text(d.label))).toList(),
      onChanged: (v) => setState(() => _gapDir = v!),
    ),
    const SizedBox(height: 10),
    _section('阈值 (%)'),
    SizedBox(
      width: 120,
      child: TextFormField(
        initialValue: _gapPct.toString(),
        decoration: _inputDec('例如 2.5'),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final p = double.tryParse(v);
          if (p != null) setState(() => _gapPct = p);
        },
      ),
    ),
  ];

  // ── Metric editor ────────────────────────────────────────────

  Widget _metricEditor(Metric v, ValueChanged<Metric> cb) {
    // Collect custom indicator column options
    final customOptions = <String>[''];
    for (final ci in _indicators) {
      for (final o in ci.outputs) {
        // Show template pattern (e.g. "my_boll_upper_{period}")
        customOptions.add('${ci.id}.${o.colNameTemplate}');
      }
    }

    // If already a custom column, ensure it's in options
    if (v.isCustom && v.customColumn != null && !customOptions.contains(v.customColumn)) {
      customOptions.add(v.customColumn!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Custom column picker (if indicators exist)
        if (customOptions.length > 1) ...[
          _dd<String>(
            value: v.isCustom && v.customColumn != null ? v.customColumn! : '',
            items: customOptions.map((opt) => DropdownMenuItem(
              value: opt,
              child: Text(opt.isEmpty ? '-- 内置字段 --' : opt, style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (sel) {
              if (sel == null || sel.isEmpty) {
                cb(const Metric(field: FieldName.close));
              } else {
                cb(Metric(field: FieldName.close, customColumn: sel));
              }
            },
          ),
          const SizedBox(height: 6),
        ],
        if (!v.isCustom) _fieldTransformEditor(v, cb),
      ],
    );
  }

  Widget _fieldTransformEditor(Metric v, ValueChanged<Metric> cb) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _dd<FieldName>(
            value: v.field,
            items: fieldNameOptions.map((f) => DropdownMenuItem(value: f, child: Text(f.label, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (f) => cb(v.copyWith(field: f!)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: _dd<MetricTransform>(
            value: v.transform,
            items: MetricTransform.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (t) => cb(v.copyWith(transform: t!)),
          ),
        ),
        if (v.transform.requiresWindow) ...[
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: _dd<int>(
              value: windowOptions.contains(v.window) ? v.window : windowOptions.first,
              items: windowOptions.map((w) => DropdownMenuItem(value: w, child: Text('$w', style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (w) => cb(v.copyWith(window: w!)),
            ),
          ),
        ],
        if (!v.transform.requiresWindow) const Spacer(flex: 1),
      ],
    );
  }

  Widget _operandEditor(Operand v, ValueChanged<Operand> cb) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 110,
              height: 36,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('数值', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: false, label: Text('指标', style: TextStyle(fontSize: 11))),
                ],
                selected: {v.isLiteral},
                onSelectionChanged: (s) => cb(v.copyWith(useLiteral: s.first)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: v.isLiteral
                  ? TextFormField(
                      initialValue: v.literalValue?.toString() ?? '0',
                      decoration: _inputDec('数值'),
                      keyboardType: TextInputType.number,
                      onChanged: (s) {
                        final p = double.tryParse(s);
                        if (p != null) cb(v.copyWith(literalValue: p));
                      },
                    )
                  : _metricEditor(v.metric!, (m) => cb(v.copyWith(metric: m))),
            ),
          ],
        ),
        if (!v.isLiteral) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('倍数：', style: _labelStyle),
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: v.multiplier.toString(),
                  decoration: _inputDec('1.0'),
                  keyboardType: TextInputType.number,
                  onChanged: (s) {
                    final p = double.tryParse(s);
                    if (p != null) cb(v.copyWith(multiplier: p));
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Preview ─────────────────────────────────────────────────

  Widget _previewSection(Condition c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('预览', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(c.summary, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  // ── Result ───────────────────────────────────────────────────

  Condition _result() {
    return switch (_kind) {
      ConditionKind.compare => CompareCondition(left: _left, op: _op, right: _right),
      ConditionKind.cross => CrossCondition(direction: _crossDir, left: _crossLeft, right: _crossRight),
      ConditionKind.candle => CandleCondition(pattern: _candle),
      ConditionKind.gap => GapCondition(direction: _gapDir, thresholdPct: _gapPct),
    };
  }

  // ── Helpers ─────────────────────────────────────────────────

  Widget _section(String text) => Text(text, style: _labelStyle);

  Widget _dd<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: _inputDec(null),
      isDense: true,
      items: items,
      onChanged: onChanged,
    );
  }

  InputDecoration _inputDec(String? hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.brand)),
  );

  static const _labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'MiSans');
}

/// Collect all option labels for use in metric selector
List<MapEntry<String, String>> buildCustomMetricOptions(List<CustomIndicator> indicators) {
  final options = <MapEntry<String, String>>[];
  for (final ci in indicators) {
    for (final o in ci.outputs) {
      options.add(MapEntry('${ci.id}.${o.colNameTemplate}', '${ci.label}.${o.colNameTemplate}'));
    }
  }
  return options;
}
