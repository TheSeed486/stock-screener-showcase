// Screener V2 ViewModel — ChangeNotifier managing all screener state.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../application/rust_runtime_bootstrap.dart';
import '../../src/rust/api/screener.dart' as rust;
import 'compiler/pipeline_compiler.dart';
import 'models/program_model.dart';
import 'models/stage_model.dart';
import 'models/indicator_model.dart';
import 'models/pattern_model.dart';
import 'storage/screener_v2_storage.dart';

class ScreenerViewModel extends ChangeNotifier {
  // ── Program state ──
  ScreenerV2Program _program = ScreenerV2Program.createDefault();
  ScreenerV2Program get program => _program;

  // ── Runtime state ──
  bool _running = false;
  bool get running => _running;

  String? _error;
  String? get error => _error;

  String? _pipelineJson;
  String? get pipelineJson => _pipelineJson;

  String? _registryJson;
  String? get registryJson => _registryJson;

  List<Map<String, dynamic>> _resultRows = const [];
  List<Map<String, dynamic>> get resultRows => _resultRows;

  int _elapsedMs = 0;
  int get elapsedMs => _elapsedMs;

  int _passedCount = 0;
  int get passedCount => _passedCount;

  int _totalCount = 0;
  int get totalCount => _totalCount;

  // ── Init data ──
  List<String> _availableSymbols = const [];
  List<String> get availableSymbols => _availableSymbols;

  String _defaultRegistryJson = '{}';
  String get defaultRegistryJson => _defaultRegistryJson;

  // ── Undo stack ──
  final List<ScreenerV2Program> _undoStack = [];
  final List<ScreenerV2Program> _redoStack = [];
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  // ── Selected stage ──
  int _selectedStageIndex = 0;
  int get selectedStageIndex => _selectedStageIndex;
  set selectedStageIndex(int i) {
    if (i != _selectedStageIndex && i >= 0 && i < _program.stages.length) {
      _selectedStageIndex = i;
      notifyListeners();
    }
  }

  // ── Initialization ──

  Future<void> loadInitData() async {
    try {
      await RustRuntimeBootstrap.instance.ensureInitialized();
      final results = await Future.wait([
        rust.listAvailableSymbolsRs(),
        rust.defaultRegistryJsonRs(),
      ]);
      _availableSymbols = results[0] as List<String>;
      _defaultRegistryJson = results[1] as String;
      notifyListeners();
    } catch (e) {
      _error = '初始化失败: $e';
      notifyListeners();
    }
  }

  Future<void> loadDraft() async {
    final d = await ScreenerV2Storage.loadDraft();
    if (d != null) {
      _program = d;
      _selectedStageIndex = d.stages.isNotEmpty ? 0 : -1;
      notifyListeners();
    }
  }

  // ── Program mutations (with undo) ──

  void _pushUndo() {
    _undoStack.add(_program);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _mutate(ScreenerV2Program Function(ScreenerV2Program) fn) {
    _pushUndo();
    _program = fn(_program);
    unawaited(ScreenerV2Storage.saveDraft(_program));
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_program);
    _program = _undoStack.removeLast();
    if (_selectedStageIndex >= _program.stages.length) {
      _selectedStageIndex = _program.stages.length - 1;
    }
    unawaited(ScreenerV2Storage.saveDraft(_program));
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_program);
    _program = _redoStack.removeLast();
    if (_selectedStageIndex >= _program.stages.length) {
      _selectedStageIndex = _program.stages.length - 1;
    }
    unawaited(ScreenerV2Storage.saveDraft(_program));
    notifyListeners();
  }

  // ── Program-level mutations ──

  void updateName(String name) {
    _mutate((p) => p.copyWith(name: name));
  }

  void updateUniverse(String universe) {
    _mutate((p) => p.copyWith(universe: universe));
  }

  void updateIndicators(List<CustomIndicator> indicators) {
    _mutate((p) => p.copyWith(customIndicators: indicators));
  }

  // ── Stage CRUD ──

  void addStage() {
    _mutate((p) => p.copyWith(stages: [
      ...p.stages,
      StageModel.createDefault(name: '阶段 ${p.stages.length + 1}'),
    ]));
    _selectedStageIndex = _program.stages.length - 1;
  }

  void removeStage(int index) {
    if (index < 0 || index >= _program.stages.length) return;
    _mutate((p) {
      final stages = p.stages.toList()..removeAt(index);
      return p.copyWith(stages: stages);
    });
    if (_selectedStageIndex >= _program.stages.length) {
      _selectedStageIndex = _program.stages.length - 1;
    }
  }

  void updateStage(int index, StageModel stage) {
    if (index < 0 || index >= _program.stages.length) return;
    _mutate((p) {
      final stages = p.stages.toList();
      stages[index] = stage;
      return p.copyWith(stages: stages);
    });
  }

  // ── Stage-level mutations (operate on selected stage) ──

  StageModel? get _currentStage =>
      _selectedStageIndex >= 0 && _selectedStageIndex < _program.stages.length
          ? _program.stages[_selectedStageIndex]
          : null;

  void _mutateStage(StageModel Function(StageModel) fn) {
    final stage = _currentStage;
    if (stage == null) return;
    updateStage(_selectedStageIndex, fn(stage));
  }

  // Conditions
  void addCondition(ConditionModel c) {
    _mutateStage((s) => s.copyWith(conditions: [...s.conditions, c]));
  }

  void updateCondition(int index, ConditionModel c) {
    _mutateStage((s) {
      final cs = s.conditions.toList();
      cs[index] = c;
      return s.copyWith(conditions: cs);
    });
  }

  void removeCondition(int index) {
    _mutateStage((s) {
      final cs = s.conditions.toList()..removeAt(index);
      return s.copyWith(conditions: cs);
    });
  }

  // Indicator calls
  void addIndicatorCall(IndicatorCallModel ic) {
    _mutateStage((s) => s.copyWith(prepare: [...s.prepare, ic]));
  }

  void updateIndicatorCall(int index, IndicatorCallModel ic) {
    _mutateStage((s) {
      final ps = s.prepare.toList();
      ps[index] = ic;
      return s.copyWith(prepare: ps);
    });
  }

  void removeIndicatorCall(int index) {
    _mutateStage((s) {
      final ps = s.prepare.toList()..removeAt(index);
      return s.copyWith(prepare: ps);
    });
  }

  // Points
  void addPoint(NamedPointModel p) {
    _mutateStage((s) => s.copyWith(points: [...s.points, p]));
  }

  void updatePoint(int index, NamedPointModel p) {
    _mutateStage((s) {
      final ps = s.points.toList();
      ps[index] = p;
      return s.copyWith(points: ps);
    });
  }

  void removePoint(int index) {
    _mutateStage((s) {
      final ps = s.points.toList()..removeAt(index);
      return s.copyWith(points: ps);
    });
  }

  // Vars
  void addVar(VarDefModel v) {
    _mutateStage((s) => s.copyWith(vars: [...s.vars, v]));
  }

  void updateVar(int index, VarDefModel v) {
    _mutateStage((s) {
      final vs = s.vars.toList();
      vs[index] = v;
      return s.copyWith(vars: vs);
    });
  }

  void removeVar(int index) {
    _mutateStage((s) {
      final vs = s.vars.toList()..removeAt(index);
      return s.copyWith(vars: vs);
    });
  }

  // Marks
  void addMark(MarkModel m) {
    _mutateStage((s) => s.copyWith(marks: [...s.marks, m]));
  }

  void updateMark(int index, MarkModel m) {
    _mutateStage((s) {
      final ms = s.marks.toList();
      ms[index] = m;
      return s.copyWith(marks: ms);
    });
  }

  void removeMark(int index) {
    _mutateStage((s) {
      final ms = s.marks.toList()..removeAt(index);
      return s.copyWith(marks: ms);
    });
  }

  // Stage config
  void updateStageTimeframe(dynamic tf) {
    _mutateStage((s) => s.copyWith(timeframe: tf));
  }

  void updateStageWindowSize(WindowSizeModel? ws) {
    _mutateStage((s) => s.copyWith(
      windowSize: ws,
      clearWindowSize: ws == null,
    ));
  }

  void updateStageName(String name) {
    _mutateStage((s) => s.copyWith(name: name));
  }

  // ── Validate / Run ──

  Future<bool> validate() async {
    _running = true;
    _error = null;
    _resultRows = const [];
    notifyListeners();

    try {
      await RustRuntimeBootstrap.instance.ensureInitialized();
      final result = compileScreenerV2(_program, defaultRegistryJson: _defaultRegistryJson);
      _pipelineJson = result.pipelineJson;
      _registryJson = result.registryJson;

      final ok = await rust.validatePipelineRs(pipelineJson: result.pipelineJson);
      if (!ok) _error = 'Pipeline JSON 格式错误';
      notifyListeners();
      return ok;
    } catch (e) {
      _error = '校验失败: $e';
      notifyListeners();
      return false;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> run() async {
    _running = true;
    _error = null;
    _resultRows = const [];
    notifyListeners();

    try {
      await RustRuntimeBootstrap.instance.ensureInitialized();
      final result = compileScreenerV2(_program, defaultRegistryJson: _defaultRegistryJson);
      _pipelineJson = result.pipelineJson;
      _registryJson = result.registryJson;

      if (_availableSymbols.isEmpty) {
        _error = '没有可用的股票数据，请先确保数据已下载';
        notifyListeners();
        return;
      }

      // Use all available symbols (no cap)
      final symbols = _availableSymbols;
      final stage = _currentStage;
      final windowSize = stage?.windowSize;
      final windowN = windowSize is ExactWindowSize ? windowSize.n : 60;
      final to = DateTime.now().toIso8601String().substring(0, 10);
      final from = DateTime.now().subtract(Duration(days: windowN * 2)).toIso8601String().substring(0, 10);

      final resultJson = await rust.runScreenerRs(
        pipelineJson: result.pipelineJson,
        registryJson: result.registryJson,
        symbols: symbols,
        fromDate: from,
        toDate: to,
      );

      _parseResult(resultJson);
      notifyListeners();
    } catch (e) {
      _error = '运行失败: $e';
      notifyListeners();
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  void _parseResult(String json) {
    try {
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      _elapsedMs = parsed['elapsed_ms'] as int? ?? 0;
      _passedCount = parsed['passed'] as int? ?? 0;
      _totalCount = parsed['total'] as int? ?? 0;
      _resultRows = (parsed['rows'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      _resultRows = const [];
      _elapsedMs = 0;
      _passedCount = 0;
      _totalCount = 0;
    }
  }

  // ── Save strategy ──

  Future<void> saveStrategy() async {
    await ScreenerV2Storage.saveStrategy(_program.name, _program);
  }

  Future<void> loadStrategy(String name) async {
    final s = await ScreenerV2Storage.loadStrategy(name);
    if (s != null) {
      _pushUndo();
      _program = s;
      _selectedStageIndex = s.stages.isNotEmpty ? 0 : -1;
      notifyListeners();
    }
  }

  Future<List<String>> listStrategies() => ScreenerV2Storage.listStrategies();
}
