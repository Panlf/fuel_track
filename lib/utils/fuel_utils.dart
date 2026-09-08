import 'package:intl/intl.dart';
import '../models/fuel_record.dart';

/// 燃油数据的格式化与油耗计算工具。
class FuelUtils {
  FuelUtils._();

  static final NumberFormat _currencyFormat = NumberFormat('#,##0.00');

  static String formatDateFull(DateTime date) {
    return DateFormat('yyyy年MM月dd日').format(date);
  }

  static String formatCurrency(double value) {
    return '¥${_currencyFormat.format(value)}';
  }

  static String formatOdometer(int km) {
    return '$km km';
  }

  static String formatLiters(double liters) {
    return '${liters.toStringAsFixed(2)} L';
  }

  static String formatConsumption(double? consumption) {
    if (consumption == null) return '--';
    return consumption.toStringAsFixed(2);
  }

  /// 计算相邻两条记录间的百公里油耗；里程无效（不前进）时返回 null。
  static double? calculateConsumption(FuelRecord prev, FuelRecord current) {
    final distance = current.odometer - prev.odometer;
    if (distance <= 0) return null;
    return (current.liters / distance) * 100;
  }

  /// 按里程表升序排列后计算逐段百公里油耗趋势。
  static List<double> calculateConsumptionTrend(List<FuelRecord> records) {
    if (records.length < 2) return const [];
    final sorted = List<FuelRecord>.from(records)
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    final trend = <double>[];
    for (var i = 1; i < sorted.length; i++) {
      final c = calculateConsumption(sorted[i - 1], sorted[i]);
      if (c != null) trend.add(c);
    }
    return trend;
  }
}
