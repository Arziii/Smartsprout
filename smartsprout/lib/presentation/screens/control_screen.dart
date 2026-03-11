import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/sensor_provider.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  String _mode = 'manual';

  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);
    final notifier = ref.read(sensorDataProvider.notifier);
    final isConnected = !sensorData.isOffline;
    final pumpLocked = sensorData.pumpLocked;

    return Scaffold(
      body: Stack(
        children: [
          // Gradient Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD1E3DF), Color(0xFF8BAEAA)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Text("Irrigation Control",
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F2027),
                      )),
                  const SizedBox(height: 8),
                  Text(
                    isConnected
                        ? "Connected to Smart Sprout"
                        : "⚠ Offline — commands will not be sent",
                    style: TextStyle(
                      color: isConnected
                          ? const Color(0xFF4A6164)
                          : Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Mode Selector Card
                  _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Operation Mode',
                            style: GoogleFonts.inter(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'manual',
                                label: Text('Manual'),
                                icon: Icon(Icons.touch_app)),
                            ButtonSegment(
                                value: 'auto',
                                label: Text('Auto'),
                                icon: Icon(Icons.schedule)),
                            ButtonSegment(
                                value: 'ml',
                                label: Text('Smart'),
                                icon: Icon(Icons.psychology)),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (sel) =>
                              setState(() => _mode = sel.first),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Per-Zone Force Water Controls
                  if (_mode == 'manual') ...[
                    _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Manual Override",
                              style: GoogleFonts.inter(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (pumpLocked)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.lock, color: Colors.redAccent),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Pump is LOCKED — tank level critically low.",
                                      style: TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          _buildZoneButton(1, "Zone 1 (Left)",
                              sensorData.soilMoisture[0], notifier,
                              disabled: pumpLocked || !isConnected),
                          const SizedBox(height: 12),
                          _buildZoneButton(
                              2,
                              "Zone 2 (Center)",
                              sensorData.soilMoisture.length > 1
                                  ? sensorData.soilMoisture[1]
                                  : 0,
                              notifier,
                              disabled: pumpLocked || !isConnected),
                          const SizedBox(height: 12),
                          _buildZoneButton(
                              3,
                              "Zone 3 (Right)",
                              sensorData.soilMoisture.length > 2
                                  ? sensorData.soilMoisture[2]
                                  : 0,
                              notifier,
                              disabled: pumpLocked || !isConnected),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Emergency Stop
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: isConnected
                          ? () {
                              HapticFeedback.heavyImpact();
                              notifier.emergencyStop();
                            }
                          : null,
                      icon: const Icon(Icons.power_settings_new, size: 24),
                      label: Text("EMERGENCY STOP",
                          style: GoogleFonts.inter(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneButton(
      int zone, String label, double moisture, SensorDataNotifier notifier,
      {bool disabled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              Text("Moisture: ${moisture.toStringAsFixed(0)}%",
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: disabled
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    notifier.forceWater(zone);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2BCC71),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text("Water Now",
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}
