import 'package:cloud_firestore/cloud_firestore.dart';

class SensorData {
  final List<double> soilMoisture; // 3 zones (calibrated = raw + offset)
  final List<double> soilMoistureRaw; // 3 zones (raw sensor, before offset)
  final List<double> soilOffsets; // 3 zone offsets
  final List<double> startThreshold; // 3 zone start thresholds (start pump)
  final List<double> targetMoisture; // 3 zone saturation targets (stop pump)
  final List<int> maxPumpRuntime; // 3 zone safety timeouts (seconds)
  final double temperature;
  final double humidity;
  final String tankLevel;
  final double flowRate;
  final bool pumpLocked;
  final List<bool> pumpStatus; // Per-zone pump active state confirmed by Pi
  final String systemStatus; // 'ok', 'sensor_fault', 'tank_low', 'offline'
  final Map<String, String>
      hardwareStatus; // explicit fault flags e.g. {'bed1': 'ok', 'environment': 'fault'}
  final List<String> alerts;
  final int timestamp;
  final DateTime? lastHeartbeat;

  const SensorData({
    this.soilMoisture = const [0.0, 0.0, 0.0],
    this.soilMoistureRaw = const [0.0, 0.0, 0.0],
    this.soilOffsets = const [0.0, 0.0, 0.0],
    this.startThreshold = const [50.0, 50.0, 50.0],
    this.targetMoisture = const [65.0, 65.0, 65.0],
    this.maxPumpRuntime = const [30, 30, 30],
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.tankLevel = 'FAULT',
    this.flowRate = 0.0,
    this.pumpLocked = false,
    this.pumpStatus = const [false, false, false],
    this.systemStatus = 'offline',
    this.hardwareStatus = const {},
    this.alerts = const [],
    this.timestamp = 0,
    this.lastHeartbeat,
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

    // Parse raw sensor moisture — preserve -1 sentinel (disconnected sensor)
    final soilRawJson = json['soil_moisture_raw'];
    List<double> rawSoil = [-1.0, -1.0, -1.0];
    if (soilRawJson is List) {
      rawSoil = soilRawJson.map<double>((e) => (e as num).toDouble()).toList();
    } else if (soilRawJson is Map) {
      rawSoil = [
        (soilRawJson['bed1'] as num?)?.toDouble() ?? -1.0,
        (soilRawJson['bed2'] as num?)?.toDouble() ?? -1.0,
        (soilRawJson['bed3'] as num?)?.toDouble() ?? -1.0,
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

    final hwStatusRaw = json['hardware_status'];
    Map<String, String> hwStatus = {};
    if (hwStatusRaw is Map) {
      hwStatusRaw.forEach((key, value) {
        hwStatus[key.toString()] = value.toString();
      });
    }

    // Parse last_heartbeat from Firestore
    DateTime? heartbeat;
    final hbRaw = json['last_heartbeat'];
    if (hbRaw is Timestamp) {
      heartbeat = hbRaw.toDate();
    } else if (hbRaw is DateTime) {
      heartbeat = hbRaw;
    } else if (hbRaw is Map && hbRaw['_seconds'] != null) {
      heartbeat = DateTime.fromMillisecondsSinceEpoch(
        (hbRaw['_seconds'] as int) * 1000,
      );
    } else if (hbRaw is int) {
      heartbeat = DateTime.fromMillisecondsSinceEpoch(hbRaw * 1000);
    }

    // Parse target moisture per zone
    final targetJson = json['target_moisture'];
    List<double> targets = [65.0, 65.0, 65.0];
    if (targetJson is Map) {
      targets = [
        (targetJson['bed1'] as num?)?.toDouble() ?? 65.0,
        (targetJson['bed2'] as num?)?.toDouble() ?? 65.0,
        (targetJson['bed3'] as num?)?.toDouble() ?? 65.0,
      ];
    }

    // Parse max pump runtime per zone
    final runtimeJson = json['max_pump_runtime'];
    List<int> runtimes = [30, 30, 30];
    if (runtimeJson is Map) {
      runtimes = [
        (runtimeJson['bed1'] as num?)?.toInt() ?? 30,
        (runtimeJson['bed2'] as num?)?.toInt() ?? 30,
        (runtimeJson['bed3'] as num?)?.toInt() ?? 30,
      ];
    }
    // Parse start thresholds per zone
    final startJson = json['start_threshold'];
    List<double> starts = [
      targets[0] - 15.0,
      targets[1] - 15.0,
      targets[2] - 15.0
    ];
    if (startJson is Map) {
      starts = [
        (startJson['bed1'] as num?)?.toDouble() ?? (targets[0] - 15.0),
        (startJson['bed2'] as num?)?.toDouble() ?? (targets[1] - 15.0),
        (startJson['bed3'] as num?)?.toDouble() ?? (targets[2] - 15.0),
      ];
    }

    return SensorData(
      soilMoisture: soil,
      soilMoistureRaw: List.from(rawSoil),
      soilOffsets: List.from(offsets),
      startThreshold: List.from(starts),
      targetMoisture: List.from(targets),
      maxPumpRuntime: List.from(runtimes),
      temperature: (json['temperature'] as num?)?.toDouble() ?? -1.0,
      humidity: (json['humidity'] as num?)?.toDouble() ?? -1.0,
      tankLevel: json['tank_level']?.toString() ?? 'FAULT',
      flowRate: (json['flow_rate'] as num?)?.toDouble() ?? 0.0,
      pumpLocked: json['pump_locked'] as bool? ?? false,
      pumpStatus: [
        json['pump_status_zone1'] as bool? ?? false,
        json['pump_status_zone2'] as bool? ?? false,
        json['pump_status_zone3'] as bool? ?? false,
      ],
      systemStatus: json['system_status'] as String? ?? 'offline',
      hardwareStatus: hwStatus,
      alerts: alerts,
      timestamp: json['timestamp'] as int? ?? 0,
      lastHeartbeat: heartbeat,
    );
  }

  bool get hasSensorFault =>
      systemStatus == 'sensor_fault' ||
      alerts.contains('soil_sensor_fault') ||
      alerts.contains('dht22_fault') ||
      alerts.contains('environment_sensor_fault') ||
      isTankFault;
  bool get isTankLow =>
      systemStatus == 'tank_low' ||
      alerts.contains('tank_empty') ||
      tankLevel == 'LOW';
  bool get isOffline => systemStatus == 'offline' || isControllerDisconnected;
  bool get isHealthy => !hasSensorFault && !isTankLow && !isOffline;

  bool get isEnvFault => hardwareStatus['environment'] == 'fault';

  /// Returns true if the bed has a hardware fault flag OR its raw sensor reads
  /// the -1 sentinel (disconnected / open-circuit sensor).
  bool hasBedFault(int index) {
    final hwFault = hardwareStatus['bed${index + 1}'] == 'fault';
    final rawFault =
        index < soilMoistureRaw.length && soilMoistureRaw[index] < 0;
    return hwFault || rawFault;
  }

  bool get isTankFault =>
      hardwareStatus['tank'] == 'fault' || tankLevel == 'FAULT';

  bool get isControllerDisconnected {
    if (lastHeartbeat == null) return true;
    return DateTime.now().difference(lastHeartbeat!).inMinutes > 2;
  }

  SensorData copyWith({
    List<double>? soilMoisture,
    List<double>? soilMoistureRaw,
    List<double>? soilOffsets,
    List<double>? startThreshold,
    List<double>? targetMoisture,
    List<int>? maxPumpRuntime,
    double? temperature,
    double? humidity,
    String? tankLevel,
    double? flowRate,
    bool? pumpLocked,
    List<bool>? pumpStatus,
    String? systemStatus,
    Map<String, String>? hardwareStatus,
    List<String>? alerts,
    int? timestamp,
    DateTime? lastHeartbeat,
  }) {
    return SensorData(
      soilMoisture: soilMoisture ?? this.soilMoisture,
      soilMoistureRaw: soilMoistureRaw ?? this.soilMoistureRaw,
      soilOffsets: soilOffsets ?? this.soilOffsets,
      startThreshold: startThreshold ?? this.startThreshold,
      targetMoisture: targetMoisture ?? this.targetMoisture,
      maxPumpRuntime: maxPumpRuntime ?? this.maxPumpRuntime,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      tankLevel: tankLevel ?? this.tankLevel,
      flowRate: flowRate ?? this.flowRate,
      pumpLocked: pumpLocked ?? this.pumpLocked,
      pumpStatus: pumpStatus ?? this.pumpStatus,
      systemStatus: systemStatus ?? this.systemStatus,
      hardwareStatus: hardwareStatus ?? this.hardwareStatus,
      alerts: alerts ?? this.alerts,
      timestamp: timestamp ?? this.timestamp,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    );
  }
}
