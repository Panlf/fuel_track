import '../models/fuel_record.dart';
import '../models/fuel_stats.dart';
import 'fuel_utils.dart';

/// 基于加油记录列表的统计计算，统一供概览页、记录页、统计页使用，
/// 保证各处统计口径一致，避免重复实现。
class FuelStatsCalculator {
  FuelStatsCalculator._();

  /// 汇总统计；平均油耗取逐段油耗的算术平均值，与图表口径一致。
  static FuelStats summarize(List<FuelRecord> records) {
    final trend = FuelUtils.calculateConsumptionTrend(records);
    final avgConsumption = trend.isEmpty
        ? 0.0
        : trend.reduce((a, b) => a + b) / trend.length;
    final totalCost = records.fold(0.0, (sum, r) => sum + r.totalCost);
    final totalLiters = records.fold(0.0, (sum, r) => sum + r.liters);

    double? best;
    double? worst;
    for (final c in trend) {
      if (best == null || c < best) best = c;
      if (worst == null || c > worst) worst = c;
    }

    var totalDistance = 0.0;
    if (records.length >= 2) {
      final sorted = List<FuelRecord>.from(records)
        ..sort((a, b) => a.odometer.compareTo(b.odometer));
      totalDistance = (sorted.last.odometer - sorted.first.odometer).toDouble();
    }
    final avgPricePerLiter = totalLiters > 0 ? totalCost / totalLiters : 0.0;

    return FuelStats(
      avgConsumption: avgConsumption,
      totalCost: totalCost,
      totalLiters: totalLiters,
      totalDistance: totalDistance,
      avgPricePerLiter: avgPricePerLiter,
      bestConsumption: best,
      worstConsumption: worst,
    );
  }

  /// 每条记录相对「里程表顺序前一条记录」的百公里油耗，按记录 id 索引。
  static Map<String, double> consumptionByRecordId(List<FuelRecord> records) {
    if (records.length < 2) return const {};
    final sorted = List<FuelRecord>.from(records)
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    final result = <String, double>{};
    for (var i = 1; i < sorted.length; i++) {
      final c = FuelUtils.calculateConsumption(sorted[i - 1], sorted[i]);
      if (c != null) result[sorted[i].id] = c;
    }
    return result;
  }

  /// 每公里花费趋势（元/km），保留 3 位小数。
  static List<double> costPerKmTrend(List<FuelRecord> records) {
    if (records.length < 2) return const [];
    final sorted = List<FuelRecord>.from(records)
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    final trend = <double>[];
    for (var i = 1; i < sorted.length; i++) {
      final distance = sorted[i].odometer - sorted[i - 1].odometer;
      if (distance > 0) {
        trend.add(
          double.parse((sorted[i].totalCost / distance).toStringAsFixed(3)),
        );
      }
    }
    return trend;
  }

  /// 最近 [months] 个月（含当月）的加油花费，key 为「yyyy-MM」，按月份升序返回。
  static Map<String, double> monthlyCost(
    List<FuelRecord> records, {
    int months = 6,
  }) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - (months - 1));
    final monthly = <String, double>{};
    for (final record in records) {
      if (record.date.isBefore(cutoff)) continue;
      final key =
          '${record.date.year}-${record.date.month.toString().padLeft(2, '0')}';
      monthly[key] = (monthly[key] ?? 0) + record.totalCost;
    }
    final keys = monthly.keys.toList()..sort();
    return {for (final key in keys) key: monthly[key]!};
  }
}
