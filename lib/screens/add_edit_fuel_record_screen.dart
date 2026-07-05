import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/fuel_record.dart';
import '../theme/app_theme.dart';

class AddEditFuelRecordScreen extends StatefulWidget {
  final String vehicleId;
  final FuelRecord? existingRecord;

  const AddEditFuelRecordScreen({
    super.key,
    required this.vehicleId,
    this.existingRecord,
  });

  @override
  State<AddEditFuelRecordScreen> createState() =>
      _AddEditFuelRecordScreenState();
}

class _AddEditFuelRecordScreenState extends State<AddEditFuelRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _odometerController = TextEditingController();
  final _litersController = TextEditingController();
  final _priceController = TextEditingController();
  final _stationController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isFullTank = true;
  bool _isSaving = false;

  bool get _isEditing => widget.existingRecord != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final r = widget.existingRecord!;
      _odometerController.text = r.odometer.toString();
      _litersController.text = r.liters.toString();
      _priceController.text = r.pricePerLiter.toString();
      _stationController.text = r.station ?? '';
      _notesController.text = r.notes ?? '';
      _selectedDate = r.date;
      _isFullTank = r.isFullTank;
    }
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _litersController.dispose();
    _priceController.dispose();
    _stationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  double get _totalCost {
    final liters = double.tryParse(_litersController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;
    return liters * price;
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final record = FuelRecord(
        id: _isEditing
            ? widget.existingRecord!.id
            : DateTime.now().millisecondsSinceEpoch.toString(),
        vehicleId: widget.vehicleId,
        date: _selectedDate,
        odometer: int.parse(_odometerController.text),
        liters: double.parse(_litersController.text),
        pricePerLiter: double.parse(_priceController.text),
        isFullTank: _isFullTank,
        station: _stationController.text.isEmpty
            ? null
            : _stationController.text,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );

      if (_isEditing) {
        await DatabaseHelper.instance.updateFuelRecord(record);
      } else {
        await DatabaseHelper.instance.insertFuelRecord(record);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? '记录已更新' : '记录已保存'),
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
        title: Text(_isEditing ? '编辑记录' : '添加加油记录'),
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
            _buildDateField(),
            const SizedBox(height: 16),
            _buildOdometerField(),
            const SizedBox(height: 16),
            _buildLitersField(),
            const SizedBox(height: 16),
            _buildPriceField(),
            const SizedBox(height: 16),
            _buildTotalCostDisplay(),
            const SizedBox(height: 16),
            _buildFullTankSwitch(),
            const SizedBox(height: 16),
            _buildStationField(),
            const SizedBox(height: 16),
            _buildNotesField(),
            const SizedBox(height: 24),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today, color: AppColors.primary),
        title: const Text('加油日期'),
        subtitle: Text(
          DateFormat('yyyy年MM月dd日').format(_selectedDate),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _selectDate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildOdometerField() {
    return TextFormField(
      controller: _odometerController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '里程表读数 (km)',
        prefixIcon: Icon(Icons.straighten),
        hintText: '例如: 50000',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return '请输入里程数';
        final n = int.tryParse(value);
        if (n == null || n < 0) return '请输入有效的里程数';
        return null;
      },
    );
  }

  Widget _buildLitersField() {
    return TextFormField(
      controller: _litersController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: '加油量 (升)',
        prefixIcon: Icon(Icons.water_drop),
        hintText: '例如: 45.5',
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (value == null || value.isEmpty) return '请输入加油量';
        final n = double.tryParse(value);
        if (n == null || n <= 0) return '请输入有效的加油量';
        return null;
      },
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: '单价 (元/升)',
        prefixIcon: Icon(Icons.attach_money),
        hintText: '例如: 7.85',
      ),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (value == null || value.isEmpty) return '请输入单价';
        final n = double.tryParse(value);
        if (n == null || n <= 0) return '请输入有效的单价';
        return null;
      },
    );
  }

  Widget _buildTotalCostDisplay() {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '总费用',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '¥${_totalCost.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullTankSwitch() {
    return Card(
      child: SwitchListTile(
        title: const Text('满箱油'),
        subtitle: const Text(
          '是否加满油箱',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        value: _isFullTank,
        onChanged: (value) => setState(() => _isFullTank = value),
        secondary: Icon(
          _isFullTank ? Icons.local_gas_station : Icons.local_gas_station_outlined,
          color: _isFullTank ? AppColors.primary : AppColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildStationField() {
    return TextFormField(
      controller: _stationController,
      decoration: const InputDecoration(
        labelText: '加油站 (选填)',
        prefixIcon: Icon(Icons.place),
        hintText: '例如: 中国石化朝阳路站',
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: '备注 (选填)',
        prefixIcon: Icon(Icons.notes),
        hintText: '添加备注信息...',
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isSaving ? null : _saveRecord,
      child: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(_isEditing ? '更新记录' : '保存记录'),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条加油记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance
                  .deleteFuelRecord(widget.existingRecord!.id);
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
