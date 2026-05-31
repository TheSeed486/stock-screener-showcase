// Stage editor — the main editor area for a single stage.
// Redesigned: inline condition editing, custom indicator editor,
// multi-block pattern editor, results in dialog.

import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../screener_view_model.dart';
import '../models/stage_model.dart';
import '../models/expr_node.dart';
import '../models/enums.dart';
import '../models/indicator_model.dart';
import '../models/pattern_model.dart';
import '../models/path_ref.dart';
import 'expr_builder.dart';
import 'custom_indicator_editor.dart';

class StageEditor extends StatefulWidget {
  final ScreenerViewModel vm;
  const StageEditor({super.key, required this.vm});

  @override
  State<StageEditor> createState() => _StageEditorState();
}

class _StageEditorState extends State<StageEditor> {
  late TextEditingController _nameCtrl;
  late TextEditingController _windowCtrl;
  int _lastStageIndex = -1;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _windowCtrl = TextEditingController();
    _syncControllers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _windowCtrl.dispose();
    super.dispose();
  }

  void _syncControllers() {
    final stage = widget.vm.program.stages[widget.vm.selectedStageIndex];
    _nameCtrl.text = stage.name;
    _windowCtrl.text = stage.windowSize is ExactWindowSize
        ? (stage.windowSize as ExactWindowSize).n.toString()
        : '60';
    _lastStageIndex = widget.vm.selectedStageIndex;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vm.program.stages.isEmpty) return const SizedBox.shrink();
    if (_lastStageIndex != widget.vm.selectedStageIndex) {
      _syncControllers();
    }
    final stage = widget.vm.program.stages[widget.vm.selectedStageIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stageConfig(stage),
          const SizedBox(height: 12),
          _buildCustomIndicatorsSection(),
          const SizedBox(height: 12),
          _buildConditionsSection(stage),
          const SizedBox(height: 12),
          _buildIndicatorCallsSection(stage),
          const SizedBox(height: 12),
          _buildPatternSection(stage),
          const SizedBox(height: 12),
          _buildPointsSection(stage),
          const SizedBox(height: 12),
          _buildVarsSection(stage),
          const SizedBox(height: 12),
          _buildMarksSection(stage),
        ],
      ),
    );
  }

  // ── Stage config ──────────────────────────────────────────

  Widget _stageConfig(StageModel stage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            height: 32,
            child: TextField(
              controller: _nameCtrl,
              decoration: _inputDec('阶段名称'),
              style: const TextStyle(fontSize: 12),
              onChanged: widget.vm.updateStageName,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: DropdownButtonFormField<TimeframeEnum>(
              value: stage.timeframe,
              decoration: _inputDec(null),
              isDense: true,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              items: TimeframeEnum.values.map((t) => DropdownMenuItem(
                value: t,
                child: Text(t.label, style: const TextStyle(fontSize: 12)),
              )).toList(),
              onChanged: (v) { if (v != null) widget.vm.updateStageTimeframe(v); },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            height: 32,
            child: TextField(
              controller: _windowCtrl,
              decoration: _inputDec('K线根数'),
              style: const TextStyle(fontSize: 12),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) widget.vm.updateStageWindowSize(ExactWindowSize(n));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Custom indicators section ─────────────────────────────

  Widget _buildCustomIndicatorsSection() {
    final indicators = widget.vm.program.customIndicators;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('自定义指标', Icons.functions, () => _editCustomIndicator(context)),
        ...indicators.asMap().entries.map((e) => _customIndicatorRow(e.key, e.value)),
        if (indicators.isEmpty)
          _emptyHint('暂无自定义指标 — 点击 [添加] 创建如 EMA、布林带等自定义指标'),
      ],
    );
  }

  Widget _customIndicatorRow(int index, CustomIndicator ci) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${ci.label} (${ci.id})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text('参数: ${ci.paramNames.join(", ")} | 输出: ${ci.outputs.map((o) => o.colNameTemplate).join(", ")}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
          InkWell(
            onTap: () => _editCustomIndicator(context, existing: ci, index: index),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.edit, size: 14, color: AppColors.textMuted)),
          ),
          InkWell(
            onTap: () {
              final newList = [...widget.vm.program.customIndicators]..removeAt(index);
              widget.vm.updateIndicators(newList);
            },
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _editCustomIndicator(BuildContext context, {CustomIndicator? existing, int? index}) async {
    final result = await showDialog<CustomIndicator>(
      context: context,
      builder: (ctx) => CustomIndicatorEditorDialog(existing: existing),
    );
    if (result != null) {
      final newList = [...widget.vm.program.customIndicators];
      if (index != null) {
        newList[index] = result;
      } else {
        newList.add(result);
      }
      widget.vm.updateIndicators(newList);
    }
  }

  // ── Conditions section (inline ExprBuilder) ───────────────

  Widget _buildConditionsSection(StageModel stage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('筛选条件', Icons.checklist, () {
          widget.vm.addCondition(ConditionModel(
            name: '条件 ${stage.conditions.length + 1}',
            expr: GtExpr(PathExprNode(PathRef.close()), NumExpr(0)),
          ));
        }),
        ...stage.conditions.asMap().entries.map((e) => _conditionRow(e.key, e.value)),
        if (stage.conditions.isEmpty)
          _emptyHint('暂无条件 — 点击 [添加] 创建第一个条件'),
      ],
    );
  }

  Widget _conditionRow(int index, ConditionModel c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 28,
                child: TextField(
                  controller: TextEditingController(text: c.name),
                  decoration: _inputDec('条件名称'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  onChanged: (v) => widget.vm.updateCondition(index, c.copyWith(name: v)),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => widget.vm.removeCondition(index),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, size: 16, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ExprBuilder(
            node: c.expr,
            onChanged: (newExpr) => widget.vm.updateCondition(index, c.copyWith(expr: newExpr)),
          ),
        ],
      ),
    );
  }

  // ── Indicator calls section ───────────────────────────────

  Widget _buildIndicatorCallsSection(StageModel stage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('指标调用 (Prepare)', Icons.show_chart, () => _addIndicatorCall(context)),
        ...stage.prepare.asMap().entries.map((e) => _indicatorCallRow(e.key, e.value)),
        if (stage.prepare.isEmpty)
          _emptyHint('暂无指标调用 — 添加条件中引用的指标会自动收集，也可手动添加'),
      ],
    );
  }

  Widget _indicatorCallRow(int index, IndicatorCallModel ic) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(child: Text(ic.displayLabel, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
          InkWell(
            onTap: () => widget.vm.removeIndicatorCall(index),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  // ── K-line pattern section (multi-block) ──────────────────

  Widget _buildPatternSection(StageModel stage) {
    final pattern = stage.klinePattern;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('K线形态', Icons.candlestick_chart, () {
          widget.vm.updateStage(widget.vm.selectedStageIndex, stage.copyWith(
            klinePattern: KlinePatternModel(name: '新形态', blocks: [
              PatternBlockModel(blockName: '块1', pattern: CandleTypeEnum.up, blockSize: ExactWindowSize(1)),
            ]),
          ));
        }),
        if (pattern != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 28,
                      child: TextField(
                        controller: TextEditingController(text: pattern.name),
                        decoration: _inputDec('形态名称'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        onChanged: (v) => widget.vm.updateStage(widget.vm.selectedStageIndex,
                          stage.copyWith(klinePattern: pattern.copyWith(name: v))),
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => widget.vm.updateStage(widget.vm.selectedStageIndex,
                        stage.copyWith(clearKlinePattern: true)),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, size: 16, color: AppColors.textMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...pattern.blocks.asMap().entries.map((e) => _patternBlockRow(e.key, e.value, pattern, stage)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    final newBlocks = [...pattern.blocks, PatternBlockModel(
                      blockName: '块${pattern.blocks.length + 1}',
                      pattern: CandleTypeEnum.up,
                      blockSize: ExactWindowSize(1),
                    )];
                    widget.vm.updateStage(widget.vm.selectedStageIndex,
                      stage.copyWith(klinePattern: pattern.copyWith(blocks: newBlocks)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: AppColors.textSecondary),
                        SizedBox(width: 4),
                        Text('添加块', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          _emptyHint('暂无K线形态 — 点击 [添加] 创建多块形态序列（如吞没、晨星等）'),
      ],
    );
  }

  Widget _patternBlockRow(int index, PatternBlockModel block, KlinePatternModel pattern, StageModel stage) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 26,
            child: TextField(
              controller: TextEditingController(text: block.blockName),
              decoration: _inputDec('名称'),
              style: const TextStyle(fontSize: 11),
              onChanged: (v) => _updatePatternBlock(index, block.copyWith(blockName: v), pattern, stage),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: DropdownButton<CandleTypeEnum>(
              value: block.pattern,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
              items: CandleTypeEnum.values.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c.label, style: const TextStyle(fontSize: 11)),
              )).toList(),
              onChanged: (v) { if (v != null) _updatePatternBlock(index, block.copyWith(pattern: v), pattern, stage); },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 45,
            height: 26,
            child: TextField(
              controller: TextEditingController(
                text: block.blockSize is ExactWindowSize
                    ? (block.blockSize as ExactWindowSize).n.toString()
                    : '1',
              ),
              decoration: _inputDec('根数'),
              style: const TextStyle(fontSize: 11),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) {
                  _updatePatternBlock(index, block.copyWith(blockSize: ExactWindowSize(n)), pattern, stage);
                }
              },
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: '可选',
            child: SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: block.optional,
                onChanged: (v) => _updatePatternBlock(index, block.copyWith(optional: v ?? false), pattern, stage),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () {
              final newBlocks = [...pattern.blocks]..removeAt(index);
              widget.vm.updateStage(widget.vm.selectedStageIndex,
                stage.copyWith(klinePattern: pattern.copyWith(blocks: newBlocks)));
            },
            child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  void _updatePatternBlock(int index, PatternBlockModel updated, KlinePatternModel pattern, StageModel stage) {
    final newBlocks = [...pattern.blocks];
    newBlocks[index] = updated;
    widget.vm.updateStage(widget.vm.selectedStageIndex,
      stage.copyWith(klinePattern: pattern.copyWith(blocks: newBlocks)));
  }

  // ── Points section ────────────────────────────────────────

  Widget _buildPointsSection(StageModel stage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('命名点', Icons.location_on, () => _addPoint(context)),
        ...stage.points.asMap().entries.map((e) => _pointRow(e.key, e.value)),
        if (stage.points.isEmpty) _emptyHint('暂无命名点 — 用于标记窗口内的特定位置'),
      ],
    );
  }

  Widget _pointRow(int index, NamedPointModel p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(child: Text(p.displayLabel, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
          InkWell(
            onTap: () => widget.vm.removePoint(index),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  // ── Vars section ──────────────────────────────────────────

  Widget _buildVarsSection(StageModel stage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('变量', Icons.data_object, () => _addVar(context)),
        ...stage.vars.asMap().entries.map((e) => _varRow(e.key, e.value)),
        if (stage.vars.isEmpty) _emptyHint('暂无变量 — 可定义中间计算结果供条件引用'),
      ],
    );
  }

  Widget _varRow(int index, VarDefModel v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(child: Text(v.displayLabel, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
          InkWell(
            onTap: () => widget.vm.removeVar(index),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  // ── Marks section ─────────────────────────────────────────

  Widget _buildMarksSection(StageModel stage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('标记', Icons.bookmark, () => _addMark(context)),
        ...stage.marks.asMap().entries.map((e) => _markRow(e.key, e.value)),
        if (stage.marks.isEmpty) _emptyHint('暂无标记 — 用于在结果中标注特定值'),
      ],
    );
  }

  Widget _markRow(int index, MarkModel m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(child: Text(m.displayLabel, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
          InkWell(
            onTap: () => widget.vm.removeMark(index),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  // ── Section header ────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon, VoidCallback onAdd) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Spacer(),
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 12, color: AppColors.textSecondary),
                  SizedBox(width: 2),
                  Text('添加', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
    );
  }

  // ── Add dialogs ───────────────────────────────────────────

  void _addIndicatorCall(BuildContext context) {
    final moduleIdCtrl = TextEditingController(text: 'sma');
    final periodCtrl = TextEditingController(text: '20');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加指标调用', style: TextStyle(fontFamily: 'MiSans')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: moduleIdCtrl, decoration: _inputDec('指标ID (如 sma, boll, vol_ma)'), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: periodCtrl, decoration: _inputDec('周期参数 (如 20)'), style: const TextStyle(fontSize: 12), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final period = int.tryParse(periodCtrl.text.trim()) ?? 20;
              widget.vm.addIndicatorCall(IndicatorCallModel(
                moduleId: moduleIdCtrl.text.trim(),
                params: {'period': ParamValue.intVal(period)},
              ));
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _addPoint(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'A');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加命名点', style: TextStyle(fontFamily: 'MiSans')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: _inputDec('点名称 (如 A, B)'), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                widget.vm.addPoint(NamedPointModel(
                  name: name,
                  def: WherePointDef(
                    stock: StockRef.current,
                    from: PathRef.close(offset: -20),
                    to: PathRef.close(),
                    pred: BoolExpr(true),
                    select: const PointSelectModel(kind: PointSelectKind.last),
                  ),
                ));
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _addVar(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'var1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加变量', style: TextStyle(fontFamily: 'MiSans')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: _inputDec('变量名'), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                widget.vm.addVar(VarDefModel(name: name, expr: NumExpr(0)));
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _addMark(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'm1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加标记', style: TextStyle(fontFamily: 'MiSans')),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: _inputDec('标记名'), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                widget.vm.addMark(MarkModel(name: name, anchor: PathRef.close()));
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
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
