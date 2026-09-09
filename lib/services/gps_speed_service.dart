import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 单次 GNSS 定位采样。
class GpsFix {
  final double latitude;
  final double longitude;
  final double altitude;

  /// 水平精度（米），越小越准。
  final double accuracy;

  /// 芯片多普勒测速（米/秒），仅作差分测速的对照参考。
  final double speedMs;

  /// 航向角（度，正北起顺时针）。
  final double bearing;
  final DateTime time;

  GpsFix({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speedMs,
    required this.bearing,
    required this.time,
  });
}

/// GPS 测速流事件：定位采样或流状态（启动/卫星数）。
sealed class GpsEvent {
  const GpsEvent();
}

class GpsFixEvent extends GpsEvent {
  final GpsFix fix;
  const GpsFixEvent(this.fix);
}

class GpsStatusEvent extends GpsEvent {
  /// listening（流已启动）或 gnss（卫星数更新）。
  final String status;
  final int? satellites;
  final String? provider;
  const GpsStatusEvent({required this.status, this.satellites, this.provider});
}

/// GPS 高频测速服务：封装原生 GNSS 定位流与配套的权限/屏幕常亮方法。
class GpsSpeedService {
  GpsSpeedService._();

  static const _method = MethodChannel('com.github.panlf.fueltrack/location');
  static const _speedEvents = EventChannel('com.github.panlf.fueltrack/speed');

  /// 订阅高频定位流。每次订阅原生都会以 minTime=0 重新注册监听，
  /// 取消订阅（cancel）即停止定位，页面退出时务必取消。
  static Stream<GpsEvent> events() {
    return _speedEvents.receiveBroadcastStream().map((data) {
      if (data is Map) {
        final status = data['status'];
        if (status is String) {
          return GpsStatusEvent(
            status: status,
            satellites: (data['satellites'] as num?)?.toInt(),
            provider: data['provider'] as String?,
          );
        }
        final latitude = (data['latitude'] as num?)?.toDouble();
        final longitude = (data['longitude'] as num?)?.toDouble();
        final time = (data['time'] as num?)?.toInt();
        if (latitude == null || longitude == null || time == null) {
          throw FormatException('定位数据格式无效: $data');
        }
        return GpsFixEvent(
          GpsFix(
            latitude: latitude,
            longitude: longitude,
            altitude: (data['altitude'] as num?)?.toDouble() ?? 0,
            accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0,
            speedMs: (data['speed'] as num?)?.toDouble() ?? 0,
            bearing: (data['bearing'] as num?)?.toDouble() ?? 0,
            time: DateTime.fromMillisecondsSinceEpoch(time),
          ),
        );
      }
      throw FormatException('未知事件类型: $data');
    });
  }

  /// 申请定位权限；返回是否授予。永久拒绝时返回 false，可引导用户去系统设置。
  static Future<bool> requestPermission() async {
    try {
      return await _method.invokeMethod('requestLocationPermission') == true;
    } on PlatformException {
      return false;
    }
  }

  /// 打开本应用的系统设置页（手动授权场景）。
  static Future<void> openAppSettings() async {
    try {
      await _method.invokeMethod('openAppSettings');
    } on PlatformException catch (e) {
      debugPrint('[GpsSpeed] 打开系统设置失败: ${e.message}');
    }
  }

  /// 测速页期间保持屏幕常亮。
  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await _method.invokeMethod('setKeepScreenOn', {'on': on});
    } on PlatformException catch (e) {
      debugPrint('[GpsSpeed] 屏幕常亮设置失败: ${e.message}');
    }
  }
}
