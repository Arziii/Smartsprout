class SensorData {
  final double soilMoisture;
  final double temperature;
  final double humidity;
  final double tankLevel;
  final double flowRate;

  const SensorData({
    this.soilMoisture = 0.0,
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.tankLevel = 0.0,
    this.flowRate = 0.0,
  });

  SensorData copyWith({
    double? soilMoisture,
    double? temperature,
    double? humidity,
    double? tankLevel,
    double? flowRate,
  }) {
    return SensorData(
      soilMoisture: soilMoisture ?? this.soilMoisture,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      tankLevel: tankLevel ?? this.tankLevel,
      flowRate: flowRate ?? this.flowRate,
    );
  }
}
