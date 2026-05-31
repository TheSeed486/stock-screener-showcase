// Registry compiler — merges default registry with custom indicators.

import 'dart:convert';

import '../models/indicator_model.dart';

/// Merge the default ModuleRegistry JSON with custom indicators.
String mergeRegistry(String defaultJson, List<CustomIndicator> customIndicators) {
  Map<String, dynamic> reg;
  try {
    reg = Map<String, dynamic>.from(jsonDecode(defaultJson) as Map);
  } catch (_) {
    reg = {'indicators': <String, dynamic>{}, 'intraday': <String, dynamic>{}};
  }

  final indicators = Map<String, dynamic>.from(reg['indicators'] as Map? ?? {});
  for (final ci in customIndicators) {
    indicators[ci.id] = ci.toModDefJson();
  }
  reg['indicators'] = indicators;

  if (!reg.containsKey('intraday')) {
    reg['intraday'] = <String, dynamic>{};
  }

  return jsonEncode(reg);
}
