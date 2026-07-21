import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

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

class FuelPriceService {
  static const String _selectedProvinceKey = 'selected_fuel_province';
  static const String _cachedPriceKey = 'cached_fuel_price';
  static const String _cachedDateKey = 'cached_fuel_date';

  static const List<String> provinces = [
    '北京', '上海', '天津', '重庆',
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

  static Future<String?> detectProvinceFromLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('[FuelPrice] 定位服务未开启');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      print('[FuelPrice] 当前权限状态: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('[FuelPrice] 请求后权限状态: $permission');
        if (permission == LocationPermission.denied) {
          print('[FuelPrice] 定位权限被拒绝');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('[FuelPrice] 定位权限被永久拒绝');
        return null;
      }

      print('[FuelPrice] 开始获取位置...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 30),
        ),
      );

      print('[FuelPrice] 获取位置成功: ${position.latitude}, ${position.longitude}');

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 10), onTimeout: () => []);

      print('[FuelPrice] 逆地理编码结果数: ${placemarks.length}');

      if (placemarks.isNotEmpty) {
        final province = placemarks.first.administrativeArea;
        print('[FuelPrice] 行政区: $province');
        if (province != null) {
          return _normalizeProvince(province);
        }
      }
    } catch (e, stackTrace) {
      print('[FuelPrice] 定位失败: $e');
      print('[FuelPrice] 堆栈: $stackTrace');
    }
    return null;
  }

  static String _normalizeProvince(String province) {
    for (final p in provinces) {
      if (province.contains(p)) return p;
    }
    return province;
  }

  static Future<FuelPrice?> getCachedPrice() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedDate = prefs.getString(_cachedDateKey);

    if (cachedDate != _todayString()) {
      print('[FuelPrice] 缓存已过期 (cached: $cachedDate, today: ${_todayString()})');
      return null;
    }

    final json = prefs.getString(_cachedPriceKey);
    if (json == null) return null;

    try {
      final price = FuelPrice.fromJson(jsonDecode(json));
      print('[FuelPrice] 命中缓存: ${price.province}, 来源: ${price.source}');
      return price;
    } catch (e) {
      return null;
    }
  }

  static Future<void> _saveCachedPrice(FuelPrice price) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedPriceKey, jsonEncode(price.toJson()));
    await prefs.setString(_cachedDateKey, _todayString());
    print('[FuelPrice] 已缓存: ${price.province}, 来源: ${price.source}');
  }

  static Future<FuelPrice?> fetchFuelPrice(String province, {bool forceRefresh = false}) async {
    final normalizedProvince = _normalizeProvince(province);
    print('[FuelPrice] 开始查询: $normalizedProvince, forceRefresh: $forceRefresh');

    // 1. 非强制刷新时，当天同省份有缓存就直接返回
    if (!forceRefresh) {
      final cached = await getCachedPrice();
      if (cached != null && cached.province == normalizedProvince) {
        print('[FuelPrice] 当天同省份已缓存，直接返回: ${cached.province}');
        return cached;
      }
    }

    // 2. 请求 API
    print('[FuelPrice] 请求 xxapi...');
    final allPrices = await _fetchAllFromXxapi();
    if (allPrices != null && allPrices.containsKey(normalizedProvince)) {
      final price = allPrices[normalizedProvince]!;
      await _saveCachedPrice(price);
      return price;
    }

    print('[FuelPrice] API 请求失败');
    return null;
  }

  static Future<Map<String, FuelPrice>?> _fetchAllFromXxapi() async {
    try {
      final url = Uri.parse('https://v2.xxapi.cn/api/oilPrice');
      print('[FuelPrice] 请求: $url');
      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
      );

      print('[FuelPrice] xxapi 响应: ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['code'] != 200 || data['data'] == null) return null;

      final list = data['data'] as List;
      final prices = <String, FuelPrice>{};
      final now = DateTime.now();

      for (final item in list) {
        final regionName = item['regionName']?.toString() ?? '';
        final normalized = _normalizeProvince(regionName);
        if (normalized.isEmpty || normalized == regionName && !provinces.contains(regionName)) continue;

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

      print('[FuelPrice] xxapi 解析完成: ${prices.length} 个省份');
      return prices.isEmpty ? null : prices;
    } catch (e) {
      print('[FuelPrice] xxapi 失败: $e');
    }
    return null;
  }
}
