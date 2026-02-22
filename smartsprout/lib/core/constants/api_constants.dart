class ApiConstants {
  static const String mqttBrokerAddress =
      "test.mosquitto.org"; // replace with actual
  static const int mqttBrokerPort = 1883;

  static const String topicSoilMoisture =
      "smart-sprout/{device_id}/sensors/soil";
  static const String topicTemperature =
      "smart-sprout/{device_id}/sensors/temp";
  static const String topicHumidity =
      "smart-sprout/{device_id}/sensors/humidity";
  static const String topicTankLevel = "smart-sprout/{device_id}/sensors/tank";
  static const String topicFlowRate = "smart-sprout/{device_id}/sensors/flow";

  static const String topicPumpControl =
      "smart-sprout/{device_id}/control/pump";
  static const String topicConfigThresholds =
      "smart-sprout/{device_id}/config/thresholds";
}
