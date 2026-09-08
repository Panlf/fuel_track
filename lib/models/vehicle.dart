/// 车辆实体，对应数据表 vehicles。
class Vehicle {
  final String id;
  final String name;
  final String? brand;
  final String? model;
  final int? year;
  final String? fuelType;
  final double? tankCapacity;
  final int odometer;
  final String? imagePath;
  final DateTime createdAt;

  /// [createdAt] 缺省时取当前时间。
  Vehicle({
    required this.id,
    required this.name,
    this.brand,
    this.model,
    this.year,
    this.fuelType,
    this.tankCapacity,
    this.odometer = 0,
    this.imagePath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'model': model,
      'year': year,
      'fuelType': fuelType,
      'tankCapacity': tankCapacity,
      'odometer': odometer,
      'imagePath': imagePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'] as String,
      name: map['name'] as String,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      year: map['year'] as int?,
      // SQLite 的 REAL 列可能返回 int，统一走 num 转换避免强转崩溃
      tankCapacity: (map['tankCapacity'] as num?)?.toDouble(),
      odometer: map['odometer'] as int? ?? 0,
      imagePath: map['imagePath'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
    );
  }

  Vehicle copyWith({
    String? name,
    String? brand,
    String? model,
    int? year,
    String? fuelType,
    double? tankCapacity,
    int? odometer,
    String? imagePath,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      fuelType: fuelType ?? this.fuelType,
      tankCapacity: tankCapacity ?? this.tankCapacity,
      odometer: odometer ?? this.odometer,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt,
    );
  }
}
