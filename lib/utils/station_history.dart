import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 加油站选择历史，按使用次数排序，存储于 SharedPreferences。
class StationHistory {
  StationHistory._();

  static const _key = 'station_history';
  static const maxStations = 5;

  /// 返回使用次数最多的前 [maxStations] 个加油站；数据损坏时返回空列表。
  static Future<List<String>> getStations() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final sorted = map.entries.toList()
        ..sort((a, b) => (b.value as int).compareTo(a.value as int));
      return sorted.take(maxStations).map((e) => e.key).toList();
    } catch (e) {
      // 历史数据损坏不应阻塞主流程，视为无历史
      return [];
    }
  }

  /// 记录一次加油站使用；超出容量上限时仅保留次数最多的 [maxStations] 个。
  static Future<void> addStation(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> map;
    try {
      final json = prefs.getString(_key);
      map = json == null ? {} : jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      map = {};
    }
    map[trimmed] = ((map[trimmed] as int?) ?? 0) + 1;
    if (map.length > maxStations * 2) {
      final sorted = map.entries.toList()
        ..sort((a, b) => (b.value as int).compareTo(a.value as int));
      map = {for (final e in sorted.take(maxStations)) e.key: e.value};
    }
    await prefs.setString(_key, jsonEncode(map));
  }
}
