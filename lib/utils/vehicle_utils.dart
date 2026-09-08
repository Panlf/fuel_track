import '../models/vehicle.dart';

/// 车辆信息的展示工具。
class VehicleUtils {
  VehicleUtils._();

  /// 拼接车辆的描述副标题：「品牌 型号 xxxx款」。
  ///
  /// [vehicle] 为 null 时返回 [nullText]；信息为空时返回 [emptyText]。
  static String subtitle(
    Vehicle? vehicle, {
    String nullText = '暂无详细信息',
    String emptyText = '暂无详细信息',
  }) {
    if (vehicle == null) return nullText;
    final parts = <String>[
      if (vehicle.brand != null && vehicle.brand!.isNotEmpty) vehicle.brand!,
      if (vehicle.model != null && vehicle.model!.isNotEmpty) vehicle.model!,
      if (vehicle.year != null) '${vehicle.year}款',
    ];
    return parts.isEmpty ? emptyText : parts.join(' ');
  }
}
