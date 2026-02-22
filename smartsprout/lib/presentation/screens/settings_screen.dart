import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                _buildSectionHeader('Sensor Thresholds', context),
                _buildListTile('Soil Moisture Threshold',
                    subtitle: 'Currently: 40%', icon: Icons.grass),
                _buildListTile('Temperature Alert',
                    subtitle: 'Currently: >35°C', icon: Icons.thermostat),
                const SizedBox(height: 8),
                _buildSectionHeader('Connectivity', context),
                _buildListTile('Wi-Fi Configuration',
                    subtitle: 'Manage Raspberry Pi network', icon: Icons.wifi),
                _buildListTile('Bluetooth Devices',
                    subtitle: 'Paired: SmartSprout-01',
                    icon: Icons.bluetooth_connected),
                const SizedBox(height: 8),
                _buildSectionHeader('System', context),
                _buildListTile('Calibration',
                    subtitle: 'Calibrate soil and tank sensors',
                    icon: Icons.tune),
                _buildListTile('Firmware Update',
                    subtitle: 'Version 1.0.4 - Up to date',
                    icon: Icons.system_update),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
      {String? subtitle, required IconData icon}) {
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
        trailing:
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        onTap: () {},
      ),
    );
  }
}
