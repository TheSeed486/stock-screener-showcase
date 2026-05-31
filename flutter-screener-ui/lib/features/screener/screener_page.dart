import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../application/rust_runtime_bootstrap.dart';
import '../../src/rust/api/screener.dart' as rust;
import '../../theme/app_colors.dart';
import 'screener_compiler.dart';
import 'screener_condition_editor.dart';
import 'screener_indicator_editor.dart';
import 'screener_models.dart';
import 'screener_results_table.dart';
import 'screener_storage.dart';

class ScreenerPage extends StatefulWidget {
  const ScreenerPage({super.key, required this.isActive});
  final bool isActive;

  @override
  State<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends State<ScreenerPage> {
  late ScreenerProgram _prog;
  bool _running = false;
  String? _error;
  String? _pipelineJson;
  String? _registryJson;
  List<Map<String, dynamic>> _resultRows = const [];
  List<String> _availableSymbols = const [];
  String _defaultRegistryJson = '{}';
  int _nextId = 2;

  final _nameCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(text: '2026-05-25');
  final _windowCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prog = ScreenerProgram.createDefault();
    _nextId = _prog.groups.length + 1;
    _nameCtrl.text = _prog.name;
    _windowCtrl.text = _prog.windowSize.toString();
    unawaited(_loadDraft());
    unawaited(_loadInitData());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dateCtrl.dispose();
    _windowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final d = await ScreenerStorage.loadDraft();
    if (d != null && mounted) {
      _nameCtrl.text = d.name;
      _windowCtrl.text = d.windowSize.toString();
      setState(() => _prog = d);
    }
  }

  Future<void> _loadInitData() async {
    try {
      await RustRuntimeBootstrap.instance.ensureInitialized();
      final results = await Future.wait([
        rust.listAvailableSymbolsRs(),
        rust.defaultRegistryJsonRs(),
      ]);
      if (mounted) {
        setState(() {
          _availableSymbols = results[0] as List<String>;
          _defaultRegistryJson = results[1] as String;
        });
      }
    } catch (_) {}
  }

  void _setProg(ScreenerProgram p) {
    setState(() => _prog = p);
    unawaited(ScreenerStorage.saveDraft(p));
  }

  void _commitSettings() {
    final ws = int.tryParse(_windowCtrl.text.trim());
    _setProg(_prog.copyWith(
      name: _nameCtrl.text.trim().isEmpty ? '未命名策略' : _nameCtrl.text.trim(),
      windowSize: ws ?? _prog.windowSize,
    ));
  }

  // ── Validate / Run / Save ────────────────────────────────────

  Future<void> _validate() async {
    _commitSettings();
    await _runAction(() async {
      final result = compileScreener(_prog, defaultRegistryJson: _defaultRegistryJson);
      final ok = await rust.validatePipelineRs(pipelineJson: result.pipelineJson);
      if (mounted) {
        setState(() {
          _pipelineJson = result.pipelineJson;
          _registryJson = result.registryJson;
          _error = null;
        });
        _toast(ok ? '校验通过' : 'Pipeline JSON 格式错误');
      }
    });
  }

  Future<void> _run() async {
    _commitSettings();
    await _runAction(() async {
      final result = compileScreener(_prog, defaultRegistryJson: _defaultRegistryJson);
      final symbols = _availableSymbols.isNotEmpty
          ? _availableSymbols.take(100).toList()
          : const <String>[];
      if (symbols.isEmpty) {
        if (mounted) setState(() => _error = '没有可用的股票数据，请先确保数据已下载');
        return;
      }
      final to = _dateCtrl.text.trim();
      final from = _computeFrom(to, _prog.windowSize);
      final resultJson = await rust.runScreenerRs(
        pipelineJson: result.pipelineJson,
        registryJson: result.registryJson,
        symbols: symbols,
        fromDate: from,
        toDate: to,
      );
      if (mounted) {
        setState(() {
          _pipelineJson = result.pipelineJson;
          _registryJson = result.registryJson;
          _resultRows = _parseRows(resultJson);
          _error = null;
        });
      }
    });
  }

  Future<void> _runAction(Future<void> Function() fn) async {
    setState(() {
      _running = true;
      _error = null;
      _resultRows = const [];
    });
    try {
      await RustRuntimeBootstrap.instance.ensureInitialized();
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _saveStrategy() async {
    _commitSettings();
    await ScreenerStorage.saveStrategy(_prog.name, _prog);
    _toast('已保存');
  }

  Future<void> _manageIndicators() async {
    final result = await showDialog<List<CustomIndicator>>(
      context: context,
      builder: (_) => ScreenerIndicatorEditor(
        indicators: _prog.customIndicators,
        onChanged: (list) {},
      ),
    );
    if (result != null && mounted) {
      _setProg(_prog.copyWith(customIndicators: result));
    }
  }

  // ── Group CRUD ───────────────────────────────────────────────

  String _newGroupId() => 'group_${_nextId++}';

  void _addGroup() {
    _setProg(_prog.copyWith(groups: [
      ..._prog.groups,
      ConditionGroup(
        id: _newGroupId(),
        name: '条件组 ${_prog.groups.length + 1}',
        logic: GroupLogic.and,
        conditions: const [],
      ),
    ]));
  }

  void _updateGroup(ConditionGroup g) {
    _setProg(_prog.copyWith(groups: _prog.groups.map((x) => x.id == g.id ? g : x).toList()));
  }

  void _removeGroup(String id) {
    _setProg(_prog.copyWith(groups: _prog.groups.where((g) => g.id != id).toList()));
  }

  void _addCondition(ConditionGroup g) {
    _editCondition(null, (c) {
      _updateGroup(g.copyWith(conditions: [...g.conditions, c]));
    });
  }

  void _updateCondition(ConditionGroup g, int ci, Condition c) {
    final cs = g.conditions.toList();
    cs[ci] = c;
    _updateGroup(g.copyWith(conditions: cs));
  }

  void _removeCondition(ConditionGroup g, int ci) {
    final cs = g.conditions.toList();
    cs.removeAt(ci);
    _updateGroup(g.copyWith(conditions: cs));
  }

  void _editCondition(Condition? existing, ValueChanged<Condition> onSave) {
    showDialog(
      context: context,
      builder: (_) => ScreenerConditionEditor(
        condition: existing,
        customIndicators: _prog.customIndicators,
        onSave: onSave,
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _computeFrom(String to, int windowSize) {
    try {
      final d = DateTime.parse(to);
      return d.subtract(Duration(days: windowSize * 2)).toIso8601String().substring(0, 10);
    } catch (_) {
      return '2025-06-01';
    }
  }

  List<Map<String, dynamic>> _parseRows(String json) {
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _settingsBar(),
          const SizedBox(height: 8),
          _actionBar(),
          const SizedBox(height: 10),
          Expanded(flex: 5, child: _groupsList()),
          const SizedBox(height: 10),
          Expanded(flex: 3, child: _bottomPanel()),
        ],
      ),
    );
  }

  // ── Settings bar: strategy name, timeframe, window, date ─────

  Widget _settingsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.brand),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _nameCtrl,
              decoration: _inputDec('策略名称'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              onChanged: (_) => _commitSettings(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: DropdownButtonFormField<Timeframe>(
              value: _prog.timeframe,
              decoration: _inputDec(null),
              isDense: true,
              style: const TextStyle(fontSize: 12),
              items: Timeframe.values.map((t) => DropdownMenuItem(value: t, child: Text(t.label, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) { if (v != null) _setProg(_prog.copyWith(timeframe: v)); },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _windowCtrl,
              decoration: _inputDec('K线根数'),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => _commitSettings(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _dateCtrl,
              decoration: _inputDec('目标日期'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: DropdownButtonFormField<int>(
              value: _prog.resultLimit,
              decoration: _inputDec(null),
              isDense: true,
              style: const TextStyle(fontSize: 12),
              items: const [20, 50, 100, 200, 500].map((n) => DropdownMenuItem(value: n, child: Text('$n条', style: TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) { if (v != null) _setProg(_prog.copyWith(resultLimit: v)); },
            ),
          ),
        ],
      ),
    );
  }

  // ── Action bar: buttons, mode, count ─────────────────────────

  Widget _actionBar() {
    return Row(
      children: [
        _btn('校验', _running ? null : _validate, false),
        const SizedBox(width: 6),
        _btn('运行', _running ? null : _run, true),
        const SizedBox(width: 6),
        _btn('保存策略', _running ? null : _saveStrategy, false),
        const SizedBox(width: 6),
        _btn('自定义指标', _running ? null : _manageIndicators, false),
        const SizedBox(width: 10),
        // Group mode toggle
        InkWell(
          onTap: () => _setProg(_prog.copyWith(
            groupLogic: _prog.groupLogic == GroupLogic.and ? GroupLogic.or : GroupLogic.and,
          )),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '组间关系：${_prog.groupLogic.label}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand),
            ),
          ),
        ),
        if (_running)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        const Spacer(),
        Icon(Icons.storage, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text('${_availableSymbols.length} 只股票', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  // ── Groups list ──────────────────────────────────────────────

  Widget _groupsList() {
    if (_prog.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            const Text('还没有筛选条件', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'MiSans')),
            const SizedBox(height: 4),
            const Text('点击下方按钮添加条件组，每组内可组合多个条件', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addGroup,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('创建条件组'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _prog.groups.length,
            itemBuilder: (_, i) => _groupCard(_prog.groups[i]),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: OutlinedButton.icon(
            onPressed: _addGroup,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('添加条件组'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _groupCard(ConditionGroup g) {
    final andOrLabel = g.logic == GroupLogic.and ? '全部满足(AND)' : '任一满足(OR)';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
            child: Row(
              children: [
                InkWell(
                  onTap: () => _updateGroup(g.copyWith(
                    logic: g.logic == GroupLogic.and ? GroupLogic.or : GroupLogic.and,
                  )),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF673AB7).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(andOrLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF673AB7))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(g.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                InkWell(
                  onTap: () => _removeGroup(g.id),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 16, color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
          // Conditions
          if (g.conditions.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text('暂无条件 — 点击下方按钮添加', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ...g.conditions.asMap().entries.map((e) => _conditionRow(g, e.key, e.value)),
          // Add condition button
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: InkWell(
              onTap: () => _addCondition(g),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text('+ 添加条件', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conditionRow(ConditionGroup g, int ci, Condition c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(
            child: Text(c.summary, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _editCondition(c, (updated) => _updateCondition(g, ci, updated)),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.edit, size: 14, color: AppColors.textMuted)),
          ),
          InkWell(
            onTap: () => _removeCondition(g, ci),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  // ── Bottom panel ─────────────────────────────────────────────

  Widget _bottomPanel() {
    if (_resultRows.isNotEmpty) {
      return ScreenerResultsTable(rows: _resultRows, isLoading: _running, error: _error);
    }
    if (_pipelineJson != null) {
      return _jsonViewer();
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 32, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text('添加条件后点击 [校验] 查看生成的 Pipeline JSON\n点击 [运行] 执行筛选', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }

  Widget _jsonViewer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Pipeline JSON', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              if (_error != null)
                Flexible(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.rise), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _formatJson(_pipelineJson!),
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textSecondary, height: 1.5),
              ),
            ),
          ),
          if (_registryJson != null && _registryJson != '{}') ...[
            const SizedBox(height: 6),
            const Divider(),
            const SizedBox(height: 4),
            const Text('Registry JSON', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            SizedBox(
              height: 80,
              child: SingleChildScrollView(
                child: SelectableText(
                  _formatJson(_registryJson!),
                  style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppColors.textMuted, height: 1.4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatJson(String json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
    } catch (_) {
      return json;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  Widget _btn(String label, VoidCallback? onTap, bool primary) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: primary ? AppColors.brand : null,
          border: primary ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primary ? Colors.white : AppColors.textSecondary, fontFamily: 'MiSans')),
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
