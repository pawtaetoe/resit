import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// "CSC 2101" and "csc2101" are the same module.
String moduleKey(String code) => code.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Gives each module code in [codes] that has no colour yet the least-used
/// colour (lowest number on a tie), in code order, so modules seen together
/// get different colours while there are colours to go round. Colours
/// already given are never changed. Returns the updated map (code → colour).
Map<String, int> assignModuleColours(Map<String, int> existing, Iterable<String> codes, int paletteSize) {
  final result = Map<String, int>.of(existing);
  final fresh = {for (final c in codes) moduleKey(c)}.where((k) => !result.containsKey(k)).toList()..sort();
  for (final key in fresh) {
    final uses = List<int>.filled(paletteSize, 0);
    for (final i in result.values) {
      if (i >= 0 && i < paletteSize) uses[i]++;
    }
    var best = 0;
    for (var i = 1; i < paletteSize; i++) {
      if (uses[i] < uses[best]) best = i;
    }
    result[key] = best;
  }
  return result;
}

/// The module → colour choices, kept on the device so a module keeps its
/// colour from week to week and between launches.
class ModuleColourStore {
  static const _key = 'module_colours';

  Future<Map<String, int>> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, int> colours) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(colours));
    } catch (_) {
      // Chosen again (the same way) next time.
    }
  }
}
