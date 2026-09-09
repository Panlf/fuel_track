import 'dart:math' as math;

import '../services/gps_speed_service.dart';

/// 一次差分测速结果。
class SpeedReading {
  /// 平滑后当前速度（km/h），表针显示值。
  final double speedKmh;

  /// 本帧差分原始速度（km/h），未平滑，仅作对照。
  final double rawKmh;

  /// 本次会话最高速度（km/h）。
  final double maxKmh;

  /// 本次会话平均速度（km/h），按累计真实位移 / 累计时间计算。
  final double avgKmh;

  /// 平滑后纵向加速度（G），加速为正、制动为负。
  final double gForce;

  /// 本帧位移低于噪声门限，视为静止。
  final bool isNoise;

  const SpeedReading({
    required this.speedKmh,
    required this.rawKmh,
    required this.maxKmh,
    required this.avgKmh,
    required this.gForce,
    required this.isNoise,
  });
}

/// 基于 Haversine 大圆距离的高频差分测速器。
///
/// 距离采用 Haversine 公式（航海/航空领域计算两点球面距离的标准公式，
/// 在数十米~数公里的车辆行驶尺度上误差远小于 GPS 精度本身）：
///
///   a = sin²(Δφ/2) + cosφ₁·cosφ₂·sin²(Δλ/2)
///   d = 2R·atan2(√a, √(1−a))，R 取 IUGG 平均地球半径 6371008.8 m
///
/// 速度 v = d/Δt。原始差分对 GPS 噪声敏感，做两级处理：
/// 1. 噪声门限：位移小于精度不确定度的一半时视为静止（过滤原地漂移）；
/// 2. 自适应 EMA：α = 1 − e^(−Δt/τ)，τ 为时间常数，采样越快响应越快，
///    且不随采样率变化而失稳。
class GpsSpeedCalculator {
  GpsSpeedCalculator({
    this.smoothingTauMs = 600,
    this.gTauMs = 1000,
    this.maxSpeedMs = 500.0,
    this.maxPlausibleMs = 111.2,
  });

  /// IUGG 推荐平均地球半径（米）。
  static const double earthRadiusM = 6371008.8;

  static const double gravityMs2 = 9.80665;

  /// 速度 EMA 时间常数（毫秒），越小表针响应越快。
  final int smoothingTauMs;

  /// 加速度 EMA 时间常数（毫秒），取长一些避免 G 值跳动。
  final int gTauMs;

  /// 差分速度的物理上限（米/秒），过滤卫星跳变产生的瞬时荒谬值。
  final double maxSpeedMs;

  /// 位置合理性上限（米/秒，默认约 400km/h）。差分速度超过该值的帧视为
  /// 坏点（卫星重捕获、位置跳变）——该帧不参与测速，避免污染表针与统计。
  final double maxPlausibleMs;

  GpsFix? _lastFix;
  double _smoothedMs = 0;
  double _smoothedG = 0;
  double _maxKmh = 0;
  double _totalDistanceM = 0;
  double _totalTimeS = 0;

  /// 两点 Haversine 大圆距离（米）。
  static double haversineDistanceM(
    double lat1Deg,
    double lon1Deg,
    double lat2Deg,
    double lon2Deg,
  ) {
    final lat1 = _degToRad(lat1Deg);
    final lat2 = _degToRad(lat2Deg);
    final dLat = _degToRad(lat2Deg - lat1Deg);
    final dLon = _degToRad(lon2Deg - lon1Deg);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  /// 输入一次定位采样，输出测速结果；首个采样无前点可比，返回 null。
  SpeedReading? process(GpsFix fix) {
    final last = _lastFix;
    _lastFix = fix;
    if (last == null) return null;

    final dtS = fix.time.difference(last.time).inMicroseconds / 1e6;
    if (dtS <= 0) return null; // 时间戳异常（重放/对齐）直接丢弃本帧

    final distM = haversineDistanceM(
      last.latitude,
      last.longitude,
      fix.latitude,
      fix.longitude,
    );

    // 坏点剔除：位置跳变（重捕获/瞬移）产生的帧不参与测速，
    // 但仍更新参考点，保证下一帧恢复正常
    if (distM / dtS > maxPlausibleMs) return null;

    // 噪声门限：两次精度取较小者的一半，且不低于 1m（过滤静止漂移）
    final noiseGateM = math.max(1.0, 0.5 * math.min(last.accuracy, fix.accuracy));
    final isNoise = distM <= noiseGateM;
    final movingDistM = isNoise ? 0.0 : distM;

    final rawMs = movingDistM / dtS > maxSpeedMs ? maxSpeedMs : movingDistM / dtS;

    // 自适应 EMA：α = 1 − e^(−Δt/τ)，与采样率解耦
    final alpha = 1.0 - math.exp(-dtS * 1000 / smoothingTauMs);
    final prevSmoothedMs = _smoothedMs;
    _smoothedMs += alpha * (rawMs - prevSmoothedMs);

    // 纵向加速度（G），EMA 时间常数更长
    final gAlpha = 1.0 - math.exp(-dtS * 1000 / gTauMs);
    final rawG = (_smoothedMs - prevSmoothedMs) / dtS / gravityMs2;
    _smoothedG = (_smoothedG + gAlpha * (rawG - _smoothedG)).clamp(-1.5, 1.5);

    final speedKmh = _smoothedMs * 3.6;
    if (speedKmh > _maxKmh) _maxKmh = speedKmh;

    _totalDistanceM += movingDistM;
    _totalTimeS += dtS;

    return SpeedReading(
      speedKmh: speedKmh,
      rawKmh: rawMs * 3.6,
      maxKmh: _maxKmh,
      avgKmh: _totalTimeS > 0 ? (_totalDistanceM / _totalTimeS) * 3.6 : 0,
      gForce: _smoothedG,
      isNoise: isNoise,
    );
  }

  /// 清空会话统计（当前速度平滑值保留，仅重置最高/平均）。
  void resetStats() {
    _maxKmh = 0;
    _totalDistanceM = 0;
    _totalTimeS = 0;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;
}
