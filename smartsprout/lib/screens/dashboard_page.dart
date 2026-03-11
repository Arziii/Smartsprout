// FILE: lib/screens/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../presentation/providers/sensor_provider.dart';
import '../widgets/zone_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  /// Controls whether the "Connection Lost" overlay is visible.
  /// It shows when the device goes offline, then auto-hides after 3 s.
  bool _showConnectionOverlay = false;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.5,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }


  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);

    // Extract live data (with safe fallbacks)
    final soil = sensorData.soilMoisture;
    final tankLevel = sensorData.tankLevel.clamp(0.0, 100.0).toInt();
    final flowRate = sensorData.flowRate;
    final temperature = sensorData.temperature;
    final isOffline = sensorData.isOffline;
    final hasFault = sensorData.hasSensorFault;
    final isTankLow = sensorData.isTankLow;

    // Show overlay when transitioning to offline, auto-hide after 3 s
    if (isOffline && !_wasOffline) {
      _showConnectionOverlay = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showConnectionOverlay = false);
      });
    }
    // If back online, reset state
    if (!isOffline && _wasOffline) {
      _showConnectionOverlay = false;
    }
    _wasOffline = isOffline;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // ── Gradient Background ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFD1E3DF),
                    Color(0xFF8BAEAA),
                  ],
                ),
              ),
            ),
          ),
          // ── Main dashboard content ──
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                _buildTopHeader(isOffline),
                _buildVitals(tankLevel, flowRate),
                const SizedBox(height: 25),
                Text("All Feature",
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F2027),
                      letterSpacing: 0.5,
                    )),
                const SizedBox(height: 15),
                // Zone Cards Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  childAspectRatio: 0.85,
                  children: [
                    ZoneCard(
                      zoneName: "Zone 1 (Left)",
                      moisture: soil.isNotEmpty ? soil[0].toInt() : 0,
                      temp: temperature.toInt(),
                      pulseAnim: _pulseController,
                    ),
                    ZoneCard(
                      zoneName: "Zone 2 (Center)",
                      moisture: soil.length > 1 ? soil[1].toInt() : 0,
                      temp: temperature.toInt(),
                      pulseAnim: _pulseController,
                    ),
                    ZoneCard(
                      zoneName: "Zone 3 (Right)",
                      moisture: soil.length > 2 ? soil[2].toInt() : 0,
                      temp: temperature.toInt(),
                      pulseAnim: _pulseController,
                    ),
                    _buildSystemOverviewCard(sensorData),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),

          // ── "Connection Lost" Overlay (auto-hides after 3 s) ──
          if (_showConnectionOverlay)
            _buildStatusOverlay(
              icon: Icons.wifi_off,
              title: "Connection Lost",
              subtitle:
                  "Cannot reach the Smart Sprout controller.\nEnsure you are on the same Wi-Fi network.",
              color: const Color(0xFF4A6164),
            ),

          // ── "Tank Empty" Overlay ──
          if (isTankLow && !isOffline)
            _buildStatusOverlay(
              icon: Icons.water_drop_outlined,
              title: "Tank Level Critical",
              subtitle:
                  "Water reservoir is below 10%.\nPump is locked for safety.",
              color: Colors.redAccent,
            ),

          // ── "Sensor Fault" Banner ──
          if (hasFault && !isOffline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              right: 20,
              child: Material(
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.amber.shade800, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Sensor fault detected — some readings may be inaccurate.",
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusOverlay({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: color),
                const SizedBox(height: 20),
                Text(title,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    )),
                const SizedBox(height: 12),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF4A6164),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isOffline) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Good Morning,",
                style: TextStyle(
                    color: const Color(0xFF4A6164),
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text("Smart Sprout",
                style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: const Color(0xFF0F2027))),
          ],
        ),
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isOffline ? Colors.red.shade50 : Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isOffline ? Icons.wifi_off : Icons.mode_night,
            color: isOffline ? Colors.redAccent : const Color(0xFF2C3E50),
            size: 28,
          ),
        )
      ],
    );
  }

  Widget _buildVitals(int tankLevel, double flowRate) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildVitalItem(
                label: "TANK LEVEL",
                value: "$tankLevel%",
                icon: Icons.waves,
                iconColor: tankLevel < 15 ? Colors.redAccent : Colors.blue,
                isTank: true,
                tankLevel: tankLevel.toDouble(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildVitalItem(
                label: "WATER FLOW",
                value: flowRate.toStringAsFixed(1),
                unit: "L/m",
                icon: Icons.water,
                iconColor: Colors.cyan,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVitalItem({
    required String label,
    required String value,
    String? unit,
    required IconData icon,
    required Color iconColor,
    bool isTank = false,
    double tankLevel = 0,
  }) {
    return AspectRatio(
      aspectRatio: 0.9,
      child: Container(
        decoration: BoxDecoration(
            color: const Color(0xFFF3F7F6),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ]),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            if (isTank)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 40 + (tankLevel / 100) * 10,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.blue.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                    ),
                    border: Border(
                        bottom: BorderSide(
                            color: Colors.blue.withValues(alpha: 0.3),
                            width: 1.5)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value,
                          style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F2027))),
                      if (unit != null)
                        Text(" $unit",
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F2027))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Color(0xFF4A6164))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemOverviewCard(sensorData) {
    final isHealthy = sensorData.isHealthy;
    final statusText = isHealthy
        ? "All systems nominal"
        : sensorData.isOffline
            ? "Controller offline"
            : sensorData.isTankLow
                ? "Tank critically low"
                : "Sensor fault detected";

    final statusColor = isHealthy
        ? const Color(0xFF2BCC71)
        : sensorData.isOffline
            ? Colors.grey
            : Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("System\nHealth",
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E1E1E),
                height: 1.2,
              )),
          const SizedBox(height: 8),
          Text(statusText,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isHealthy ? Icons.check : Icons.warning_amber_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          )
        ],
      ),
    );
  }
}
