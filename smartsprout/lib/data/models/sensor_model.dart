class SensorData {
  final List<double> soilMoisture; // 3 zones
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
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.tankLevel = 0.0,
    this.flowRate = 0.0,
    this.pumpLocked = false,
    this.systemStatus = 'offline',
    this.alerts = const [],
    this.timestamp = 0,
  });

  /// Create SensorData from the MQTT JSON telemetry payload.
  factory SensorData.fromMqttJson(Map<String, dynamic> json) {
    final soilRaw = json['soil_moisture'];
    List<double> soil = [0.0, 0.0, 0.0];
    if (soilRaw is List) {
      soil = soilRaw.map<double>((e) => (e as num).toDouble()).toList();
    }

    final alertsRaw = json['alerts'];
    List<String> alerts = [];
    if (alertsRaw is List) {
      alerts = alertsRaw.map<String>((e) => e.toString()).toList();
    }

    return SensorData(
      soilMoisture: soil,
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

  bool get hasSensorFault => systemStatus == 'sensor_fault';
  bool get isTankLow => systemStatus == 'tank_low';
  bool get isOffline => systemStatus == 'offline';
  bool get isHealthy => systemStatus == 'ok';

  SensorData copyWith({
    List<double>? soilMoisture,
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
