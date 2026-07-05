import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StationHistory {
  static const _key = 'station_history';
  static const maxStations = 5;

  static Future<List<String>> getStations() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    final Map<String, dynamic> map = jsonDecode(json);
    final sorted = map.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));
    return sorted.take(maxStations).map((e) => e.key).toList();
  }

  static Future<void> addStation(String name) async {
    if (name.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    final Map<String, dynamic> map = json == null ? {} : jsonDecode(json);
    map[name.trim()] = ((map[name.trim()] as int?) ?? 0) + 1;
    if (map.length > maxStations * 2) {
      final sorted = map.entries.toList()
        ..sort((a, b) => (b.value as int).compareTo(a.value as int));
      map.clear();
      for (final e in sorted.take(maxStations)) {
        map[e.key] = e.value;
      }
    }
    await prefs.setString(_key, jsonEncode(map));
  }
}
