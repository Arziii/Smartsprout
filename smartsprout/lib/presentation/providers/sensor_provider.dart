import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sensor_model.dart';
import '../../data/services/mqtt_service.dart';

// ═══════════════════════════════════════════════════════
// MQTT Service Provider (singleton)
// ═══════════════════════════════════════════════════════
final mqttServiceProvider = Provider<MqttService>((ref) {
  // Default to Pi's local IP — update in settings or .env
  final service = MqttService(host: '192.168.1.100', port: 1883);
  ref.onDispose(() => service.dispose());
  return service;
});

// ═══════════════════════════════════════════════════════
// Connection State Provider
// ═══════════════════════════════════════════════════════
final mqttConnectionProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(mqttServiceProvider);
  return service.connectionStream;
});

// ═══════════════════════════════════════════════════════
// Live Sensor Data Provider (replaces old mock data)
// ═══════════════════════════════════════════════════════
final sensorDataProvider = NotifierProvider<SensorDataNotifier, SensorData>(() {
  return SensorDataNotifier();
});

class SensorDataNotifier extends Notifier<SensorData> {
  StreamSubscription<SensorData>? _telemetrySub;
  Timer? _timeoutTimer;

  @override
  SensorData build() {
    // Start with offline state
    final initialData = const SensorData(
      soilMoisture: [0.0, 0.0, 0.0],
      systemStatus: 'offline',
    );

    // Auto-connect to MQTT on build
    _connectAndListen();

    ref.onDispose(() {
      _telemetrySub?.cancel();
      _timeoutTimer?.cancel();
    });

    return initialData;
  }

  Future<void> _connectAndListen() async {
    final mqtt = ref.read(mqttServiceProvider);

    final connected = await mqtt.connect();
    if (connected) {
      _telemetrySub = mqtt.telemetryStream.listen((data) {
        state = data;
        _resetTimeout();
      });
      _startTimeout();
    } else {
      // Retry connection after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (state.isOffline) {
          _connectAndListen();
        }
      });
    }
  }

  /// If no telemetry received for 10 seconds, mark as offline.
  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!state.isOffline) {
        state = state.copyWith(systemStatus: 'offline');
      }
    });
  }

  void _resetTimeout() {
    _timeoutTimer?.cancel();
    _startTimeout();
  }

  /// Manually trigger a watering cycle on a specific zone.
  void forceWater(int zone, {int durationSeconds = 10}) {
    if (state.pumpLocked) return; // Respect safety lock
    final mqtt = ref.read(mqttServiceProvider);
    mqtt.forceWater(zone, durationSeconds: durationSeconds);
  }

  /// Emergency stop all watering.
  void emergencyStop() {
    final mqtt = ref.read(mqttServiceProvider);
    mqtt.emergencyStop();
  }
}
