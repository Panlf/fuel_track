import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 轻量信息徽标（图标 + 文本），供加油记录卡片、车库卡片等处共用。
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// 主题色，null 时使用默认次要文字色。
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final FontWeight fontWeight;

  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.borderRadius = 8,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: effectiveColor,
              fontWeight: fontWeight,
            ),
          ),
        ],
      ),
    );
  }
}
