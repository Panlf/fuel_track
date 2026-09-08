import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 今日油价实体。
class FuelPrice {
  final String province;
  final double p92;
  final double p95;
  final double p98;
  final double p0;
  final String source;
  final DateTime fetchTime;

  FuelPrice({
    required this.province,
    required this.p92,
    required this.p95,
    required this.p98,
    required this.p0,
    required this.source,
    required this.fetchTime,
  });

  Map<String, dynamic> toJson() => {
    'province': province,
    'p92': p92,
    'p95': p95,
    'p98': p98,
    'p0': p0,
    'source': source,
    'fetchTime': fetchTime.toIso8601String(),
  };

  factory FuelPrice.fromJson(Map<String, dynamic> json) => FuelPrice(
    province: json['province'] ?? '',
    p92: (json['p92'] as num?)?.toDouble() ?? 0,
    p95: (json['p95'] as num?)?.toDouble() ?? 0,
    p98: (json['p98'] as num?)?.toDouble() ?? 0,
    p0: (json['p0'] as num?)?.toDouble() ?? 0,
    source: json['source'] ?? '',
    fetchTime: DateTime.tryParse(json['fetchTime'] ?? '') ?? DateTime.now(),
  );
}

/// 油价查询服务：定位省份 -> 请求 xxapi 油价 -> 当日结果本地缓存。
class FuelPriceService {
  FuelPriceService._();

  static const String _selectedProvinceKey = 'selected_fuel_province';
  static const String _cachedPriceKey = 'cached_fuel_price';
  static const String _cachedDateKey = 'cached_fuel_date';

  static const _channel = MethodChannel('com.github.panlf.fueltrack/location');

  static const List<String> provinces = [
    '北京', '上海', '天津', '重庆', //
    '河北', '山西', '辽宁', '吉林', '黑龙江',
    '江苏', '浙江', '安徽', '福建', '江西', '山东',
    '河南', '湖北', '湖南', '广东', '海南',
    '四川', '贵州', '云南', '陕西', '甘肃', '青海',
    '台湾', '内蒙古', '广西', '西藏', '宁夏', '新疆',
  ];

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<String?> getSelectedProvince() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedProvinceKey);
  }

  static Future<void> setSelectedProvince(String province) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedProvinceKey, province);
  }

  /// 通过原生定位 + 逆地理编码识别当前省份；任一环节失败返回 null。
  static Future<String?> detectProvinceFromLocation() async {
    try {
      debugPrint('[FuelPrice] 调用原生定位...');
      final result = await _channel.invokeMethod('getCurrentLocation');
      debugPrint('[FuelPrice] 原生定位成功: $result');

      final latitude = (result['latitude'] as num?)?.toDouble();
      final longitude = (result['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        debugPrint('[FuelPrice] 原生定位返回坐标无效: $result');
        return null;
      }
      final provider = result['provider'] as String?;
      debugPrint('[FuelPrice] 坐标: $latitude, $longitude, 提供者: $provider');

      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 10), onTimeout: () => []);

      debugPrint('[FuelPrice] 逆地理编码结果数: ${placemarks.length}');

      if (placemarks.isNotEmpty) {
        final province = placemarks.first.administrativeArea;
        debugPrint('[FuelPrice] 行政区: $province');
        if (province != null) {
          return _normalizeProvince(province);
        }
      }
    } on PlatformException catch (e) {
      debugPrint('[FuelPrice] 原生定位失败: ${e.code} - ${e.message}');
    } catch (e, stackTrace) {
      debugPrint('[FuelPrice] 定位失败: $e');
      debugPrint('[FuelPrice] 堆栈: $stackTrace');
    }
    return null;
  }

  /// 将系统返回的行政区名称归一化为省份数据库中的标准名称。
  static String _normalizeProvince(String province) {
    for (final p in provinces) {
      if (province.contains(p)) return p;
    }
    return province;
  }

  /// 读取当日缓存油价；跨天或数据损坏时返回 null。
  static Future<FuelPrice?> getCachedPrice() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedDate = prefs.getString(_cachedDateKey);

    if (cachedDate != _todayString()) {
      debugPrint(
        '[FuelPrice] 缓存已过期 (cached: $cachedDate, today: ${_todayString()})',
      );
      return null;
    }

    final json = prefs.getString(_cachedPriceKey);
    if (json == null) return null;

    try {
      final price = FuelPrice.fromJson(jsonDecode(json));
      debugPrint('[FuelPrice] 命中缓存: ${price.province}, 来源: ${price.source}');
      return price;
    } catch (e) {
      return null;
    }
  }

  static Future<void> _saveCachedPrice(FuelPrice price) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedPriceKey, jsonEncode(price.toJson()));
    await prefs.setString(_cachedDateKey, _todayString());
    debugPrint('[FuelPrice] 已缓存: ${price.province}, 来源: ${price.source}');
  }

  /// 查询指定省份油价；非强制刷新时优先返回当日同省份缓存。
  static Future<FuelPrice?> fetchFuelPrice(
    String province, {
    bool forceRefresh = false,
  }) async {
    final normalizedProvince = _normalizeProvince(province);
    debugPrint(
      '[FuelPrice] 开始查询: $normalizedProvince, forceRefresh: $forceRefresh',
    );

    // 1. 非强制刷新时，当天同省份有缓存就直接返回
    if (!forceRefresh) {
      final cached = await getCachedPrice();
      if (cached != null && cached.province == normalizedProvince) {
        debugPrint('[FuelPrice] 当天同省份已缓存，直接返回: ${cached.province}');
        return cached;
      }
    }

    // 2. 请求 API
    debugPrint('[FuelPrice] 请求 xxapi...');
    final allPrices = await _fetchAllFromXxapi();
    if (allPrices != null && allPrices.containsKey(normalizedProvince)) {
      final price = allPrices[normalizedProvince]!;
      await _saveCachedPrice(price);
      return price;
    }

    debugPrint('[FuelPrice] API 请求失败');
    return null;
  }

  static Future<Map<String, FuelPrice>?> _fetchAllFromXxapi() async {
    try {
      final url = Uri.parse('https://v2.xxapi.cn/api/oilPrice');
      debugPrint('[FuelPrice] 请求: $url');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      debugPrint('[FuelPrice] xxapi 响应: ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['code'] != 200 || data['data'] == null) return null;

      final list = data['data'] as List;
      final prices = <String, FuelPrice>{};
      final now = DateTime.now();

      for (final item in list) {
        final regionName = item['regionName']?.toString() ?? '';
        final normalized = _normalizeProvince(regionName);
        // 跳过无法归一化到已知省份的地区
        if (normalized.isEmpty ||
            (normalized == regionName && !provinces.contains(regionName))) {
          continue;
        }

        final p92 = (item['n92'] as num?)?.toDouble() ?? 0;
        final p95 = (item['n95'] as num?)?.toDouble() ?? 0;
        final p98 = (item['n98'] as num?)?.toDouble() ?? 0;
        final p0 = (item['n0'] as num?)?.toDouble() ?? 0;

        if (p92 > 0) {
          prices[normalized] = FuelPrice(
            province: normalized,
            p92: p92,
            p95: p95,
            p98: p98,
            p0: p0,
            source: 'xxapi',
            fetchTime: now,
          );
        }
      }

      debugPrint('[FuelPrice] xxapi 解析完成: ${prices.length} 个省份');
      return prices.isEmpty ? null : prices;
    } catch (e) {
      debugPrint('[FuelPrice] xxapi 失败: $e');
    }
    return null;
  }
}
