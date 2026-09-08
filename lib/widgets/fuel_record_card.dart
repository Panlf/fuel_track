import 'package:flutter/material.dart';

import '../models/fuel_record.dart';
import '../theme/app_theme.dart';
import '../utils/fuel_utils.dart';
import 'info_chip.dart';

/// 加油记录卡片：日期/里程/金额 + 油品、油量、单价、油耗徽标 + 加油站。
class FuelRecordCard extends StatelessWidget {
  final FuelRecord record;
  final double? consumption;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const FuelRecordCard({
    super.key,
    required this.record,
    this.consumption,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_gas_station,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          FuelUtils.formatDateFull(record.date),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${FuelUtils.formatOdometer(record.odometer)} · ${record.isFullTank ? '满箱' : '非满箱'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    FuelUtils.formatCurrency(record.totalCost),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (record.fuelType != null &&
                      record.fuelType!.isNotEmpty) ...[
                    InfoChip(
                      icon: Icons.local_gas_station,
                      label: record.fuelType!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  InfoChip(
                    icon: Icons.water_drop,
                    label: '${record.liters.toStringAsFixed(2)} L',
                  ),
                  const SizedBox(width: 8),
                  InfoChip(
                    icon: Icons.attach_money,
                    label: '¥${record.pricePerLiter.toStringAsFixed(2)}/L',
                  ),
                  if (consumption != null) ...[
                    const SizedBox(width: 8),
                    InfoChip(
                      icon: Icons.speed,
                      label: '${consumption!.toStringAsFixed(2)} L/100km',
                      color: _consumptionColor(consumption!),
                    ),
                  ],
                ],
              ),
              if (record.station != null && record.station!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.place,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      record.station!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 按油耗水平分级配色：≤6 优 / ≤8 良 / ≤10 中 / 更高偏差。
  Color _consumptionColor(double consumption) {
    if (consumption <= 6) return AppColors.success;
    if (consumption <= 8) return AppColors.chartBlue;
    if (consumption <= 10) return AppColors.warning;
    return AppColors.error;
  }
}
