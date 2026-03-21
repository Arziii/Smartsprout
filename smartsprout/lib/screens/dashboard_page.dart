import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../presentation/providers/sensor_provider.dart';
import '../widgets/zone_card.dart';
import '../widgets/water_wave.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _entranceController;

  bool _showConnectionOverlay = false;
  bool _wasOffline = false;
  
  bool _showTankLowOverlay = false;
  bool _wasTankLow = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.6,
      upperBound: 1.0,
    )..repeat(reverse: true);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);

    final rawSoil = sensorData.soilMoistureRaw;
    final offsets = sensorData.soilOffsets;
    final tankLevel = sensorData.tankLevel.clamp(0.0, 100.0).toDouble();
    final temperature = sensorData.temperature;
    // On Linux (Pi), never show as offline — the Pi IS the system.
    final isOffline = Platform.isLinux ? false : sensorData.isOffline;
    final hasFault = sensorData.hasSensorFault;
    final isTankLow = sensorData.isTankLow;

    if (isOffline && !_wasOffline) {
      _showConnectionOverlay = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showConnectionOverlay = false);
      });
    }
    if (!isOffline && _wasOffline) {
      _showConnectionOverlay = false;
    }
    _wasOffline = isOffline;

    if (isTankLow && !_wasTankLow) {
      _showTankLowOverlay = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showTankLowOverlay = false);
      });
    }
    if (!isTankLow && _wasTankLow) {
      _showTankLowOverlay = false;
    }
    _wasTankLow = isTankLow;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // ── Gradient & Blob Background ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE0ECE9),
                    Color(0xFFB4CDCA),
                  ],
                ),
              ),
            ),
          ),
          
          // Background Blobs for depth
          _buildBlob(top: -100, right: -50, size: 300, color: const Color(0xFF2BCC71).withOpacity(0.15)),
          _buildBlob(bottom: 100, left: -100, size: 400, color: Colors.blue.withOpacity(0.1)),
          
          // ── Main dashboard content ──
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                _buildAnimatedWidget(0, _buildTopHeader(isOffline, isTankLow, hasFault)),
                const SizedBox(height: 10),
                _buildAnimatedWidget(1, _buildVitals(tankLevel, temperature)),
                const SizedBox(height: 30),
                _buildAnimatedWidget(2, Text("System Overview",
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F2027),
                      letterSpacing: -0.5,
                    ))),
                const SizedBox(height: 15),
                // Feature Cards Grid
                _buildAnimatedWidget(3, GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.9,
                  children: [
                    ZoneCard(
                      zoneName: "Zone 1 (Left)",
                      rawMoisture: rawSoil.isNotEmpty ? rawSoil[0].toInt() : 0,
                      calibratedValue: offsets.isNotEmpty ? offsets[0] : 0.0,
                      temp: temperature.toInt(),
                      pulseAnim: _pulseController,
                    ),
                    ZoneCard(
                      zoneName: "Zone 2 (Center)",
                      rawMoisture: rawSoil.length > 1 ? rawSoil[1].toInt() : 0,
                      calibratedValue: offsets.length > 1 ? offsets[1] : 0.0,
                      temp: temperature.toInt(),
                      pulseAnim: _pulseController,
                    ),
                    ZoneCard(
                      zoneName: "Zone 3 (Right)",
                      rawMoisture: rawSoil.length > 2 ? rawSoil[2].toInt() : 0,
                      calibratedValue: offsets.length > 2 ? offsets[2] : 0.0,
                      temp: temperature.toInt(),
                      pulseAnim: _pulseController,
                    ),
                    _buildSystemOverviewCard(sensorData),
                  ],
                )),
                const SizedBox(height: 100),
              ],
            ),
          ),

          // ── Status Overlays ──
          if (_showConnectionOverlay)
            _buildStatusOverlay(
              icon: Icons.wifi_off_rounded,
              title: "Connection Lost",
              subtitle: "Smart Sprout controller unreachable.\nCheck your Wi-Fi settings.",
              color: const Color(0xFF4A6164),
            ),

          if (_showTankLowOverlay && !isOffline)
            _buildStatusOverlay(
              icon: Icons.water_drop_rounded,
              title: "Low Water Level",
              subtitle: "Water reservoir is below 10%.\nPump protection active.",
              color: Colors.redAccent,
            ),
        ],
      ),
    );
  }

  Widget _buildBlob({double? top, double? left, double? right, double? bottom, required double size, required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Platform.isLinux 
            ? null 
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(color: Colors.transparent),
              ),
      ),
    );
  }

  Widget _buildAnimatedWidget(int index, Widget child) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        final start = 0.1 * index;
        final end = start + 0.5;
        final curve = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0), curve: Curves.easeOutCubic),
        );
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - curve.value)),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(bool isOffline, bool isTankLow, bool hasFault) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Good Morning,",
                  style: GoogleFonts.outfit(
                      color: const Color(0xFF4A6164),
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              Text("Smart Sprout",
                  style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      color: const Color(0xFF0F2027))),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFault) ...[
                _buildGlassIconButton(icon: Icons.warning_amber_rounded, color: Colors.amber),
                const SizedBox(width: 8),
              ],
              if (isTankLow) ...[
                _buildGlassIconButton(icon: Icons.water_drop_rounded, color: Colors.redAccent),
                const SizedBox(width: 8),
              ],
              isOffline
                  ? _buildGlassIconButton(icon: Icons.wifi_off_rounded, color: Colors.redAccent)
                  : _buildGlassIconButton(icon: Icons.wifi_rounded, color: const Color(0xFF2BCC71)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({required IconData icon, required Color color}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildVitals(double tankLevel, double systemTemp) {
    return Row(
      children: [
        Expanded(
          child: _buildVitalCard(
            label: "TANK LEVEL",
            value: "${tankLevel.toInt()}%",
            icon: Icons.waves_rounded,
            color: tankLevel < 20 ? Colors.redAccent : const Color(0xFF29B6F6),
            isTank: true,
            level: tankLevel,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildVitalCard(
            label: "TEMPERATURE",
            value: systemTemp.toStringAsFixed(1),
            unit: "°C",
            icon: Icons.thermostat_rounded,
            color: const Color(0xFFFF7043),
          ),
        ),
      ],
    );
  }

  Widget _buildVitalCard({
    required String label,
    required String value,
    String? unit,
    required IconData icon,
    required Color color,
    bool isTank = false,
    double level = 0,
  }) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(Platform.isLinux ? 1.0 : 0.8),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: Platform.isLinux ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          if (isTank)
            Positioned.fill(
              child: WaterWave(value: level, color: color.withOpacity(0.15)),
            ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1.0),
                  duration: const Duration(seconds: 1),
                  builder: (context, val, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: value,
                                style: GoogleFonts.outfit(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0F2027),
                                ),
                              ),
                              if (unit != null)
                                TextSpan(
                                  text: " $unit",
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF4A6164),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(label,
                            style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: const Color(0xFF4A6164).withOpacity(0.8))),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemOverviewCard(sensorData) {
    final isHealthy = sensorData.isHealthy;
    final statusColor = isHealthy ? const Color(0xFF2BCC71) : Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(Platform.isLinux ? 1.0 : 0.8),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("System\nHealth",
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F2027),
                height: 1.1,
              )),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: statusColor.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)
                  ]
                ),
              ),
              Icon(
                isHealthy ? Icons.verified_rounded : Icons.report_problem_rounded,
                color: statusColor,
                size: 24,
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatusOverlay({required IconData icon, required String title, required String subtitle, required Color color}) {
    final content = Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: Platform.isLinux ? null : [BoxShadow(color: Colors.black26, blurRadius: 30, offset: const Offset(0, 10))],
          ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(icon, size: 48, color: color),
                  ),
                  const SizedBox(height: 24),
                  Text(title, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                  const SizedBox(height: 12),
                  Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5)),
                ],
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: Platform.isLinux 
          ? content 
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: content,
            ),
    );
  }
}
