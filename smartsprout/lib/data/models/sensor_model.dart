class SensorData {
  final List<double> soilMoisture;    // 3 zones (calibrated = raw + offset)
  final List<double> soilMoistureRaw; // 3 zones (raw sensor, before offset)
  final List<double> soilOffsets;     // 3 zone offsets
  final double temperature;
  final double humidity;
  final double tankLevel;
  final double flowRate;
  final bool pumpLocked;
  final String systemStatus; // 'ok', 'sensor_fault', 'tank_low', 'offline'
  final List<String> alerts;
  final int timestamp;

  const SensorData({
    this.soilMoisture = const [0.0, 0.0, 0.0],
    this.soilMoistureRaw = const [0.0, 0.0, 0.0],
    this.soilOffsets = const [0.0, 0.0, 0.0],
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.tankLevel = 0.0,
    this.flowRate = 0.0,
    this.pumpLocked = false,
    this.systemStatus = 'offline',
    this.alerts = const [],
    this.timestamp = 0,
  });

  /// Create SensorData from the Firebase JSON telemetry payload.
  factory SensorData.fromJson(Map<String, dynamic> json) {
    final soilCalJson = json['soil_moisture'];
    List<double> soil = [0.0, 0.0, 0.0];
    if (soilCalJson is List) {
      soil = soilCalJson.map<double>((e) => (e as num).toDouble()).toList();
    } else if (soilCalJson is Map) {
      soil = [
        (soilCalJson['bed1'] as num?)?.toDouble() ?? 0.0,
        (soilCalJson['bed2'] as num?)?.toDouble() ?? 0.0,
        (soilCalJson['bed3'] as num?)?.toDouble() ?? 0.0,
      ];
    }

    // Parse raw sensor moisture (before offsets)
    final soilRawJson = json['soil_moisture_raw'];
    List<double> rawSoil = [0.0, 0.0, 0.0];
    if (soilRawJson is List) {
      rawSoil = soilRawJson.map<double>((e) => (e as num).toDouble()).toList();
    } else if (soilRawJson is Map) {
      rawSoil = [
        (soilRawJson['bed1'] as num?)?.toDouble() ?? 0.0,
        (soilRawJson['bed2'] as num?)?.toDouble() ?? 0.0,
        (soilRawJson['bed3'] as num?)?.toDouble() ?? 0.0,
      ];
    }

    final offsetsRaw = json['soil_offsets'];
    List<double> offsets = [0.0, 0.0, 0.0];
    if (offsetsRaw is List) {
      offsets = offsetsRaw.map<double>((e) => (e as num).toDouble()).toList();
    } else if (offsetsRaw is Map) {
      offsets = [
        (offsetsRaw['bed1'] as num?)?.toDouble() ?? 0.0,
        (offsetsRaw['bed2'] as num?)?.toDouble() ?? 0.0,
        (offsetsRaw['bed3'] as num?)?.toDouble() ?? 0.0,
      ];
    }

    final alertsRaw = json['alerts'];
    List<String> alerts = [];
    if (alertsRaw is List) {
      alerts = alertsRaw.map<String>((e) => e.toString()).toList();
    }

    return SensorData(
      soilMoisture: soil,
      soilMoistureRaw: rawSoil,
      soilOffsets: offsets,
      temperature: (json['temperature'] as num?)?.toDouble() ?? -1.0,
      humidity: (json['humidity'] as num?)?.toDouble() ?? -1.0,
      tankLevel: (json['tank_level'] as num?)?.toDouble() ?? -1.0,
      flowRate: (json['flow_rate'] as num?)?.toDouble() ?? 0.0,
      pumpLocked: json['pump_locked'] as bool? ?? false,
      systemStatus: json['system_status'] as String? ?? 'offline',
      alerts: alerts,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  bool get hasSensorFault => systemStatus == 'sensor_fault' || alerts.contains('soil_sensor_fault') || alerts.contains('dht22_fault');
  bool get isTankLow => systemStatus == 'tank_low' || alerts.contains('tank_empty') || tankLevel < 20.0;
  bool get isOffline => systemStatus == 'offline';
  bool get isHealthy => !hasSensorFault && !isTankLow && !isOffline;

  SensorData copyWith({
    List<double>? soilMoisture,
    List<double>? soilMoistureRaw,
    List<double>? soilOffsets,
    double? temperature,
    double? humidity,
    double? tankLevel,
    double? flowRate,
    bool? pumpLocked,
    String? systemStatus,
    List<String>? alerts,
    int? timestamp,
  }) {
    return SensorData(
      soilMoisture: soilMoisture ?? this.soilMoisture,
      soilMoistureRaw: soilMoistureRaw ?? this.soilMoistureRaw,
      soilOffsets: soilOffsets ?? this.soilOffsets,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      tankLevel: tankLevel ?? this.tankLevel,
      flowRate: flowRate ?? this.flowRate,
      pumpLocked: pumpLocked ?? this.pumpLocked,
      systemStatus: systemStatus ?? this.systemStatus,
      alerts: alerts ?? this.alerts,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
