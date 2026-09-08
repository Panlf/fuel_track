import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/fuel_record.dart';
import '../theme/app_theme.dart';
import '../utils/fuel_stats_calculator.dart';
import '../utils/fuel_utils.dart';
import '../widgets/stats_card.dart';

/// 统计分析页：概览卡片、油耗趋势、每公里花费、近 6 个月花费柱状图。
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  List<FuelRecord> _records = [];
  bool _isLoading = true;

  // 统计结果在数据加载时一次性计算缓存，避免每次 build 重复排序/遍历
  List<double> _consumptionTrend = const []; // 百公里油耗趋势（保留 2 位小数）
  List<double> _costPerKmTrend = const []; // 每公里花费趋势（保留 3 位小数）
  Map<String, double> _monthlyCost = const {}; // 近 6 个月花费，key 为 yyyy-MM
  double _avgConsumption = 0;
  double _totalCost = 0;
  double _totalLiters = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final vehicles = await DatabaseHelper.instance.getAllVehicles();
      if (vehicles.isNotEmpty) {
        var selectedId = await DatabaseHelper.instance.getSelectedVehicleId();
        if (selectedId == null || !vehicles.any((v) => v.id == selectedId)) {
          selectedId = vehicles.first.id;
        }
        _records = await DatabaseHelper.instance.getFuelRecords(selectedId);

        final stats = FuelStatsCalculator.summarize(_records);
        _avgConsumption = stats.avgConsumption;
        _totalCost = stats.totalCost;
        _totalLiters = stats.totalLiters;
        _consumptionTrend = _records.length < 2
            ? const []
            : FuelUtils.calculateConsumptionTrend(
                _records,
              ).map((v) => double.parse(v.toStringAsFixed(2))).toList();
        _costPerKmTrend = FuelStatsCalculator.costPerKmTrend(_records);
        _monthlyCost = FuelStatsCalculator.monthlyCost(_records);
      }
    } catch (e) {
      debugPrint('Error loading statistics: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('统计分析')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.length < 2
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bar_chart,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '需要至少2条记录才能生成统计',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '去添加更多加油记录吧',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  _buildLineChartCard(
                    title: '油耗趋势 (L/100km)',
                    trend: _consumptionTrend,
                    color: AppColors.chartBlue,
                    reservedSize: 40,
                    axisLabel: (value) => value.toStringAsFixed(2),
                    tooltipLabel: (value) =>
                        '${value.toStringAsFixed(2)} L/100km',
                  ),
                  const SizedBox(height: 16),
                  _buildLineChartCard(
                    title: '每公里花费 (元/km)',
                    trend: _costPerKmTrend,
                    color: AppColors.chartGreen,
                    reservedSize: 50,
                    axisLabel: (value) => '¥${value.toStringAsFixed(2)}',
                    tooltipLabel: (value) => '¥${value.toStringAsFixed(3)}/km',
                    clampMinToZero: true,
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlyCostChart(),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '数据概览',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: StatsCard(
                title: '平均油耗（百公里）',
                value: '${_avgConsumption.toStringAsFixed(2)} L',
                icon: Icons.speed,
                iconColor: AppColors.chartBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatsCard(
                title: '总花费（元）',
                value: FuelUtils.formatCurrency(_totalCost),
                icon: Icons.account_balance_wallet,
                iconColor: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: StatsCard(
                title: '总加油量（升）',
                value: FuelUtils.formatLiters(_totalLiters),
                icon: Icons.local_gas_station,
                iconColor: AppColors.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatsCard(
                title: '记录次数',
                value: '${_records.length} 次',
                icon: Icons.list,
                iconColor: AppColors.chartPurple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 计算「美观」的坐标轴间隔（0.2/0.5/1/2/5…）。
  double _niceInterval(double range, int targetTicks) {
    if (range <= 0) return 0.5;
    final rough = range / targetTicks;
    final mag = (rough * 10).roundToDouble() / 10;
    const candidates = [0.2, 0.5, 1.0, 2.0, 5.0];
    for (final c in candidates) {
      if (c >= mag) return c;
    }
    return mag;
  }

  /// 折线趋势图卡片，油耗趋势与每公里花费共用同一构建逻辑。
  Widget _buildLineChartCard({
    required String title,
    required List<double> trend,
    required Color color,
    required double reservedSize,
    required String Function(double value) axisLabel,
    required String Function(double value) tooltipLabel,
    bool clampMinToZero = false,
  }) {
    if (trend.isEmpty) return const SizedBox.shrink();

    final spots = List<FlSpot>.generate(
      trend.length,
      (i) => FlSpot(i.toDouble(), trend[i]),
    );

    final minVal = trend.reduce((a, b) => a < b ? a : b);
    final maxVal = trend.reduce((a, b) => a > b ? a : b);
    final interval = _niceInterval(maxVal - minVal, 4);
    var minY = (minVal / interval).floor() * interval;
    if (clampMinToZero && minY < 0) minY = 0.0;
    final maxY = (maxVal / interval).ceil() * interval;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: AppColors.divider, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: reservedSize,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            axisLabel(value),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            tooltipLabel(spot.y),
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (trend.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: Colors.white,
                              strokeColor: color,
                              strokeWidth: 2,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyCostChart() {
    final monthlyData = _monthlyCost;
    if (monthlyData.isEmpty) return const SizedBox.shrink();

    final entries = monthlyData.entries.toList();
    final maxValue = entries
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);
    final costInterval = _niceInterval(maxValue, 4);
    final maxY = (maxValue / costInterval).ceil() * costInterval;

    final barGroups = List<BarChartGroupData>.generate(
      entries.length,
      (i) => BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: entries[i].value,
            color: AppColors.chartOrange,
            width: 28,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '最近6个月加油费',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: costInterval,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: AppColors.divider, strokeWidth: 1),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '¥${rod.toY.toStringAsFixed(2)}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: costInterval,
                        getTitlesWidget: (value, meta) {
                          if (value >= 1000) {
                            return Text(
                              '${(value / 1000).toStringAsFixed(1)}k',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            );
                          }
                          return Text(
                            '¥${value.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          final parts = entries[idx].key.split('-');
                          final month = parts.length > 1 ? parts[1] : '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '$month月',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  maxY: maxY,
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
