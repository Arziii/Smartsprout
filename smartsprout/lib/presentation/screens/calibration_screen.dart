import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/sensor_provider.dart';
import '../../data/services/data_service.dart';

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;

  // Local optimistic watering triggers
  final Map<int, double> _localStarts = {1: 50.0, 2: 50.0, 3: 50.0};
  final Map<int, double> _localTargets = {1: 65.0, 2: 65.0, 3: 65.0};
  final Map<int, int> _localTimeouts = {1: 30, 2: 30, 3: 30};
  bool _targetsLoaded = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);
    final isConnected = Platform.isLinux || !sensorData.isOffline;
    final moistureData = sensorData.soilMoisture;

    // Initialize local sliders ONCE from the persisted triggerSettingsProvider.
    // This survives navigation — the provider is backed by SharedPreferences.
    if (!_targetsLoaded) {
      final triggers = ref.read(triggerSettingsProvider);
      for (int z = 1; z <= 3; z++) {
        _localStarts[z] = triggers.startThreshold[z - 1];
        _localTargets[z] = triggers.targetMoisture[z - 1];
        _localTimeouts[z] = triggers.maxPumpRuntime[z - 1];
      }
      _targetsLoaded = true;
    }

    // Live sensor moisture per zone
    double liveMoisture(int zoneIndex) {
      return moistureData.length > zoneIndex ? moistureData[zoneIndex] : 0.0;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text('Calibration',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027),
              letterSpacing: -0.5,
            )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027),
              size: 20),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.pushReplacement('/settings'),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            // Background Gradient
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
                  ),
                ),
              ),
            ),

            // Organic Blob shapes
            Positioned(
              top: -50,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2BCC71).withValues(alpha: 0.15),
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              left: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.1),
                ),
              ),
            ),

            SafeArea(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  _buildInfoBanner(),
                  const SizedBox(height: 25),
                  _buildSectionHeader('Watering Triggers'),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        children: [
                          for (int i = 0; i < 3; i++) ...[
                            _buildAnimatedItem(
                              i,
                              _buildCalibrationCard(
                                zone: i + 1,
                                label: i == 0
                                    ? 'LEFT BED'
                                    : i == 1
                                        ? 'CENTER BED'
                                        : 'RIGHT BED',
                                liveMoisture: liveMoisture(i),
                                offsetValue: sensorData.soilOffsets.length > i
                                    ? sensorData.soilOffsets[i]
                                    : 0.0,
                                isConnected: isConnected,
                              ),
                            ),
                            const SizedBox(height: 15),
                          ],
                        ],
                      ),
                      if (!isConnected)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                color: Colors.white.withValues(alpha: 0.6),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                        color: Color(0xFF2BCC71)),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Searching for Raspberry Pi...',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : const Color(0xFF0F2027),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _buildSectionHeader('Reference Reset'),
                  _buildAnimatedItem(
                    4,
                    _buildDryCalibrationButton(isConnected),
                  ),
                  const SizedBox(height: 12),
                  _buildAnimatedItem(
                    5,
                    _buildWetCalibrationButton(isConnected),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0F2027).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA726).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.info_outline_rounded,
                color: Color(0xFFE65100), size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              'Set the Start Threshold (pump ON), Target Saturation (pump OFF), and Safety Timeout for each zone. Tap SET TRIGGER RULES to queue the command. The Pi confirms and syncs back.',
              style: GoogleFonts.outfit(
                color: const Color(0xFF37474F),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF4A6164),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCalibrationCard({
    required int zone,
    required String label,
    required double liveMoisture,
    required double? offsetValue,
    required bool isConnected,
  }) {
    // Color based on moisture level
    Color moistureColor;
    if (liveMoisture < 25) {
      moistureColor = Colors.redAccent;
    } else if (liveMoisture < 50) {
      moistureColor = const Color(0xFFFFA726);
    } else {
      moistureColor = const Color(0xFF2BCC71);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0F2027).withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row: Label ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF0F2027),
                ),
              ),
              if (offsetValue != null && offsetValue != 0.0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF29B6F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF29B6F6).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune_rounded,
                          size: 12, color: Color(0xFF0277BD)),
                      const SizedBox(width: 4),
                      Text(
                        '${offsetValue >= 0 ? "+" : ""}${offsetValue.toStringAsFixed(1)}%',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: const Color(0xFF0277BD),
                        ),
                      ),
                    ],
                  ),
                )
            ],
          ),
          const SizedBox(height: 12),

          // ── Live Moisture Display ──
          Row(
            children: [
              Icon(Icons.water_drop_rounded, color: moistureColor, size: 20),
              const SizedBox(width: 8),
              Text(
                isConnected ? '${liveMoisture.toStringAsFixed(1)}%' : '--%',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF0F2027),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MOISTURE',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  color: const Color(0xFF4A6164).withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // ── Precision Saturation Controls ──
          _buildPrecisionControls(zone, isConnected),

          const SizedBox(height: 16),
          // SET trigger button
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isConnected ? () => _submitZoneTargets(zone) : null,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isConnected
                          ? [const Color(0xFF2BCC71), const Color(0xFF20A056)]
                          : [Colors.grey.shade300, Colors.grey.shade400],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isConnected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF2BCC71)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      'SET TRIGGER RULES',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the precision saturation controls for a zone.
  Widget _buildPrecisionControls(int zone, bool isConnected) {
    final start = _localStarts[zone] ?? 50.0;
    final target = _localTargets[zone] ?? 65.0;
    final timeout = _localTimeouts[zone] ?? 30;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F9F4),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: const Color(0xFF2BCC71).withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded,
                    size: 16, color: Color(0xFF2BCC71)),
                const SizedBox(width: 6),
                Text(
                  'AUTOMATION SETTINGS',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: const Color(0xFF4A6164),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Start Threshold Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Start Threshold (ON)',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: const Color(0xFF37474F))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2BCC71).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${start.round()}%',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: const Color(0xFF2BCC71))),
                ),
              ],
            ),
            Slider(
              value: start,
              min: 5,
              max: 95,
              divisions: 18,
              activeColor: const Color(0xFF2BCC71),
              inactiveColor: const Color(0xFF2BCC71).withValues(alpha: 0.15),
              onChanged: isConnected
                  ? (val) {
                      // Validate: Start must be AT LEAST 5% lower than Target
                      double newVal = val;
                      if (newVal > target - 5.0) {
                        newVal = target - 5.0;
                      }
                      setState(() => _localStarts[zone] = newVal);
                    }
                  : null,
            ),
            const SizedBox(height: 4),

            // Target Saturation Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Target Saturation (OFF)',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: const Color(0xFF37474F))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2BCC71).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${target.round()}%',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: const Color(0xFF2BCC71))),
                ),
              ],
            ),
            Slider(
              value: target,
              min: 10,
              max: 100,
              divisions: 18,
              activeColor: const Color(0xFF2BCC71),
              inactiveColor: const Color(0xFF2BCC71).withValues(alpha: 0.15),
              onChanged: isConnected
                  ? (val) {
                      // Validate: Target must be AT LEAST 5% higher than Start
                      double newVal = val;
                      if (newVal < start + 5.0) {
                        newVal = start + 5.0;
                      }
                      setState(() => _localTargets[zone] = newVal);
                    }
                  : null,
            ),

            const SizedBox(height: 8),

            // Safety Timeout Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Safety Timeout',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: const Color(0xFF37474F))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA726).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${timeout}s',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: const Color(0xFFE65100))),
                ),
              ],
            ),
            Slider(
              value: timeout.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              activeColor: const Color(0xFFFFA726),
              inactiveColor: const Color(0xFFFFA726).withValues(alpha: 0.15),
              onChanged: isConnected
                  ? (val) {
                      setState(() => _localTimeouts[zone] = val.round());
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _submitZoneTargets(int zone) {
    final start = _localStarts[zone] ?? 50.0;
    final target = _localTargets[zone] ?? 65.0;
    final timeout = _localTimeouts[zone] ?? 30;

    // 1. Persist locally via provider so sliders survive navigation.
    ref.read(triggerSettingsProvider.notifier).updateZone(
          zone,
          start: start,
          target: target,
          timeout: timeout,
        );

    // 2. Zero-Trust Flow: push command to Firestore queue.
    final dataService = ref.read(dataServiceProvider);
    dataService?.sendCommand({
      'command': 'set_triggers',
      'zone': zone,
      'start_threshold': start,
      'target_saturation': target,
      'safety_timeout': timeout,
    });

    // 3. Confirm to user.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Zone $zone rules queued — Start: ${start.round()}%, Target: ${target.round()}%, Timeout: ${timeout}s',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFF0F2027),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildDryCalibrationButton(bool isConnected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isConnected
            ? () {
                _showConfirmDryCalibrationDialog();
              }
            : null,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isConnected
                  ? [const Color(0xFFA1887F), const Color(0xFF795548)]
                  : [
                      Colors.grey.withValues(alpha: 0.4),
                      Colors.grey.withValues(alpha: 0.5)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: isConnected
                ? null
                : Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white10
                        : Colors.white.withValues(alpha: 0.5),
                    width: 1.5),
            boxShadow: isConnected
                ? [
                    BoxShadow(
                      color: const Color(0xFF795548).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: isConnected
                ? [
                    const Icon(Icons.water_drop_outlined, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'RUN DRY CALIBRATION (ALL ZONES)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ]
                : [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'WAITING FOR CONNECTION...',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  void _showConfirmDryCalibrationDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Confirm Dry Calibration',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027),
            ),
          ),
          content: Text(
            'Please ensure all soil sensors are completely dry and exposed to air before running this calibration. This will reset the 0% reference for all zones.',
            style: GoogleFonts.outfit(color: const Color(0xFF37474F)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'CANCEL',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final dataService = ref.read(dataServiceProvider);
                dataService?.sendCommand({'command': 'dry_calibrate'});
                // Auto force-sync after dry calibration
                dataService?.forceSync();
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Dry calibration command sent — syncing live data...'),
                    backgroundColor: Color(0xFF5D4037),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF795548),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('CONFIRM',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Wet Calibration ───────────────────────────────────

  Widget _buildWetCalibrationButton(bool isConnected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isConnected
            ? () {
                _showConfirmWetCalibrationDialog();
              }
            : null,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isConnected
                  ? [const Color(0xFF29B6F6), const Color(0xFF0288D1)]
                  : [
                      Colors.grey.withValues(alpha: 0.4),
                      Colors.grey.withValues(alpha: 0.5)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: isConnected
                ? null
                : Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white10
                        : Colors.white.withValues(alpha: 0.5),
                    width: 1.5),
            boxShadow: isConnected
                ? [
                    BoxShadow(
                      color: const Color(0xFF29B6F6).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: isConnected
                ? [
                    const Icon(Icons.water_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'RUN WET CALIBRATION (ALL ZONES)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ]
                : [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'WAITING FOR CONNECTION...',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  void _showConfirmWetCalibrationDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Colors.white.withValues(alpha: 0.9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Confirm Wet Calibration',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027),
            ),
          ),
          content: Text(
            'Please submerge all soil sensors fully in water (or press them into saturated soil) before confirming. This will reset the 100% reference for all zones.',
            style: GoogleFonts.outfit(color: const Color(0xFF37474F)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'CANCEL',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final dataService = ref.read(dataServiceProvider);
                dataService?.sendCommand({'command': 'run_wet_calibration'});
                // Auto force-sync so the new wet_raw values appear immediately
                dataService?.forceSync();
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Wet calibration command sent — syncing live data...'),
                    backgroundColor: Color(0xFF0288D1),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF29B6F6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('CONFIRM',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    final animation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        (index * 0.1).clamp(0.0, 1.0),
        1.0,
        curve: Curves.easeOutCubic,
      ),
    ));

    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        (index * 0.1).clamp(0.0, 1.0),
        1.0,
        curve: Curves.easeOut,
      ),
    ));

    return SlideTransition(
      position: animation,
      child: FadeTransition(
        opacity: opacity,
        child: child,
      ),
    );
  }
}
