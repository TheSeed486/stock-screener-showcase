// Screener V2 persistence — draft + strategy storage via shared_preferences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/program_model.dart';

class ScreenerV2Storage {
  static const _draftKey = 'screener_v2_draft';
  static const _strategiesKey = 'screener_v2_strategies';

  // ── Draft ─────────────────────────────────────────────────

  static Future<void> saveDraft(ScreenerV2Program program) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(program.toJson()));
  }

  static Future<ScreenerV2Program?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_draftKey);
    if (json == null) return null;
    try {
      return ScreenerV2Program.fromJson(
        Map<String, dynamic>.from(jsonDecode(json) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Named strategies ──────────────────────────────────────

  static Future<void> saveStrategy(String name, ScreenerV2Program program) async {
    final prefs = await SharedPreferences.getInstance();
    final strategies = _loadStrategiesMap(prefs);
    strategies[name] = program.toJson();
    await prefs.setString(_strategiesKey, jsonEncode(strategies));
  }

  static Future<ScreenerV2Program?> loadStrategy(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final strategies = _loadStrategiesMap(prefs);
    final json = strategies[name];
    if (json == null) return null;
    try {
      return ScreenerV2Program.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> listStrategies() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadStrategiesMap(prefs).keys.toList();
  }

  static Future<void> deleteStrategy(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final strategies = _loadStrategiesMap(prefs);
    strategies.remove(name);
    await prefs.setString(_strategiesKey, jsonEncode(strategies));
  }

  static Map<String, dynamic> _loadStrategiesMap(SharedPreferences prefs) {
    final json = prefs.getString(_strategiesKey);
    if (json == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return {};
    }
  }
}
