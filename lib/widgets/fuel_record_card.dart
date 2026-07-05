import 'package:flutter/material.dart';
import '../models/fuel_record.dart';
import '../theme/app_theme.dart';
import '../utils/fuel_utils.dart';

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
                  _buildInfoChip(
                      Icons.water_drop, '${record.liters.toStringAsFixed(2)} L'),
                  const SizedBox(width: 8),
                  _buildInfoChip(Icons.attach_money,
                      '¥${record.pricePerLiter.toStringAsFixed(2)}/L'),
                  if (consumption != null) ...[
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.speed,
                      '${consumption!.toStringAsFixed(2)} L/100km',
                      color: _getConsumptionColor(consumption!),
                    ),
                  ],
                ],
              ),
              if (record.station != null && record.station!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.place, size: 14, color: AppColors.textSecondary),
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

  Widget _buildInfoChip(IconData icon, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? AppColors.textSecondary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color ?? AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getConsumptionColor(double consumption) {
    if (consumption <= 6) return AppColors.success;
    if (consumption <= 8) return AppColors.chartBlue;
    if (consumption <= 10) return AppColors.warning;
    return AppColors.error;
  }
}
