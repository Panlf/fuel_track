import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../database/database_helper.dart';
import '../models/vehicle.dart';
import '../theme/app_theme.dart';

class AddEditVehicleScreen extends StatefulWidget {
  final Vehicle? existingVehicle;

  const AddEditVehicleScreen({super.key, this.existingVehicle});

  @override
  State<AddEditVehicleScreen> createState() => _AddEditVehicleScreenState();
}

class _AddEditVehicleScreenState extends State<AddEditVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _fuelTypeController = TextEditingController();
  final _tankCapacityController = TextEditingController();
  final _odometerController = TextEditingController();

  String? _imagePath;
  bool _isSaving = false;
  final _picker = ImagePicker();

  bool get _isEditing => widget.existingVehicle != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final v = widget.existingVehicle!;
      _nameController.text = v.name;
      _brandController.text = v.brand ?? '';
      _modelController.text = v.model ?? '';
      _yearController.text = v.year?.toString() ?? '';
      _fuelTypeController.text = v.fuelType ?? '';
      _tankCapacityController.text = v.tankCapacity?.toString() ?? '';
      _odometerController.text = v.odometer.toString();
      _imagePath = v.imagePath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _fuelTypeController.dispose();
    _tankCapacityController.dispose();
    _odometerController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final vehiclesDir = Directory('${appDir.path}/vehicle_images');
    if (!await vehiclesDir.exists()) {
      await vehiclesDir.create(recursive: true);
    }

    final fileName =
        'vehicle_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
    final savedFile = await File(picked.path).copy('${vehiclesDir.path}/$fileName');

    if (_imagePath != null && _imagePath!.isNotEmpty) {
      final oldFile = File(_imagePath!);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    }

    setState(() => _imagePath = savedFile.path);
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '选择图片来源',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: AppColors.primary),
                title: const Text('从相册选择'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt,
                    color: AppColors.primary),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_imagePath != null && _imagePath!.isNotEmpty)
                ListTile(
                  leading:
                      const Icon(Icons.delete, color: AppColors.error),
                  title: const Text('移除图片'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _imagePath = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final vehicle = Vehicle(
        id: _isEditing
            ? widget.existingVehicle!.id
            : DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        brand: _brandController.text.trim().isEmpty
            ? null
            : _brandController.text.trim(),
        model: _modelController.text.trim().isEmpty
            ? null
            : _modelController.text.trim(),
        year: int.tryParse(_yearController.text),
        fuelType: _fuelTypeController.text.trim().isEmpty
            ? null
            : _fuelTypeController.text.trim(),
        tankCapacity: double.tryParse(_tankCapacityController.text),
        odometer: int.tryParse(_odometerController.text) ?? 0,
        imagePath: _imagePath,
      );

      if (_isEditing) {
        await DatabaseHelper.instance.updateVehicle(vehicle);
      } else {
        await DatabaseHelper.instance.insertVehicle(vehicle);
        await DatabaseHelper.instance.setSelectedVehicleId(vehicle.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? '车辆信息已更新' : '车辆已添加'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑车辆' : '添加车辆'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildImageSection(),
            const SizedBox(height: 20),
            _buildNameField(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildBrandField()),
                const SizedBox(width: 12),
                Expanded(child: _buildModelField()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildYearField()),
                const SizedBox(width: 12),
                Expanded(child: _buildTankCapacityField()),
              ],
            ),
            const SizedBox(height: 16),
            _buildFuelTypeField(),
            const SizedBox(height: 16),
            if (_isEditing) ...[
              _buildOdometerField(),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 24),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Center(
      child: GestureDetector(
        onTap: _showImageSourceDialog,
        child: Stack(
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: _imagePath != null && _imagePath!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(
                        File(_imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      ),
                    )
                  : _buildPlaceholder(),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.directions_car_outlined,
          size: 48,
          color: AppColors.primary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          '添加照片',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.primary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: '车辆名称 *',
        prefixIcon: Icon(Icons.label),
        hintText: '例如: 我的爱车',
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return '请输入车辆名称';
        return null;
      },
    );
  }

  Widget _buildBrandField() {
    return TextFormField(
      controller: _brandController,
      decoration: const InputDecoration(
        labelText: '品牌',
        hintText: '例如: 丰田',
      ),
    );
  }

  Widget _buildModelField() {
    return TextFormField(
      controller: _modelController,
      decoration: const InputDecoration(
        labelText: '型号',
        hintText: '例如: 卡罗拉',
      ),
    );
  }

  Widget _buildYearField() {
    return TextFormField(
      controller: _yearController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '年份',
        hintText: '例如: 2024',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return null;
        final n = int.tryParse(value);
        if (n == null || n < 1900 || n > 2100) return '请输入有效年份';
        return null;
      },
    );
  }

  Widget _buildTankCapacityField() {
    return TextFormField(
      controller: _tankCapacityController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: '油箱容量 (L)',
        hintText: '例如: 55',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return null;
        final n = double.tryParse(value);
        if (n == null || n <= 0) return '请输入有效容量';
        return null;
      },
    );
  }

  Widget _buildFuelTypeField() {
    return TextFormField(
      controller: _fuelTypeController,
      decoration: const InputDecoration(
        labelText: '油品类型',
        prefixIcon: Icon(Icons.local_gas_station),
        hintText: '例如: 95号汽油',
      ),
    );
  }

  Widget _buildOdometerField() {
    return TextFormField(
      controller: _odometerController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '当前里程 (km)',
        prefixIcon: Icon(Icons.straighten),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return '请输入里程数';
        final n = int.tryParse(value);
        if (n == null || n < 0) return '请输入有效里程数';
        return null;
      },
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveVehicle,
      child: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(_isEditing ? '保存修改' : '添加车辆'),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除车辆'),
        content: const Text('确定要删除这辆车吗？\n该车辆的所有加油记录也会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance
                  .deleteVehicle(widget.existingVehicle!.id);
              // ignore: use_build_context_synchronously
              Navigator.pop(ctx);
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
