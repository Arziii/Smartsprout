import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sensor_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── Wi-Fi State ──
  String _wifiSsid = 'Checking...';
  bool _wifiConnected = false;
  bool _wifiScanning = false;
  List<Map<String, dynamic>> _wifiNetworks = [];

  // ── System State ──
  bool _isCalibrating = false;
  String _firmwareVersion = 'Checking...';
  String _firmwarePlatform = '';
  String _firmwareUptime = '';

  StreamSubscription<Map<String, dynamic>>? _settingsSub;

  @override
  void initState() {
    super.initState();
    // Listen for settings responses from the Pi
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mqtt = ref.read(mqttServiceProvider);
      _settingsSub = mqtt.settingsStream.listen(_handleSettingsResponse);

      // Request initial status
      mqtt.requestWifiStatus();
      mqtt.requestFirmwareInfo();
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    super.dispose();
  }

  void _handleSettingsResponse(Map<String, dynamic> data) {
    final response = data['response'] as String? ?? '';

    switch (response) {
      case 'wifi_status':
        setState(() {
          _wifiSsid = data['ssid'] as String? ?? 'Not connected';
          _wifiConnected = data['connected'] as bool? ?? false;
        });
        break;

      case 'wifi_scan':
        final networks = data['networks'] as List? ?? [];
        setState(() {
          _wifiScanning = false;
          _wifiNetworks = networks
              .map<Map<String, dynamic>>((n) => Map<String, dynamic>.from(n))
              .toList();
        });
        if (_wifiNetworks.isNotEmpty) {
          _showWifiPickerDialog();
        }
        break;

      case 'wifi_connect':
        final success = data['success'] as bool? ?? false;
        final message = data['message'] as String? ?? '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? '✅ $message' : '❌ $message'),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ));
        if (success) {
          ref.read(mqttServiceProvider).requestWifiStatus();
        }
        break;

      case 'calibrate':
        setState(() => _isCalibrating = false);
        final status = data['status'] as String? ?? 'unknown';
        if (status == 'complete') {
          _showCalibrationResults(data);
        }
        break;

      case 'firmware_info':
        setState(() {
          _firmwareVersion = data['version'] as String? ?? 'Unknown';
          _firmwarePlatform = data['platform'] as String? ?? '';
          _firmwareUptime = data['uptime'] as String? ?? '';
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);
    final isConnected = !sensorData.isOffline;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Garden background
          Positioned.fill(
            child: Image.asset(
              'assets/images/dashboard_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFFF0F4EE)),
            ),
          ),
          // 60% white frosted overlay
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.60)),
          ),
          // Content
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // ── Connectivity Section ──
                _buildSectionHeader('Connectivity', context),
                _buildListTile(
                  'Wi-Fi Configuration',
                  subtitle: _wifiConnected
                      ? 'Connected: $_wifiSsid'
                      : 'Not connected',
                  icon: _wifiConnected ? Icons.wifi : Icons.wifi_off,
                  trailing: _wifiScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: isConnected
                      ? () {
                          setState(() => _wifiScanning = true);
                          ref.read(mqttServiceProvider).requestWifiScan();
                        }
                      : null,
                ),
                _buildListTile(
                  'Bluetooth Devices',
                  subtitle: isConnected
                      ? 'Paired: SmartSprout-01'
                      : 'Controller offline',
                  icon: Icons.bluetooth_connected,
                  onTap: () => _showBluetoothDialog(),
                ),
                const SizedBox(height: 8),

                // ── System Section ──
                _buildSectionHeader('System', context),
                _buildListTile(
                  'Calibration',
                  subtitle: _isCalibrating
                      ? 'Running calibration...'
                      : 'Calibrate soil and tank sensors',
                  icon: Icons.tune,
                  trailing: _isCalibrating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: isConnected && !_isCalibrating
                      ? () {
                          setState(() => _isCalibrating = true);
                          ref.read(mqttServiceProvider).requestCalibration();
                        }
                      : null,
                ),
                _buildListTile(
                  'Firmware Update',
                  subtitle: 'Version $_firmwareVersion'
                      '${_firmwarePlatform.isNotEmpty ? ' • $_firmwarePlatform' : ''}'
                      '${_firmwareUptime.isNotEmpty ? '\n$_firmwareUptime' : ''}',
                  icon: Icons.system_update,
                  onTap: () {
                    ref.read(mqttServiceProvider).requestFirmwareInfo();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Checking for firmware updates...')),
                    );
                  },
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogs ──

  void _showWifiPickerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available Networks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 12),
              ..._wifiNetworks.map((net) {
                final ssid = net['ssid'] as String? ?? 'Unknown';
                final signal = net['signal'] as int? ?? 0;
                final security = net['security'] as String? ?? 'Open';
                return ListTile(
                  leading: Icon(
                    signal > 70
                        ? Icons.wifi
                        : signal > 40
                            ? Icons.wifi_2_bar
                            : Icons.wifi_1_bar,
                    color: Colors.teal,
                  ),
                  title: Text(ssid,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$signal% • $security'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showWifiPasswordDialog(ssid);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showWifiPasswordDialog(String ssid) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Connect to $ssid'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(mqttServiceProvider)
                  .connectWifi(ssid, passwordController.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Connect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showBluetoothDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bluetooth Devices'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.bluetooth_connected, color: Colors.teal.shade600),
              title: const Text('SmartSprout-01'),
              subtitle: const Text('Connected'),
              trailing: Icon(Icons.check_circle, color: Colors.green.shade600),
            ),
            const Divider(),
            const Text(
              'To pair a new device, use the Pairing screen from the home menu.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showCalibrationResults(Map<String, dynamic> data) {
    final soilRaw = data['soil_raw'] as List? ?? [];
    final tankDist = data['tank_distance_cm'] ?? 'N/A';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Calibration Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Raw ADC Readings (averaged):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (int i = 0; i < soilRaw.length; i++)
              Text('  Zone ${i + 1}: ${soilRaw[i]}'),
            const SizedBox(height: 12),
            Text('Tank Level: $tankDist%'),
            const SizedBox(height: 12),
            const Text(
              'Use these values to adjust SOIL_SENSOR_DRY and SOIL_SENSOR_WET in your .env file.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  // ── UI Builders (unchanged aesthetics) ──

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, top: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  Widget _buildListTile(String title,
      {String? subtitle,
      required IconData icon,
      Widget? trailing,
      VoidCallback? onTap}) {
    return Card(
      elevation: 2,
      color: Colors.white.withValues(alpha: 0.90),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.teal.shade600, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
            : null,
        trailing: trailing ??
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        onTap: onTap,
      ),
    );
  }
}
