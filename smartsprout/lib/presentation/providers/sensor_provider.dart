import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sensor_model.dart';

final sensorDataProvider = NotifierProvider<SensorDataNotifier, SensorData>(() {
  return SensorDataNotifier();
});

class SensorDataNotifier extends Notifier<SensorData> {
  @override
  SensorData build() {
    return const SensorData(
      soilMoisture: 45.0, // Mock initial state
      temperature: 28.5,
      humidity: 65.0,
      tankLevel: 75.0,
      flowRate: 2.5,
    );
  }

  void updateSoilMoisture(double value) {
    state = state.copyWith(soilMoisture: value);
  }

  void updateTemperature(double value) {
    state = state.copyWith(temperature: value);
  }

  void updateHumidity(double value) {
    state = state.copyWith(humidity: value);
  }

  void updateTankLevel(double value) {
    state = state.copyWith(tankLevel: value);
  }

  void updateFlowRate(double value) {
    state = state.copyWith(flowRate: value);
  }

  // For demo testing
  void simulateRandomChanges() {
    // A function to mimic live data from MQTT/BLE without needing a device connected right now
  }
}
