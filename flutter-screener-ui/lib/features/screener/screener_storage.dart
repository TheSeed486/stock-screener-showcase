import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'screener_models.dart';

class ScreenerStorage {
  ScreenerStorage._();

  static const _draftKey = 'screener_v2_draft';
  static const _stratIdxKey = 'screener_v2_strategies';
  static const _maxStrategies = 50;

  // ── Draft ────────────────────────────────────────────────────

  static Future<void> saveDraft(ScreenerProgram program) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(program.toJson()));
  }

  static Future<ScreenerProgram?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return ScreenerProgram.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  // ── Strategies ───────────────────────────────────────────────

  static Future<List<SavedStrategyMeta>> listStrategies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stratIdxKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SavedStrategyMeta.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<ScreenerProgram?> loadStrategy(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stratKey(id));
    if (raw == null || raw.isEmpty) return null;
    try {
      return ScreenerProgram.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveStrategy(String name, ScreenerProgram program) async {
    final prefs = await SharedPreferences.getInstance();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final saved = program.copyWith(name: name);

    await prefs.setString(_stratKey(id), jsonEncode(saved.toJson()));

    final list = await listStrategies();
    list.insert(0, SavedStrategyMeta(id: id, name: name, savedAt: DateTime.now()));
    final trimmed = list.length > _maxStrategies ? list.sublist(0, _maxStrategies) : list;
    await prefs.setString(
      _stratIdxKey,
      jsonEncode(trimmed.map((m) => m.toJson()).toList()),
    );
  }

  static Future<void> deleteStrategy(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stratKey(id));
    final list = await listStrategies();
    list.removeWhere((m) => m.id == id);
    await prefs.setString(
      _stratIdxKey,
      jsonEncode(list.map((m) => m.toJson()).toList()),
    );
  }

  static String _stratKey(String id) => 'screener_v2_strat_$id';
}

class SavedStrategyMeta {
  final String id;
  final String name;
  final DateTime savedAt;

  const SavedStrategyMeta({required this.id, required this.name, required this.savedAt});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedStrategyMeta.fromJson(Map<String, dynamic> json) => SavedStrategyMeta(
    id: json['id'] as String,
    name: json['name'] as String,
    savedAt: DateTime.parse(json['savedAt'] as String),
  );
}
