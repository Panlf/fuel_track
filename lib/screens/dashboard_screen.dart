import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/vehicle.dart';
import '../models/fuel_record.dart';
import '../theme/app_theme.dart';
import '../utils/fuel_utils.dart';
import '../widgets/stats_card.dart';
import '../widgets/fuel_record_card.dart';
import 'add_edit_fuel_record_screen.dart';
import 'fuel_records_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Vehicle? _currentVehicle;
  List<Vehicle> _allVehicles = [];
  List<FuelRecord> _recentRecords = [];
  bool _isLoading = true;
  double _avgConsumption = 0;
  double _totalCost = 0;
  double _totalLiters = 0;
  int _totalRecords = 0;

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
    try {
      _allVehicles = await DatabaseHelper.instance.getAllVehicles();
      if (_allVehicles.isEmpty) {
        final newVehicle = Vehicle(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '我的爱车',
          brand: '',
          model: '',
        );
        await DatabaseHelper.instance.insertVehicle(newVehicle);
        await DatabaseHelper.instance.setSelectedVehicleId(newVehicle.id);
        _allVehicles = await DatabaseHelper.instance.getAllVehicles();
        _currentVehicle = newVehicle;
      } else {
        var selectedId = await DatabaseHelper.instance.getSelectedVehicleId();
        if (selectedId == null || !_allVehicles.any((v) => v.id == selectedId)) {
          selectedId = _allVehicles.first.id;
          await DatabaseHelper.instance.setSelectedVehicleId(selectedId);
        }
        _currentVehicle = _allVehicles.firstWhere((v) => v.id == selectedId);
      }

      if (_currentVehicle != null) {
        final records =
            await DatabaseHelper.instance.getFuelRecords(_currentVehicle!.id);
        _recentRecords = records.take(5).toList();
        _totalRecords = records.length;

        if (records.length >= 2) {
          final sorted = List<FuelRecord>.from(records)
            ..sort((a, b) => a.odometer.compareTo(b.odometer));
          final consumptions = <double>[];
          for (int i = 1; i < sorted.length; i++) {
            final c = FuelUtils.calculateConsumption(sorted[i - 1], sorted[i]);
            if (c != null) consumptions.add(c);
          }
          if (consumptions.isNotEmpty) {
            _avgConsumption =
                consumptions.reduce((a, b) => a + b) / consumptions.length;
          }
        } else {
          _avgConsumption = 0;
        }
        _totalCost = records.fold(0.0, (sum, r) => sum + r.totalCost);
        _totalLiters = records.fold(0.0, (sum, r) => sum + r.liters);
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _switchVehicle(Vehicle vehicle) async {
    await DatabaseHelper.instance.setSelectedVehicleId(vehicle.id);
    _loadData();
  }

  void _showVehicleSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '切换车辆',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...(_allVehicles.map((vehicle) {
              final isSelected = vehicle.id == _currentVehicle?.id;
              return ListTile(
                leading: _buildSheetAvatar(vehicle, 40),
                title: Text(
                  vehicle.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _buildSubtitleText(vehicle),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchVehicle(vehicle);
                },
              );
            })),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 260,
                    pinned: true,
                    backgroundColor: AppColors.primary,
                    flexibleSpace: FlexibleSpaceBar(
                      background: _buildHeaderBackground(),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildQuickStats(),
                        const SizedBox(height: 8),
                        _buildRecentSection(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditFuelRecordScreen(
                vehicleId: _currentVehicle?.id ?? '',
              ),
            ),
          );
          _loadData();
        },
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Widget _buildHeaderBackground() {
    final hasImage = _currentVehicle?.imagePath != null &&
        _currentVehicle!.imagePath!.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          Image.file(
            File(_currentVehicle!.imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildGradientBackground(),
          )
        else
          _buildGradientBackground(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.1),
                Colors.black.withValues(alpha: 0.7),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _showVehicleSelector,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeaderAvatar(),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (_allVehicles.length > 1)
                      TextButton.icon(
                        onPressed: _showVehicleSelector,
                        icon: Icon(
                          Icons.swap_horiz,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 18,
                        ),
                        label: Text(
                          '切换',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _currentVehicle?.name ?? '我的爱车',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildSubtitleText(_currentVehicle),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildHeaderChip(
                        Icons.straighten,
                        FuelUtils.formatOdometer(
                            _currentVehicle?.odometer ?? 0)),
                    const SizedBox(width: 10),
                    if (_currentVehicle?.fuelType != null &&
                        _currentVehicle!.fuelType!.isNotEmpty)
                      _buildHeaderChip(
                          Icons.local_gas_station, _currentVehicle!.fuelType!),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderAvatar() {
    if (_currentVehicle?.imagePath != null &&
        _currentVehicle!.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(_currentVehicle!.imagePath!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultHeaderAvatar(),
        ),
      );
    }
    return _buildDefaultHeaderAvatar();
  }

  Widget _buildDefaultHeaderAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.directions_car,
        color: Colors.white,
        size: 26,
      ),
    );
  }

  Widget _buildSheetAvatar(Vehicle vehicle, double size) {
    if (vehicle.imagePath != null && vehicle.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(vehicle.imagePath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultSheetAvatar(size),
        ),
      );
    }
    return _buildDefaultSheetAvatar(size);
  }

  Widget _buildDefaultSheetAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.directions_car,
        color: AppColors.primary,
        size: size * 0.5,
      ),
    );
  }

  Widget _buildHeaderChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitleText(Vehicle? vehicle) {
    if (vehicle == null) return '点击切换车辆';
    final parts = <String>[];
    if (vehicle.brand != null && vehicle.brand!.isNotEmpty) {
      parts.add(vehicle.brand!);
    }
    if (vehicle.model != null && vehicle.model!.isNotEmpty) {
      parts.add(vehicle.model!);
    }
    if (vehicle.year != null) {
      parts.add('${vehicle.year}款');
    }
    return parts.isEmpty ? '前往车库添加详细信息' : parts.join(' ');
  }

  Widget _buildQuickStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
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
                  value: FuelUtils.formatConsumption(_avgConsumption),
                  icon: Icons.speed,
                  iconColor: AppColors.chartBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatsCard(
                  title: '总花费',
                  value: FuelUtils.formatCurrency(_totalCost),
                  subtitle: '共 $_totalRecords 次加油',
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
                  title: '当前里程',
                  value: FuelUtils.formatOdometer(
                      _currentVehicle?.odometer ?? 0),
                  icon: Icons.straighten,
                  iconColor: AppColors.chartPurple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '最近加油',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FuelRecordsScreen()),
                  );
                },
                child: const Text('查看全部'),
              ),
            ],
          ),
          if (_recentRecords.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_gas_station_outlined,
                        size: 48,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '还没有加油记录',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '点击 + 添加第一条记录',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...(_recentRecords.map((record) => FuelRecordCard(
                  record: record,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddEditFuelRecordScreen(
                          vehicleId: _currentVehicle?.id ?? '',
                          existingRecord: record,
                        ),
                      ),
                    );
                    _loadData();
                  },
                ))),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
