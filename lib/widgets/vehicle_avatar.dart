import 'dart:io';

import 'package:flutter/material.dart';

/// 车辆头像：有图片时展示本地图片（加载失败回退默认图标），否则展示默认图标。
/// 供概览页头部、车辆切换弹窗、车库列表等处共用。
class VehicleAvatar extends StatelessWidget {
  final String? imagePath;
  final double size;
  final double radius;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;

  const VehicleAvatar({
    super.key,
    required this.imagePath,
    required this.size,
    required this.iconSize,
    required this.backgroundColor,
    required this.iconColor,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath != null && imagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(imagePath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefault(),
        ),
      );
    }
    return _buildDefault();
  }

  Widget _buildDefault() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.directions_car, color: iconColor, size: iconSize),
    );
  }
}
