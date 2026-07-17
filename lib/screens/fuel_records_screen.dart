import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../database/database_helper.dart';
import '../models/fuel_record.dart';
import '../utils/fuel_utils.dart';
import '../widgets/fuel_record_card.dart';
import 'add_edit_fuel_record_screen.dart';

class FuelRecordsScreen extends StatefulWidget {
  final VoidCallback? onDataChanged;

  const FuelRecordsScreen({super.key, this.onDataChanged});

  @override
  State<FuelRecordsScreen> createState() => _FuelRecordsScreenState();
}

class _FuelRecordsScreenState extends State<FuelRecordsScreen> {
  List<FuelRecord> _records = [];
  bool _isLoading = true;
  String _vehicleId = '';

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
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

  double? _getConsumption(int index) {
    if (index >= _records.length - 1) return null;
    final sorted = List<FuelRecord>.from(_records)
      ..sort((a, b) => a.odometer.compareTo(b.odometer));
    final currentIdx = sorted.indexWhere((r) => r.id == _records[index].id);
    if (currentIdx <= 0) return null;
    return FuelUtils.calculateConsumption(
        sorted[currentIdx - 1], sorted[currentIdx]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('加油记录'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              onPressed: _exportToExcel,
              tooltip: '导出Excel',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_gas_station_outlined,
                        size: 64,
                        color: Colors.grey.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无加油记录',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '点击右下角按钮添加记录',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRecords,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      return FuelRecordCard(
                        record: _records[index],
                        consumption: _getConsumption(index),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddEditFuelRecordScreen(
                                vehicleId: _vehicleId,
                                existingRecord: _records[index],
                              ),
                            ),
                          );
                          _loadRecords();
                          widget.onDataChanged?.call();
                        },
                        onDelete: () => _confirmDelete(_records[index]),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddEditFuelRecordScreen(
                vehicleId: _vehicleId,
              ),
            ),
          );
          _loadRecords();
          widget.onDataChanged?.call();
        },
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  void _confirmDelete(FuelRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条加油记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteFuelRecord(record.id);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadRecords();
              widget.onDataChanged?.call();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    try {
      final sorted = List<FuelRecord>.from(_records)
        ..sort((a, b) => a.date.compareTo(b.date));

      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['加油记录'];

      final headerStyle = CellStyle(
        bold: true,
        fontSize: 12,
      );

      final headers = ['日期', '里程(km)', '加油量(L)', '单价(¥/L)', '总价(¥)', '油品', '加油站', '备注'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (int i = 0; i < sorted.length; i++) {
        final record = sorted[i];
        final row = i + 1;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            TextCellValue(FuelUtils.formatDateFull(record.date));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            IntCellValue(record.odometer);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
            DoubleCellValue(record.liters);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
            DoubleCellValue(record.pricePerLiter);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
            DoubleCellValue(record.totalCost);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value =
            TextCellValue(record.fuelType ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value =
            TextCellValue(record.station ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value =
            TextCellValue(record.notes ?? '');
      }

      for (int i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 16);
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = '加油记录_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final filePath = '${dir.path}/$fileName';
      final fileBytes = excel.save();

      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已导出到: $filePath'),
              action: SnackBarAction(
                label: '分享',
                onPressed: () {
                  Share.shareXFiles([XFile(filePath)]);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }
}
