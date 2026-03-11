import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/sensor_model.dart';

/// Service that manages the MQTT connection to the Raspberry Pi.
/// Publishes commands and streams live sensor telemetry.
class MqttService {
  final String host;
  final int port;

  MqttServerClient? _client;
  bool _isConnected = false;

  // ── Streams ──
  final _telemetryController = StreamController<SensorData>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _alertController = StreamController<Map<String, dynamic>>.broadcast();
  final _settingsController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<SensorData> get telemetryStream => _telemetryController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get alertStream => _alertController.stream;
  Stream<Map<String, dynamic>> get settingsStream => _settingsController.stream;

  bool get isConnected => _isConnected;

  // ── MQTT Topics ──
  static const _topicTelemetry = 'smartsprout/telemetry';
  static const _topicCommand = 'smartsprout/command';
  static const _topicStatus = 'smartsprout/status';
  static const _topicAlert = 'smartsprout/alert';
  static const _topicSettings = 'smartsprout/settings';
  static const _topicSettingsCmd = 'smartsprout/settings/cmd';

  MqttService({required this.host, this.port = 1883});

  /// Connect to the local MQTT broker running on the Raspberry Pi.
  Future<bool> connect() async {
    _client = MqttServerClient.withPort(host, 'smartsprout-flutter', port);
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.resubscribeOnAutoReconnect = true;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onAutoReconnect = _onAutoReconnect;
    _client!.onAutoReconnected = _onAutoReconnected;

    final connMsg = MqttConnectMessage()
        .withClientIdentifier('smartsprout-flutter')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMsg;

    try {
      debugPrint('[MQTT] Connecting to $host:$port...');
      await _client!.connect();
    } catch (e) {
      debugPrint('[MQTT] Connection error: $e');
      _isConnected = false;
      _connectionController.add(false);
      return false;
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      debugPrint('[MQTT] Connected!');
      _isConnected = true;
      _connectionController.add(true);
      _subscribe();
      return true;
    }

    debugPrint('[MQTT] Connection failed');
    _isConnected = false;
    _connectionController.add(false);
    return false;
  }

  void _subscribe() {
    _client?.subscribe(_topicTelemetry, MqttQos.atMostOnce);
    _client?.subscribe(_topicStatus, MqttQos.atLeastOnce);
    _client?.subscribe(_topicAlert, MqttQos.atLeastOnce);
    _client?.subscribe(_topicSettings, MqttQos.atLeastOnce);

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final payload = MqttPublishPayload.bytesToStringAsString(
            (msg.payload as MqttPublishMessage).payload.message);

        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;

          if (msg.topic == _topicTelemetry) {
            final data = SensorData.fromMqttJson(json);
            _telemetryController.add(data);
          } else if (msg.topic == _topicAlert) {
            _alertController.add(json);
          } else if (msg.topic == _topicSettings) {
            _settingsController.add(json);
          } else if (msg.topic == _topicStatus) {
            final status = json['status'] as String? ?? 'offline';
            if (status == 'offline') {
              _telemetryController
                  .add(const SensorData(systemStatus: 'offline'));
            }
          }
        } catch (e) {
          debugPrint('[MQTT] Parse error: $e');
        }
      }
    });
  }

  /// Send a "Force Water" command to trigger the pump for a specific zone.
  void forceWater(int zone, {int durationSeconds = 10}) {
    _publish(_topicCommand, {
      'command': 'force_water',
      'zone': zone,
      'duration_seconds': durationSeconds,
    });
  }

  /// Send an emergency stop command.
  void emergencyStop() {
    _publish(_topicCommand, {'command': 'stop_all'});
  }

  // ── Settings System Commands ──

  /// Request a Wi-Fi network scan.
  void requestWifiScan() {
    _publish(_topicSettingsCmd, {'command': 'wifi_scan'});
  }

  /// Connect to a Wi-Fi network.
  void connectWifi(String ssid, String password) {
    _publish(_topicSettingsCmd, {
      'command': 'wifi_connect',
      'ssid': ssid,
      'password': password,
    });
  }

  /// Request current Wi-Fi status.
  void requestWifiStatus() {
    _publish(_topicSettingsCmd, {'command': 'wifi_status'});
  }

  /// Request sensor calibration.
  void requestCalibration() {
    _publish(_topicSettingsCmd, {'command': 'calibrate'});
  }

  /// Request firmware info.
  void requestFirmwareInfo() {
    _publish(_topicSettingsCmd, {'command': 'firmware_info'});
  }

  void _publish(String topic, Map<String, dynamic> payload) {
    if (!_isConnected || _client == null) {
      debugPrint('[MQTT] Cannot publish — not connected');
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _onConnected() {
    _isConnected = true;
    _connectionController.add(true);
    debugPrint('[MQTT] onConnected');
  }

  void _onDisconnected() {
    _isConnected = false;
    _connectionController.add(false);
    debugPrint('[MQTT] onDisconnected');
  }

  void _onAutoReconnect() {
    debugPrint('[MQTT] Auto-reconnecting...');
  }

  void _onAutoReconnected() {
    _isConnected = true;
    _connectionController.add(true);
    debugPrint('[MQTT] Auto-reconnected!');
  }

  /// Disconnect and release resources.
  void dispose() {
    _client?.disconnect();
    _telemetryController.close();
    _connectionController.close();
    _alertController.close();
    _settingsController.close();
  }
}
