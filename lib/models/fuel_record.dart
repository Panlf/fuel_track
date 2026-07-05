class FuelRecord {
  final String id;
  final String vehicleId;
  final DateTime date;
  final int odometer;
  final double liters;
  final double pricePerLiter;
  final double totalCost;
  final bool isFullTank;
  final String? fuelType;
  final String? station;
  final String? notes;

  FuelRecord({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.odometer,
    required this.liters,
    required this.pricePerLiter,
    double? totalCost,
    this.isFullTank = true,
    this.fuelType,
    this.station,
    this.notes,
  }) : totalCost = totalCost ?? (liters * pricePerLiter);

  double? get consumptionPer100km => null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicleId': vehicleId,
      'date': date.millisecondsSinceEpoch,
      'odometer': odometer,
      'liters': liters,
      'pricePerLiter': pricePerLiter,
      'totalCost': totalCost,
      'isFullTank': isFullTank ? 1 : 0,
      'fuelType': fuelType,
      'station': station,
      'notes': notes,
    };
  }

  factory FuelRecord.fromMap(Map<String, dynamic> map) {
    return FuelRecord(
      id: map['id'] as String,
      vehicleId: map['vehicleId'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      odometer: map['odometer'] as int,
      liters: (map['liters'] as num).toDouble(),
      pricePerLiter: (map['pricePerLiter'] as num).toDouble(),
      totalCost: (map['totalCost'] as num?)?.toDouble(),
      isFullTank: (map['isFullTank'] as int) == 1,
      fuelType: map['fuelType'] as String?,
      station: map['station'] as String?,
      notes: map['notes'] as String?,
    );
  }

  FuelRecord copyWith({
    DateTime? date,
    int? odometer,
    double? liters,
    double? pricePerLiter,
    bool? isFullTank,
    String? fuelType,
    String? station,
    String? notes,
  }) {
    return FuelRecord(
      id: id,
      vehicleId: vehicleId,
      date: date ?? this.date,
      odometer: odometer ?? this.odometer,
      liters: liters ?? this.liters,
      pricePerLiter: pricePerLiter ?? this.pricePerLiter,
      totalCost: liters != null && pricePerLiter != null
          ? liters * pricePerLiter
          : totalCost,
      isFullTank: isFullTank ?? this.isFullTank,
      fuelType: fuelType ?? this.fuelType,
      station: station ?? this.station,
      notes: notes ?? this.notes,
    );
  }
}
