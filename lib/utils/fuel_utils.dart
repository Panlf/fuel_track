import 'package:intl/intl.dart';
import '../models/fuel_record.dart';

class FuelUtils {
  static String formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String formatDateShort(DateTime date) {
    return DateFormat('MM/dd').format(date);
  }

  static String formatDateFull(DateTime date) {
    return DateFormat('yyyy年MM月dd日').format(date);
  }

  static String formatNumber(double value, {int decimals = 2}) {
    return value.toStringAsFixed(decimals);
  }

  static String formatCurrency(double value) {
    final formatter = NumberFormat('#,##0.00');
    return '¥${formatter.format(value)}';
  }

  static String formatOdometer(int km) {
    return '$km km';
  }

  static String formatLiters(double liters) {
    return '${liters.toStringAsFixed(2)} L';
  }

  static String formatConsumption(double? consumption) {
    if (consumption == null) return '--';
    return '${consumption.toStringAsFixed(2)} L/100km';
  }

  static double? calculateConsumption(
      FuelRecord prev, FuelRecord current) {
    final distance = current.odometer - prev.odometer;
    if (distance <= 0) return null;
    return (current.liters / distance) * 100;
  }

  static List<double> calculateConsumptionTrend(List<FuelRecord> records) {
    if (records.length < 2) return [];
    final sorted = List<FuelRecord>.from(records)
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    final trend = <double>[];
    for (int i = 1; i < sorted.length; i++) {
      final c = calculateConsumption(sorted[i - 1], sorted[i]);
      if (c != null) trend.add(c);
    }
    return trend;
  }
}
