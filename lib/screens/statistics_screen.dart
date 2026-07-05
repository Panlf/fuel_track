import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';
import '../models/fuel_record.dart';
import '../theme/app_theme.dart';
import '../utils/fuel_utils.dart';
import '../widgets/stats_card.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  List<FuelRecord> _records = [];
  bool _isLoading = true;
  String _vehicleId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final vehicles = await DatabaseHelper.instance.getAllVehicles();
    if (vehicles.isNotEmpty) {
      var selectedId = await DatabaseHelper.instance.getSelectedVehicleId();
      if (selectedId == null || !vehicles.any((v) => v.id == selectedId)) {
        selectedId = vehicles.first.id;
      }
      _vehicleId = selectedId;
      _records = await DatabaseHelper.instance.getFuelRecords(_vehicleId);
    }
    setState(() => _isLoading = false);
  }

  List<double> get _consumptionTrend {
    if (_records.length < 2) return [];
    final sorted = List<FuelRecord>.from(_records)
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    final trend = <double>[];
    for (int i = 1; i < sorted.length; i++) {
      final c = FuelUtils.calculateConsumption(sorted[i - 1], sorted[i]);
      if (c != null) trend.add(c);
    }
    return trend;
  }

  List<double> get _costTrend {
    final sorted = List<FuelRecord>.from(_records)
      ..sort((a, b) => a.date.compareTo(b.date));
    return sorted.map((r) => r.totalCost).toList();
  }

  List<double> get _litersTrend {
    final sorted = List<FuelRecord>.from(_records)
      ..sort((a, b) => a.date.compareTo(b.date));
    return sorted.map((r) => r.liters).toList();
  }

  double get _avgConsumption {
    final trend = _consumptionTrend;
    if (trend.isEmpty) return 0;
    return trend.reduce((a, b) => a + b) / trend.length;
  }

  double get _totalCost => _records.fold(0.0, (sum, r) => sum + r.totalCost);

  double get _totalLiters => _records.fold(0.0, (sum, r) => sum + r.liters);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计分析'),
      ),
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
                      _buildConsumptionChart(),
                      const SizedBox(height: 16),
                      _buildCostChart(),
                      const SizedBox(height: 16),
                      _buildLitersChart(),
                      const SizedBox(height: 16),
                      _buildMonthlyStats(),
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
                title: '平均油耗',
                value: '${_avgConsumption.toStringAsFixed(2)} L/100km',
                icon: Icons.speed,
                iconColor: AppColors.chartBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatsCard(
                title: '总花费',
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
                title: '总加油量',
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

  Widget _buildConsumptionChart() {
    final trend = _consumptionTrend;
    if (trend.isEmpty) return const SizedBox.shrink();

    final spots = trend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final minY = trend.reduce((a, b) => a < b ? a : b) - 0.5;
    final maxY = trend.reduce((a, b) => a > b ? a : b) + 0.5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '油耗趋势 (L/100km)',
              style: TextStyle(
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
                    horizontalInterval: (maxY - minY) / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(1),
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
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (trend.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppColors.chartBlue,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeColor: AppColors.chartBlue,
                          strokeWidth: 2,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.chartBlue.withValues(alpha: 0.1),
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

  Widget _buildCostChart() {
    if (_costTrend.isEmpty) return const SizedBox.shrink();

    final spots = _costTrend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final maxY = _costTrend.reduce((a, b) => a > b ? a : b) * 1.1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '加油费用趋势 (元)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '¥${(value / 100).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  maxY: maxY,
                  barGroups: spots
                      .map((spot) => BarChartGroupData(
                            x: spot.x.toInt(),
                            barRods: [
                              BarChartRodData(
                                toY: spot.y,
                                color: AppColors.chartOrange,
                                width: 16,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLitersChart() {
    if (_litersTrend.isEmpty) return const SizedBox.shrink();

    final spots = _litersTrend
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final maxY = _litersTrend.reduce((a, b) => a > b ? a : b) * 1.1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '加油量趋势 (升)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(0),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  maxY: maxY,
                  barGroups: spots
                      .map((spot) => BarChartGroupData(
                            x: spot.x.toInt(),
                            barRods: [
                              BarChartRodData(
                                toY: spot.y,
                                color: AppColors.chartGreen,
                                width: 16,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyStats() {
    final monthlyData = <String, double>{};
    for (final record in _records) {
      final key =
          '${record.date.year}-${record.date.month.toString().padLeft(2, '0')}';
      monthlyData[key] = (monthlyData[key] ?? 0) + record.totalCost;
    }

    if (monthlyData.isEmpty) return const SizedBox.shrink();

    final sorted = monthlyData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '月度花费',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...sorted.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.chartOrange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        FuelUtils.formatCurrency(entry.value),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
