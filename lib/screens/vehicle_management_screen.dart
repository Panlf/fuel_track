import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/vehicle.dart';
import '../theme/app_theme.dart';
import 'add_edit_vehicle_screen.dart';

class VehicleManagementScreen extends StatefulWidget {
  const VehicleManagementScreen({super.key});

  @override
  State<VehicleManagementScreen> createState() =>
      _VehicleManagementScreenState();
}

class _VehicleManagementScreenState extends State<VehicleManagementScreen> {
  List<Vehicle> _vehicles = [];
  String? _selectedVehicleId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _vehicles = await DatabaseHelper.instance.getAllVehicles();
    _selectedVehicleId = await DatabaseHelper.instance.getSelectedVehicleId();
    if (_selectedVehicleId == null && _vehicles.isNotEmpty) {
      _selectedVehicleId = _vehicles.first.id;
      await DatabaseHelper.instance.setSelectedVehicleId(_selectedVehicleId!);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _selectVehicle(Vehicle vehicle) async {
    await DatabaseHelper.instance.setSelectedVehicleId(vehicle.id);
    setState(() => _selectedVehicleId = vehicle.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到 ${vehicle.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _confirmDelete(Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除车辆'),
        content: Text('确定要删除「${vehicle.name}」吗？\n该车辆的所有加油记录也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteVehicle(vehicle.id);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('车库管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vehicles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 64,
                        color: Colors.grey.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '还没有添加车辆',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '点击右下角按钮添加第一辆车',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _vehicles.length,
                    itemBuilder: (context, index) {
                      final vehicle = _vehicles[index];
                      final isSelected = vehicle.id == _selectedVehicleId;
                      return _buildVehicleCard(vehicle, isSelected);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEditVehicleScreen()),
          );
          _loadData();
        },
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Widget _buildVehicleCard(Vehicle vehicle, bool isSelected) {
    return Card(
      color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : null,
      child: InkWell(
        onTap: () => _selectVehicle(vehicle),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildVehicleAvatar(vehicle),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vehicle.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildSubtitle(vehicle),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildInfoChip(Icons.straighten,
                            '${vehicle.odometer} km'),
                        if (vehicle.fuelType != null &&
                            vehicle.fuelType!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _buildInfoChip(
                              Icons.local_gas_station, vehicle.fuelType!),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddEditVehicleScreen(existingVehicle: vehicle),
                      ),
                    ).then((_) => _loadData());
                  } else if (value == 'delete') {
                    _confirmDelete(vehicle);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleAvatar(Vehicle vehicle) {
    if (vehicle.imagePath != null && vehicle.imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(vehicle.imagePath!),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
        ),
      );
    }
    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.directions_car,
        color: AppColors.primary,
        size: 32,
      ),
    );
  }

  String _buildSubtitle(Vehicle vehicle) {
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
    return parts.isEmpty ? '暂无详细信息' : parts.join(' ');
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
