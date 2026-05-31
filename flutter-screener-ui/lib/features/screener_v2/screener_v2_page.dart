// Screener V2 — Pipeline JSON editor + indicator definition + Rust execution.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../theme/app_colors.dart';
import '../../application/rust_runtime_bootstrap.dart';
import '../../src/rust/api/screener.dart' as rust;
import '../../data/watchlist_repository.dart';
import 'widgets/custom_indicator_editor.dart';
import 'models/indicator_model.dart';

class ScreenerV2Page extends StatefulWidget {
  const ScreenerV2Page({super.key, required this.isActive});
  final bool isActive;

  @override
  State<ScreenerV2Page> createState() => _ScreenerV2PageState();
}

class _ScreenerV2PageState extends State<ScreenerV2Page> {
  final _pipelineCtrl = TextEditingController();
  final _registryCtrl = TextEditingController();
  bool _running = false;
  String? _resultJson;
  List<CustomIndicator> _customIndicators = [];
  List<String> _availableSymbols = [];
  Map<String, String> _watchlistGroups = {}; // groupId -> groupName
  Map<String, List<String>> _wlGroupSymbols = {}; // groupId -> symbols
  String _defaultRegistry = '{}';
  bool _selSh = true, _selSz = true, _selBj = true;
  bool _selStar = true, _selGem = true;
  String? _selWlGroup; // null = none, groupId = specific group
  // Scan mode
  bool _scanMode = false;
  final _scanFromCtrl = TextEditingController();
  final _scanToCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pipelineCtrl.text = _defaultPipelineJson;
    _pipelineCtrl.addListener(_onPipelineChanged);
    _registryCtrl.addListener(_onPipelineChanged);
    _loadInit();
  }

  void _onPipelineChanged() {
    if (_resultJson != null) {
      setState(() => _resultJson = null);
    }
  }

  Future<void> _loadInit() async {
    await RustRuntimeBootstrap.instance.ensureInitialized();
    final symbols = await rust.listAvailableSymbolsRs();
    final reg = await rust.defaultRegistryJsonRs();
    await _loadWatchlistSymbols();
    setState(() {
      _availableSymbols = symbols;
      _defaultRegistry = reg;
    });
  }

  Future<void> _loadWatchlistSymbols() async {
    try {
      final groups = await const RustWatchlistRepository().loadState();
      final groupMap = <String, String>{};
      final groupSyms = <String, List<String>>{};
      for (final g in groups) {
        groupMap[g.id] = g.name;
        final syms = <String>[];
        for (final e in g.entries) {
          final prefix = switch (e.market) { 0 => 'SZ', 1 => 'SH', 2 => 'BJ', _ => '' };
          if (prefix.isNotEmpty) {
            syms.add('$prefix.${e.code.padLeft(6, "0")}');
          }
        }
        if (syms.isNotEmpty) groupSyms[g.id] = syms;
      }
      _watchlistGroups = groupMap;
      _wlGroupSymbols = groupSyms;
    } catch (_) {
      _watchlistGroups = {};
      _wlGroupSymbols = {};
    }
  }

  List<String> _filteredSymbols() {
    if (_selWlGroup != null) {
      return _wlGroupSymbols[_selWlGroup!] ?? [];
    }
    var list = _availableSymbols;
    if (!_selSh || !_selSz || !_selBj) {
      list = list.where((s) {
        if (s.startsWith('SH.') && !_selSh) return false;
        if (s.startsWith('SZ.') && !_selSz) return false;
        if (s.startsWith('BJ.') && !_selBj) return false;
        return true;
      }).toList();
    }
    if (!_selStar) list = list.where((s) => !RegExp(r'^SH\.(688|689)').hasMatch(s)).toList();
    if (!_selGem) list = list.where((s) => !RegExp(r'^SZ\.(300|301)').hasMatch(s)).toList();
    return list;
  }

  @override
  void dispose() {
    _pipelineCtrl.dispose();
    _registryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _toolbar(),
          const SizedBox(height: 8),
          Expanded(child: _editorArea()),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.code, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          const Text('Pipeline 编辑器', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(width: 16),
          _btn('格式化', _formatJson),
          const SizedBox(width: 6),
          _btn('校验', _running ? null : _validate),
          const SizedBox(width: 6),
          _btn('运行', _running ? null : _run, primary: true),
          const SizedBox(width: 6),
          _btn(_scanMode ? '单次' : '扫描', () => setState(() { _scanMode = !_scanMode; })),
          if (_scanMode) ...[
            const SizedBox(width: 6),
            SizedBox(width: 110, child: TextField(controller: _scanFromCtrl, decoration: const InputDecoration(labelText: '从', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal:6,vertical:4)), style: const TextStyle(fontSize:12))),
            const SizedBox(width: 6),
            SizedBox(width: 110, child: TextField(controller: _scanToCtrl, decoration: const InputDecoration(labelText: '到', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal:6,vertical:4)), style: const TextStyle(fontSize:12))),
          ],
          if (_running) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          if (_resultJson != null && !_running) ...[
            const SizedBox(width: 6),
            _btn('查看结果', _showResults, primary: true),
            const SizedBox(width: 6),
            _btn('导出', _exportCsv),
          ],
          const Spacer(),
          _marketChip('沪', _selSh, (v) => setState(() { _selSh = v; _selWlGroup = null; })),
          _marketChip('深', _selSz, (v) => setState(() { _selSz = v; _selWlGroup = null; })),
          _marketChip('京', _selBj, (v) => setState(() { _selBj = v; _selWlGroup = null; })),
          const SizedBox(width: 4),
          _marketChip('科创', _selStar, (v) => setState(() { _selStar = v; _selWlGroup = null; })),
          _marketChip('创业', _selGem, (v) => setState(() { _selGem = v; _selWlGroup = null; })),
          if (_watchlistGroups.isNotEmpty) ...[
            const SizedBox(width: 4),
            _wlGroupDropdown(),
          ],
          const SizedBox(width: 8),
          _btn('管理指标', _showIndicatorManager),
          const SizedBox(width: 8),
          Text('${_filteredSymbols().length} 只', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onTap, {bool primary = false}) {
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
        child: Text(label, style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: onTap == null
              ? AppColors.textMuted
              : primary ? Colors.white : AppColors.textSecondary,
          fontFamily: 'MiSans',
        )),
      ),
    );
  }

  Widget _marketChip(String label, bool on, ValueChanged<bool> toggle) {
    return InkWell(
      onTap: () => toggle(!on),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.brand.withValues(alpha: 0.12) : AppColors.surfaceMuted,
          border: Border.all(color: on ? AppColors.brand : AppColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: Text(label, style: TextStyle(
          fontSize: 11, fontFamily: 'MiSans',
          fontWeight: FontWeight.w600,
          color: on ? AppColors.brand : AppColors.textSecondary,
        ))),
      ),
    );
  }

  Widget _wlGroupDropdown() {
    final items = <String, String>{'': '市场筛选', ..._watchlistGroups};
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: _selWlGroup != null ? AppColors.brand : AppColors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selWlGroup ?? '',
          isDense: true,
          style: TextStyle(fontSize: 11,
            color: _selWlGroup != null ? AppColors.brand : AppColors.textSecondary,
            fontFamily: 'MiSans'),
          items: items.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, style: const TextStyle(fontSize: 11, fontFamily: 'MiSans')),
          )).toList(),
          onChanged: (v) => setState(() => _selWlGroup = (v == null || v.isEmpty) ? null : v),
        ),
      ),
    );
  }

  Widget _editorArea() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _codeEditor('Pipeline JSON', _pipelineCtrl),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _codeEditor('Registry JSON (可选)', _registryCtrl),
        ),
      ],
    );
  }

  Widget _codeEditor(String title, TextEditingController ctrl) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFFCDD6F4), height: 1.5),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                hintText: '粘贴 JSON...',
                hintStyle: TextStyle(color: Color(0xFF585B70)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 结果展示：全屏弹窗 + 虚拟滚动表格 ────────────────────

  void _showResults() {
    if (_resultJson == null) return;
    List<Map<String, dynamic>> rows;
    int elapsedMs = 0, passed = 0, total = 0;
    try {
      final parsed = jsonDecode(_resultJson!) as Map<String, dynamic>;
      if (parsed.containsKey('dates')) {
        rows = [];
        final results = parsed['results'] as Map<String, dynamic>;
        for (final date in (parsed['dates'] as List)) {
          final day = results[date] as Map<String, dynamic>;
          passed += day['passed'] as int? ?? 0;
          total += day['total'] as int? ?? 0;
          for (final row in (day['rows'] as List)) {
            final r = Map<String, dynamic>.from(row as Map);
            // Only show passed stocks for scan results
            final ok = r['passed'] ?? r['通过'];
            if (ok != true) continue;
            r['日期'] = date;
            rows.add(r);
          }
        }
      } else {
        elapsedMs = parsed['elapsed_ms'] as int? ?? 0;
        passed = parsed['passed'] as int? ?? 0;
        total = parsed['total'] as int? ?? 0;
        rows = (parsed['rows'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) { return; }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ScreenerResultsPage(rows: rows, elapsedMs: elapsedMs, passed: passed, total: total)));
  }

  void _exportCsv() {
    if (_resultJson == null) return;
    try {
      final parsed = jsonDecode(_resultJson!) as Map<String, dynamic>;
      final rows = (parsed['rows'] as List).cast<Map<String, dynamic>>();
      final name = 'screener_result_${DateTime.now().toIso8601String().substring(0,10)}';
      _writeCsvFile('$name.csv', rows);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出: $name.csv (${rows.length} 行)')));
    } catch (_) {}
  }

  void _writeCsvFile(String path, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    final keys = <String>[];
    final seen = <String>{};
    for (final r in rows) { for (final k in r.keys) { if (seen.add(k)) keys.add(k); } }
    final buf = StringBuffer();
    buf.writeln(keys.join(','));
    for (final r in rows) { buf.writeln(keys.map((k) { final s = r[k]?.toString() ?? ''; return s.contains(',') ? '"$s"' : s; }).join(',')); }
    File(path).writeAsStringSync(buf.toString());
  }

  // ── Actions ─────────────────────────────────────────────

  void _formatJson() {
    _formatCtrl(_pipelineCtrl);
    _formatCtrl(_registryCtrl);
  }

  void _formatCtrl(TextEditingController ctrl) {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      final obj = jsonDecode(text);
      ctrl.text = const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {}
  }

  Future<void> _validate() async {
    setState(() { _running = true; _resultJson = null; });
    try {
      final pipelineJson = _pipelineCtrl.text.trim();
      jsonDecode(pipelineJson);
      final ok = await rust.validatePipelineRs(pipelineJson: pipelineJson);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('校验通过'), duration: Duration(seconds: 2)),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pipeline 格式校验失败'), duration: Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      setState(() => _running = false);
    }
  }

  Future<void> _run() async {
    setState(() { _running = true; _resultJson = null; });
    try {
      final pipelineJson = _pipelineCtrl.text.trim();
      jsonDecode(pipelineJson);
      final registryJson = _buildRegistryJson();
      if (_availableSymbols.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可用的股票数据'), duration: Duration(seconds: 3)));
        return;
      }

      if (_scanMode) {
        final from = _scanFromCtrl.text.trim().isNotEmpty ? _scanFromCtrl.text.trim() : DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
        final to = _scanToCtrl.text.trim().isNotEmpty ? _scanToCtrl.text.trim() : DateTime.now().toIso8601String().substring(0, 10);
        String stageName = 'scan';
        try { final pj = jsonDecode(pipelineJson) as Map<String, dynamic>; stageName = (pj['stages'] as List?)?.first?['name'] as String? ?? 'scan'; } catch (_) {}
        final scanDirName = '${stageName}_${from}_${to}'.replaceAll(RegExp(r'[/\\?%*:|\"<>]'), '_');
        final fullPath = '${Directory.current.path}/$scanDirName';
        _resultJson = await rust.runScreenerScanRs(pipelineJson: pipelineJson, registryJson: registryJson, symbols: _filteredSymbols(), fromDate: from, toDate: to, outputDir: fullPath);
      } else {
        String toDate;
        try {
          final pj = jsonDecode(pipelineJson) as Map<String, dynamic>;
          final stages = pj['stages'] as List?;
          final sd = stages?.isNotEmpty == true ? (stages!.first as Map)['start_date'] : null;
          toDate = sd?.toString() ?? DateTime.now().toIso8601String().substring(0, 10);
        } catch (_) { toDate = DateTime.now().toIso8601String().substring(0, 10); }
        final to = toDate;
        final from = DateTime.parse(to).subtract(const Duration(days: 120)).toIso8601String().substring(0, 10);
        _resultJson = await rust.runScreenerRs(pipelineJson: pipelineJson, registryJson: registryJson, symbols: _filteredSymbols(), fromDate: from, toDate: to);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      setState(() => _running = false);
      if (_resultJson != null && mounted) {
        _showResults();
      }
    }
  }

  String _buildRegistryJson() {
    // Start with default registry
    Map<String, dynamic> reg;
    try {
      reg = Map<String, dynamic>.from(jsonDecode(_defaultRegistry) as Map);
    } catch (_) {
      reg = {'indicators': <String, dynamic>{}, 'intraday': <String, dynamic>{}};
    }

    // Merge user registry overrides
    final userRegText = _registryCtrl.text.trim();
    if (userRegText.isNotEmpty) {
      try {
        final userReg = Map<String, dynamic>.from(jsonDecode(userRegText) as Map);
        final indicators = Map<String, dynamic>.from(reg['indicators'] as Map? ?? {});
        final userIndicators = Map<String, dynamic>.from(userReg['indicators'] as Map? ?? {});
        indicators.addAll(userIndicators);
        reg['indicators'] = indicators;
        if (userReg.containsKey('intraday')) {
          final intraday = Map<String, dynamic>.from(reg['intraday'] as Map? ?? {});
          intraday.addAll(Map<String, dynamic>.from(userReg['intraday'] as Map));
          reg['intraday'] = intraday;
        }
      } catch (_) {}
    }

    // Merge custom indicators from UI
    for (final ci in _customIndicators) {
      final indicators = Map<String, dynamic>.from(reg['indicators'] as Map? ?? {});
      indicators[ci.id] = ci.toModDefJson();
      reg['indicators'] = indicators;
    }

    return jsonEncode(reg);
  }

  Future<void> _showIndicatorManager() async {
    final result = await showDialog<List<CustomIndicator>>(
      context: context,
      builder: (ctx) => _IndicatorManagerDialog(indicators: _customIndicators),
    );
    if (result != null) {
      setState(() => _customIndicators = result);
    }
  }

  // ── Default pipeline example ────────────────────────────

  static const _defaultPipelineJson = '''
{
  "stages": [
    {
      "name": "趋势筛选",
      "timeframe": "Daily",
      "start_date": null,
      "windowsize": {"Exact": 60},
      "prepare": {
        "indicators": [
          {
            "module_id": "sma",
            "params": {"period": {"type": "Int", "value": 20}}
          }
        ]
      },
      "kline_pattern": null,
      "vars": [],
      "points": [],
      "conditions": [
        [
          "收盘价 > SMA20",
          {
            "t": "Gt",
            "v": [
              {"t": "Path", "v": {"stock": {"t": "Current"}, "anchor": {"t": "WindowEnd"}, "offset": 0, "field": "close"}},
              {"t": "Path", "v": {"stock": {"t": "Current"}, "anchor": {"t": "WindowEnd"}, "offset": 0, "field": "sma_20"}}
            ]
          }
        ]
      ],
      "marks": [],
      "extra_stocks": []
    }
  ]
}''';
}

// ── 结果全屏页（可排序 data_table_2）──────────────────────

class _ScreenerResultsPage extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final int elapsedMs;
  final int passed;
  final int total;
  const _ScreenerResultsPage({
    required this.rows,
    required this.elapsedMs,
    required this.passed,
    required this.total,
  });

  @override
  State<_ScreenerResultsPage> createState() => _ScreenerResultsPageState();
}

class _ScreenerResultsPageState extends State<_ScreenerResultsPage> {
  int? _sortIdx;
  bool _sortAsc = true;

  String _fmtMs(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${(ms ~/ 60000)}m${((ms % 60000) / 1000).toStringAsFixed(0)}s';
  }

  static const _keyMap = <String, String>{
    'market': '市场', '市场': '市场',
    'code': '代码', '代码': '代码',
    'name': '名称', '名称': '名称',
    'date': '日期', '日期': '日期',
    'open': '开盘', '开盘': '开盘',
    'high': '最高', '最高': '最高',
    'low': '最低', '最低': '最低',
    'close': '收盘', '收盘': '收盘',
    'volume': '成交量', '成交量': '成交量',
    'amount': '成交额', '成交额': '成交额',
    'passed': '通过', '通过': '通过',
    'eliminated_reason': '淘汰原因', '淘汰原因': '淘汰原因',
    '_patt': '形态匹配', '形态匹配': '形态匹配',
  };
  static const _numCols = {'收盘', '开盘', '最高', '最低', '成交量', '成交额'};

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceMuted,
          title: Text('筛选结果: 0 条 | 耗时 ${_fmtMs(widget.elapsedMs)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'MiSans')),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('关闭'),
            ),
          ],
        ),
        body: const Center(
          child: Text('没有匹配的股票', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }

    final keys = _displayKeys();
    if (keys.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceMuted,
          title: Text('筛选结果: ${widget.rows.length} 条 | 通过: ${widget.passed}/${widget.total} | 耗时 ${_fmtMs(widget.elapsedMs)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'MiSans')),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('关闭'),
            ),
          ],
        ),
        body: const Center(
          child: Text('结果格式异常', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }

    final displayKeys = _displayKeys();
    final sortedRows = _sortedRows(displayKeys);
    final columns = displayKeys.map((k) => DataColumn(
      label: Text(k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'MiSans')),
      numeric: _numCols.contains(k),
      onSort: (ci, asc) => setState(() { _sortIdx = ci; _sortAsc = asc; }),
    )).toList();

    final dataRows = <DataRow>[];
    for (int i = 0; i < sortedRows.length; i++) {
      final row = sortedRows[i];
      final passed = row['passed'] ?? row['通过'];
      dataRows.add(DataRow(
        color: WidgetStateProperty.resolveWith((_) {
          if (passed == true) return AppColors.rise.withValues(alpha: 0.05);
          if (passed == false) return AppColors.fall.withValues(alpha: 0.03);
          return i.isOdd ? AppColors.surfaceMuted.withValues(alpha: 0.4) : null;
        }),
        cells: displayKeys.map((k) => DataCell(
          Text(_fmt(k, row), overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontFamily: 'MiSans',
              color: passed == false ? AppColors.textMuted : AppColors.textPrimary)),
        )).toList(),
      ));
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceMuted,
        title: Text('筛选结果: ${sortedRows.length} 条',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'MiSans')),
        actions: [TextButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 16), label: const Text('关闭'))],
      ),
      body: PaginatedDataTable2(
        columnSpacing: 8,
        horizontalMargin: 10,
        minWidth: keys.length * 90.0,
        dataRowHeight: 30,
        headingRowHeight: 36,
        rowsPerPage: 100,
        showFirstLastButtons: true,
        sortColumnIndex: _sortIdx,
        sortAscending: _sortAsc,
        columns: columns,
        source: _RowSource(dataRows),
      ),
    );
  }

  List<String> _displayKeys() {
    final raw = <String>{};
    for (final row in widget.rows) { raw.addAll(row.keys); }
    final cn = raw.map((k) => _keyMap[k] ?? k).toSet();
    cn.remove('市场');
    cn.removeWhere((k) => k.startsWith('_c_'));
    const priority = ['代码', '名称', '日期', '通过', '淘汰原因',
      '收盘', '开盘', '最高', '最低', '成交量', '成交额'];
    return [
      for (final p in priority) if (cn.remove(p)) p,
      ...(cn.toList()..sort()),
    ];
  }

  List<Map<String, dynamic>> _sortedRows(List<String> keys) {
    if (_sortIdx == null || _sortIdx! >= keys.length) return widget.rows;
    final col = keys[_sortIdx!];
    final sorted = List<Map<String, dynamic>>.of(widget.rows);
    sorted.sort((a, b) {
      final va = a[col];
      final vb = b[col];
      if (va == null && vb == null) return 0;
      if (va == null) return _sortAsc ? -1 : 1;
      if (vb == null) return _sortAsc ? 1 : -1;
      int cmp;
      if (va is num && vb is num) {
        cmp = va.compareTo(vb);
      } else if (va is bool && vb is bool) {
        cmp = (va ? 1 : 0).compareTo(vb ? 1 : 0);
      } else {
        cmp = va.toString().compareTo(vb.toString());
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  String _fmt(String displayKey, Map<String, dynamic> row) {
    dynamic v = row[displayKey];
    if (v == null) {
      final enKey = _keyMap.entries
          .firstWhere((e) => e.value == displayKey, orElse: () => const MapEntry('', '')).key;
      if (enKey.isNotEmpty) v = row[enKey];
    }
    if (v == null) return '-';

    switch (displayKey) {
      case '代码':
        if (v is num) {
          final mkt = row['market'] ?? row['市场'];
          final prefix = mkt is num
              ? switch (mkt.toInt()) { 0 => 'SZ', 1 => 'SH', 2 => 'BJ', _ => '' }
              : '';
          return '$prefix${v.toInt().toString().padLeft(6, "0")}';
        }
      case '通过':
        if (v is bool) return v ? '✓' : '✗';
    }

    if (v is bool) return '$v';
    if (v is double) {
      if (v.abs() >= 1e8) return '${(v / 1e8).toStringAsFixed(2)}亿';
      if (v.abs() >= 1e4) return '${(v / 1e4).toStringAsFixed(2)}万';
      return v.toStringAsFixed(v.abs() < 10 ? 3 : 2);
    }
    return v.toString();
  }
}

// ── Paginated data source ───────────────────────────────────

class _RowSource extends DataTableSource {
  final List<DataRow> _rows;
  _RowSource(this._rows);

  @override DataRow? getRow(int i) => i < _rows.length ? _rows[i] : null;
  @override bool get isRowCountApproximate => false;
  @override int get rowCount => _rows.length;
  @override int get selectedRowCount => 0;
}

// ── Indicator manager dialog ──────────────────────────────

class _IndicatorManagerDialog extends StatefulWidget {
  final List<CustomIndicator> indicators;
  const _IndicatorManagerDialog({required this.indicators});

  @override
  State<_IndicatorManagerDialog> createState() => _IndicatorManagerDialogState();
}

class _IndicatorManagerDialogState extends State<_IndicatorManagerDialog> {
  late List<CustomIndicator> _list;

  @override
  void initState() {
    super.initState();
    _list = widget.indicators.toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理自定义指标', style: TextStyle(fontFamily: 'MiSans')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._list.asMap().entries.map((e) => ListTile(
              title: Text('${e.value.label} (${e.value.id})', style: const TextStyle(fontSize: 13)),
              subtitle: Text('参数: ${e.value.paramNames.join(", ")} | 输出: ${e.value.outputs.length}列',
                style: const TextStyle(fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _edit(e.key, e.value),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    onPressed: () => setState(() => _list.removeAt(e.key)),
                  ),
                ],
              ),
            )),
            if (_list.isEmpty) const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无自定义指标', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _add(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加指标'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _list),
          child: const Text('确认'),
        ),
      ],
    );
  }

  Future<void> _add() async {
    final result = await showDialog<CustomIndicator>(
      context: context,
      builder: (ctx) => const CustomIndicatorEditorDialog(),
    );
    if (result != null) setState(() => _list.add(result));
  }

  Future<void> _edit(int index, CustomIndicator existing) async {
    final result = await showDialog<CustomIndicator>(
      context: context,
      builder: (ctx) => CustomIndicatorEditorDialog(existing: existing),
    );
    if (result != null) setState(() => _list[index] = result);
  }
}
