import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/vehicle.dart';
import '../theme/app_theme.dart';
import '../utils/vehicle_utils.dart';
import '../widgets/info_chip.dart';
import '../widgets/vehicle_avatar.dart';
import 'add_edit_vehicle_screen.dart';

/// 车库管理页：车辆列表、切换当前车辆、新增/编辑/删除。
class VehicleManagementScreen extends StatefulWidget {
  final VoidCallback? onVehicleChanged;

  const VehicleManagementScreen({super.key, this.onVehicleChanged});

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
    try {
      _vehicles = await DatabaseHelper.instance.getAllVehicles();
      _selectedVehicleId = await DatabaseHelper.instance.getSelectedVehicleId();
      if (_selectedVehicleId == null && _vehicles.isNotEmpty) {
        _selectedVehicleId = _vehicles.first.id;
        await DatabaseHelper.instance.setSelectedVehicleId(_selectedVehicleId!);
      }
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _selectVehicle(Vehicle vehicle) async {
    await DatabaseHelper.instance.setSelectedVehicleId(vehicle.id);
    setState(() => _selectedVehicleId = vehicle.id);
    widget.onVehicleChanged?.call();
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
              widget.onVehicleChanged?.call();
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
      appBar: AppBar(title: const Text('车库管理')),
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
              VehicleAvatar(
                imagePath: vehicle.imagePath,
                size: 64,
                iconSize: 32,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                iconColor: AppColors.primary,
              ),
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
                              horizontal: 8,
                              vertical: 3,
                            ),
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
                      VehicleUtils.subtitle(vehicle),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        InfoChip(
                          icon: Icons.straighten,
                          label: '${vehicle.odometer} km',
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          borderRadius: 6,
                          fontWeight: FontWeight.normal,
                        ),
                        if (vehicle.fuelType != null &&
                            vehicle.fuelType!.isNotEmpty)
                          InfoChip(
                            icon: Icons.local_gas_station,
                            label: vehicle.fuelType!,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            borderRadius: 6,
                            fontWeight: FontWeight.normal,
                          ),
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
}
