class FuelStats {
  final double avgConsumption;
  final double totalCost;
  final double totalLiters;
  final double totalDistance;
  final double avgPricePerLiter;
  final double? bestConsumption;
  final double? worstConsumption;

  FuelStats({
    required this.avgConsumption,
    required this.totalCost,
    required this.totalLiters,
    required this.totalDistance,
    required this.avgPricePerLiter,
    this.bestConsumption,
    this.worstConsumption,
  });
}
