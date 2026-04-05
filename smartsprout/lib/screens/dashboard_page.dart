import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/utils/platform_utils.dart';
import '../presentation/providers/sensor_provider.dart';
import '../widgets/zone_card.dart';
import 'system_health_page.dart';

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

  bool _showFaultOverlay = false;
  bool _wasFault = false;

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
    final triggers = ref.watch(triggerSettingsProvider);

    final rawSoil = sensorData.soilMoistureRaw;
    final startThresholds = triggers
        .startThreshold; // locally persisted — updates immediately on SET
    final targets = triggers.targetMoisture; // locally persisted
    final tankLevelStr = sensorData.tankLevel;
    final temperature = sensorData.temperature;
    final humidity = sensorData.humidity;
    // On Linux (Pi), never show as offline — the Pi IS the system.
    final isOffline = Platform.isLinux ? false : sensorData.isOffline;
    final hasFault = sensorData.hasSensorFault;
    final isEnvFault = sensorData.isEnvFault;
    final isTankLow = sensorData.isTankLow;
    final isHeartbeatStale =
        !Platform.isLinux && sensorData.isControllerDisconnected;

    if (isOffline && !_wasOffline) {
      _showConnectionOverlay = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showConnectionOverlay = false);
      });
    }
    if (!isOffline && _wasOffline) {
      _showConnectionOverlay = false;
    }
    _wasOffline = isOffline;

    if (isTankLow && !_wasTankLow) {
      _showTankLowOverlay = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showTankLowOverlay = false);
      });
    }
    if (!isTankLow && _wasTankLow) {
      _showTankLowOverlay = false;
    }
    _wasTankLow = isTankLow;

    if (hasFault && !_wasFault) {
      _showFaultOverlay = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showFaultOverlay = false);
      });
    }
    if (!hasFault && _wasFault) {
      _showFaultOverlay = false;
    }
    _wasFault = hasFault;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── Gradient & Lively Animated Flowing Background ──
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF0F172A), const Color(0xFF064E3B)]
                      : [const Color(0xFFF0FDF4), const Color(0xFFCCFBF1)],
                ),
              ),
            ),
          ),

          // Animated Background Blobs for depth and smart gardening vibe
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = _pulseController.value;
              return Stack(
                children: [
                  _buildBlob(
                      top: -100,
                      right: -100,
                      size: 400 * scale,
                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.35)),
                  _buildBlob(
                      bottom: 50,
                      left: -150,
                      size: 500 * (1.6 - scale),
                      color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.2 : 0.25)),
                  _buildBlob(
                      top: MediaQuery.of(context).size.height * 0.35,
                      left: MediaQuery.of(context).size.width * 0.2,
                      size: 300 * scale,
                      color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.1 : 0.15)),
                ],
              );
            },
          ),

          // ── Main dashboard content ──
          // Windows: wrap in Scrollbar for mouse/keyboard UX
          SafeArea(
            child: Platform.isWindows
                ? Scrollbar(
                    thumbVisibility: true,
                    child: _buildMainList(
                        tankLevelStr,
                        temperature,
                        humidity,
                        rawSoil,
                        startThresholds,
                        targets,
                        isOffline,
                        isTankLow,
                        hasFault,
                        isEnvFault,
                        sensorData),
                  )
                : _buildMainList(
                    tankLevelStr,
                    temperature,
                    humidity,
                    rawSoil,
                    startThresholds,
                    targets,
                    isOffline,
                    isTankLow,
                    hasFault,
                    isEnvFault,
                    sensorData),
          ),

          // ── Status Overlays ──
          if (_showConnectionOverlay)
            _buildStatusOverlay(
              icon: Icons.wifi_off_rounded,
              title: "Connection Lost",
              subtitle:
                  "Smart Sprout controller unreachable.\nCheck your Wi-Fi settings.",
              color: const Color(0xFF4A6164),
            ),

          if ((_showTankLowOverlay || _showFaultOverlay) && !isOffline)
            _buildStatusOverlay(
              icon: Icons.warning_amber_rounded,
              title: "Issues Detected",
              subtitle:
                  "System issues have been detected.\nCheck the System Health page for verification.",
              color: Colors.orange,
            ),

          // ── Heartbeat Disconnected Warning ──
          if (isHeartbeatStale && !isOffline)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Controller Disconnected',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainList(
      String tankLevelStr,
      double temperature,
      double humidity,
      List<double> rawSoil,
      List<double> startThresholds,
      List<double> targets,
      bool isOffline,
      bool isTankLow,
      bool hasFault,
      bool isEnvFault,
      dynamic sensorData) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        _buildAnimatedWidget(
            0, _buildTopHeader(isOffline, isTankLow, hasFault)),
        const SizedBox(height: 10),
        _buildAnimatedWidget(
            1, _buildVitals(tankLevelStr, temperature, humidity, isEnvFault)),
        const SizedBox(height: 30),
        _buildAnimatedWidget(
            2,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("System Overview",
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF0F2027),
                      letterSpacing: -0.5,
                    )),
              ],
            )),
        const SizedBox(height: 15),
        _buildAnimatedWidget(
            3,
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
              childAspectRatio: 0.9,
              children: [
                ZoneCard(
                  zoneId: '1',
                  zoneName: "Zone 1 (Left)",
                  rawMoisture: rawSoil.isNotEmpty ? rawSoil[0].toInt() : 0,
                  calibratedValue:
                      startThresholds.isNotEmpty ? startThresholds[0] : 0.0,
                  targetMoisture: targets.isNotEmpty ? targets[0] : 65.0,
                  temp: temperature.toInt(),
                  pulseAnim: _pulseController,
                  isFault: sensorData.hasBedFault(0),
                ),
                ZoneCard(
                  zoneId: '2',
                  zoneName: "Zone 2 (Center)",
                  rawMoisture: rawSoil.length > 1 ? rawSoil[1].toInt() : 0,
                  calibratedValue:
                      startThresholds.length > 1 ? startThresholds[1] : 0.0,
                  targetMoisture: targets.length > 1 ? targets[1] : 65.0,
                  temp: temperature.toInt(),
                  pulseAnim: _pulseController,
                  isFault: sensorData.hasBedFault(1),
                ),
                ZoneCard(
                  zoneId: '3',
                  zoneName: "Zone 3 (Right)",
                  rawMoisture: rawSoil.length > 2 ? rawSoil[2].toInt() : 0,
                  calibratedValue:
                      startThresholds.length > 2 ? startThresholds[2] : 0.0,
                  targetMoisture: targets.length > 2 ? targets[2] : 65.0,
                  temp: temperature.toInt(),
                  pulseAnim: _pulseController,
                  isFault: sensorData.hasBedFault(2),
                ),
                _buildSystemOverviewCard(context, sensorData),
              ],
            )),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildBlob(
      {double? top,
      double? left,
      double? right,
      double? bottom,
      required double size,
      required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ),
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
          curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
              curve: Curves.easeOutCubic),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                      color: isDark ? Colors.white70 : const Color(0xFF4A6164),
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              Text("Smart Sprout",
                  style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      color: isDark ? Colors.white : const Color(0xFF0F2027))),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasFault) ...[
                _buildGlassIconButton(
                    icon: Icons.warning_amber_rounded, color: Colors.amber),
                const SizedBox(width: 8),
              ],
              if (isTankLow) ...[
                _buildGlassIconButton(
                    icon: Icons.water_drop_rounded, color: Colors.redAccent),
                const SizedBox(width: 8),
              ],
              isOffline
                  ? _buildGlassIconButton(
                      icon: Icons.wifi_off_rounded, color: Colors.redAccent)
                  : _buildGlassIconButton(
                      icon: Icons.wifi_rounded, color: const Color(0xFF2BCC71)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({required IconData icon, required Color color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(
            color:
                isDark ? Colors.white24 : Colors.white.withValues(alpha: 0.8),
            width: 1.5),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildVitals(String tankLevelStr, double systemTemp, double systemHum,
      bool isEnvFault) {
    // Tank logic
    Color tankColor;
    String tankLabel;
    String tankStatus;
    IconData tankIcon;
    if (tankLevelStr == 'HIGH') {
      tankColor = const Color(0xFF2BCC71);
      tankLabel = 'NORMAL';
      tankStatus = 'Level Sufficient';
      tankIcon = Icons.water_drop_rounded;
    } else if (tankLevelStr == 'LOW') {
      tankColor = Colors.redAccent;
      tankLabel = 'LOW';
      tankStatus = 'Refill Required';
      tankIcon = Icons.warning_amber_rounded;
    } else {
      tankColor = Colors.orange;
      tankLabel = 'FAULT';
      tankStatus = 'Sensor Disconnected';
      tankIcon = Icons.warning_amber_rounded;
    }

    return Row(
      children: [
        // TANK LEVEL CARD
        Expanded(
          child: Container(
            height: 140, // Match design
            decoration: BoxDecoration(
              color: tankLevelStr == 'HIGH'
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F172A).withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.9))
                  : tankColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: tankColor.withValues(
                      alpha: tankLevelStr == 'HIGH' ? 0.3 : 0.8),
                  width: 1.5),
              boxShadow: isLiteMode
                  ? null
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(
                              alpha: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? 0.2
                                  : 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 5))
                    ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: tankColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12)),
                      child:
                          Icon(Icons.waves_rounded, color: tankColor, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tankLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: tankColor,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          "TANK LEVEL",
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : const Color(0xFF4A6164),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: tankColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tankIcon, color: tankColor, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tankStatus,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: tankColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 15),

        // ENVIRONMENT CARD
        Expanded(
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [
                        const Color(0xFF0F172A).withValues(alpha: 0.95),
                        const Color(0xFF064E3B).withValues(alpha: 0.85)
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.95),
                        const Color(0xFFF0FDF4).withValues(alpha: 0.85)
                      ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white12
                      : Colors.white,
                  width: 2),
              boxShadow: isLiteMode
                  ? null
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(
                              alpha: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? 0.2
                                  : 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 5))
                    ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color:
                              const Color(0xFF29B6F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.thermostat_rounded,
                          color: Color(0xFF0277BD), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "ENVIRONMENT",
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white54
                                  : const Color(0xFF4A6164),
                            ),
                          ),
                          Text(
                            isEnvFault
                                ? "--°/--%"
                                : "${systemTemp.toStringAsFixed(1)}° / ${systemHum.toInt()}%",
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFF0F2027),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF29B6F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.thermostat_rounded,
                              color: Color(0xFF0277BD), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            isEnvFault
                                ? "--°C"
                                : "${systemTemp.toStringAsFixed(1)}°C",
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF0277BD)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2BCC71).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.air_rounded,
                              color: Color(0xFF1B8E4F), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            isEnvFault ? "--%" : "${systemHum.toInt()}%",
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF1B8E4F)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemOverviewCard(BuildContext context, sensorData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHealthy = sensorData.isHealthy;
    final isOffline = sensorData.isOffline;

    final statusColor = isOffline
        ? Colors.grey
        : (isHealthy ? const Color(0xFF2BCC71) : Colors.redAccent);
    final bgColor = isOffline
        ? (isDark ? Colors.grey.shade800 : Colors.grey.shade100)
        : (isHealthy
            ? const Color(0xFFE8F5E9).withValues(alpha: isDark ? 0.1 : 1.0)
            : const Color(0xFFFFEBEE).withValues(alpha: isDark ? 0.1 : 1.0));
    final titleColor = isOffline
        ? (isDark ? Colors.grey.shade300 : Colors.grey.shade800)
        : (isHealthy
            ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF2BCC71))
            : Colors.redAccent);

    return GestureDetector(
      onTap: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SystemHealthPage()));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0F172A)
                        .withValues(alpha: isLiteMode ? 1.0 : 0.95),
                    const Color(0xFF064E3B)
                        .withValues(alpha: isLiteMode ? 1.0 : 0.85)
                  ]
                : [
                    Colors.white.withValues(alpha: isLiteMode ? 1.0 : 0.95),
                    const Color(0xFFF0FDF4)
                        .withValues(alpha: isLiteMode ? 1.0 : 0.85),
                  ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isDark ? Colors.white12 : Colors.white, width: 2),
          boxShadow: isLiteMode
              ? null
              : [
                  BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
                ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("System Health",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F2027),
                )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4, right: 8),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOffline
                              ? "System Offline"
                              : (isHealthy
                                  ? "All Systems Go"
                                  : "Issues Detected"),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: titleColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isOffline
                              ? "Controller disconnected."
                              : (isHealthy
                                  ? "Operating normally."
                                  : "One or more sensors are offline."),
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 10,
                              color: titleColor.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  isOffline
                      ? Icons.wifi_off_rounded
                      : (isHealthy
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded),
                  color: statusColor,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOverlay(
      {required IconData icon,
      required String title,
      required String subtitle,
      required Color color}) {
    final content = Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0F172A)
                : Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: isLiteMode
                ? null
                : [
                    const BoxShadow(
                        color: Colors.black26,
                        blurRadius: 30,
                        offset: Offset(0, 10))
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 48, color: color),
              ),
              const SizedBox(height: 24),
              Text(title,
                  style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF0F2027))),
              const SizedBox(height: 12),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.grey.shade600,
                      fontSize: 14,
                      height: 1.5)),
            ],
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: isLiteMode
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: content,
            ),
    );
  }
}
