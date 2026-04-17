import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/sensor_provider.dart';
import '../../data/models/sensor_model.dart';
import '../../data/services/data_service.dart';

enum IrrigationStrategy { sensor, timer, none }

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen>
    with SingleTickerProviderStateMixin {
  String _mode = 'manual';
  TimeOfDay _autoTime = const TimeOfDay(hour: 8, minute: 0);
  late AnimationController _entranceController;

  // Track which zones are actively watering
  final Map<int, bool> _wateringActive = {1: false, 2: false, 3: false};

  // Optimistic UI: per-zone timeout timers (5-second Pi confirmation window)
  final Map<int, Timer?> _pumpTimeoutTimers = {1: null, 2: null, 3: null};

  // Dead-Man's Switch: heartbeat timer for manual watering safety
  Timer? _manualHeartbeatTimer;

  // Manage UI auto-reset timers for Burst (5s) and Soak (20s)
  final Map<int, Timer?> _zoneUiTimers = {1: null, 2: null, 3: null};

  // Track active auto strategy instead of a global boolean
  IrrigationStrategy _activeStrategy = IrrigationStrategy.none;

  // Master lockdown state — like a real industrial e-stop
  bool _masterLockdown = false;

  // ── Per-zone enabled toggles for each strategy ──
  // If a zone is false it is skipped when that strategy runs.
  final Map<int, bool> _sensorZonesEnabled = {1: true, 2: true, 3: true};
  final Map<int, bool> _timerZonesEnabled  = {1: true, 2: true, 3: true};

  // Which auto-strategy config page is currently visible (0 = Sensor, 1 = Timer)
  int _autoPageIndex = 0;

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
    _manualHeartbeatTimer?.cancel();
    for (var t in _zoneUiTimers.values) {
      t?.cancel();
    }
    for (var t in _pumpTimeoutTimers.values) {
      t?.cancel();
    }
    _entranceController.dispose();
    super.dispose();
  }

  /// Start the Dead-Man's Switch heartbeat (every 2s while manual watering)
  void _startManualHeartbeat() {
    _manualHeartbeatTimer?.cancel();
    final dataService = ref.read(dataServiceProvider);
    // Send initial heartbeat immediately
    dataService?.updateManualHeartbeat();
    _manualHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      dataService?.updateManualHeartbeat();
    });
  }

  /// Stop the Dead-Man's Switch heartbeat
  void _stopManualHeartbeat() {
    _manualHeartbeatTimer?.cancel();
    _manualHeartbeatTimer = null;
  }

  // ═══════════════════════════════════════════════════════
  // Optimistic UI: Start 5-second Pi confirmation window
  // ═══════════════════════════════════════════════════════

  /// Starts the 5-second window waiting for the Pi to confirm zone [zone] is ON.
  /// If `sensorData.pumpStatus[zone-1]` turns true before timeout, [_onPumpConfirmed]
  /// is called. Otherwise [_onPumpTimeout] reverts the UI.
  void _startPumpConfirmationTimer(int zone) {
    _pumpTimeoutTimers[zone]?.cancel();
    _pumpTimeoutTimers[zone] = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      // Check if Pi confirmed in time
      final sensorData = ref.read(sensorDataProvider);
      final zoneIdx = zone - 1;
      final confirmed = zoneIdx < sensorData.pumpStatus.length &&
          sensorData.pumpStatus[zoneIdx];
      if (!confirmed) {
        _onPumpTimeout(zone);
      }
    });
  }

  /// Called when the Pi confirmed pump activation (stream update).
  void _onPumpConfirmed(int zone) {
    _pumpTimeoutTimers[zone]?.cancel();
    _pumpTimeoutTimers[zone] = null;
    ref.read(pumpLoadingProvider(zone).notifier).setLoading(false);
    if (!mounted) return;
    setState(() => _wateringActive[zone] = true);
  }

  /// Called when 5 seconds pass with no Pi confirmation — revert everything.
  void _onPumpTimeout(int zone) {
    _pumpTimeoutTimers[zone]?.cancel();
    _pumpTimeoutTimers[zone] = null;
    ref.read(pumpLoadingProvider(zone).notifier).setLoading(false);
    // Also send a stop just in case a delayed response arrives later
    ref.read(sensorDataProvider.notifier).emergencyStop();
    if (!mounted) return;
    setState(() {
      _wateringActive[zone] = false;
    });
    
    final isTankLow = ref.read(sensorDataProvider).isTankLow;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isTankLow
                    ? ' The water is Low, Please check your tank ! '
                    : 'Zone $zone: Hardware did not respond. Check your connection.',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Toggle watering for a specific zone
  // ═══════════════════════════════════════════════════════

  /// Toggle watering for a specific zone
  void _toggleWatering(int zone, {int duration = 600}) {
    final isActive = _wateringActive[zone] ?? false;
    final isLoading = ref.read(pumpLoadingProvider(zone));
    final notifier = ref.read(sensorDataProvider.notifier);

    // If already loading, ignore double-tap
    if (isLoading) return;

    if (isActive) {
      // ── STOP watering this zone ──
      HapticFeedback.heavyImpact();
      notifier.emergencyStop();
      _stopManualHeartbeat();
      _zoneUiTimers[zone]?.cancel();
      _zoneUiTimers[zone] = null;
      // Clear any pending confirmation timers
      for (int z = 1; z <= 3; z++) {
        _pumpTimeoutTimers[z]?.cancel();
        ref.read(pumpLoadingProvider(z).notifier).setLoading(false);
      }
      setState(() {
        _wateringActive[1] = false;
        _wateringActive[2] = false;
        _wateringActive[3] = false;
      });
    } else {
      // ── START watering this zone (Optimistic UI) ──
      HapticFeedback.lightImpact();

      // 1. Cancel all other zones' state & timers
      for (int z = 1; z <= 3; z++) {
        _zoneUiTimers[z]?.cancel();
        _pumpTimeoutTimers[z]?.cancel();
        ref.read(pumpLoadingProvider(z).notifier).setLoading(false);
      }
      setState(() {
        _wateringActive[1] = false;
        _wateringActive[2] = false;
        _wateringActive[3] = false;
        // Zone stays false — it's in loading, not yet confirmed active
      });

      // 2. Set this zone to LOADING state
      ref.read(pumpLoadingProvider(zone).notifier).setLoading(true);

      // 3. Send command to Firestore
      notifier.forceWater(zone, durationSeconds: duration);

      if (duration >= 60) {
        _startManualHeartbeat();
      }

      // 4. Start 5-second confirmation window
      _startPumpConfirmationTimer(zone);

      // 5. For short bursts, set an auto-reset UI timer too
      if (duration < 60) {
        _zoneUiTimers[zone] = Timer(Duration(seconds: duration), () {
          if (mounted && _wateringActive[zone] == true) {
            setState(() => _wateringActive[zone] = false);
          }
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // Mutual-Exclusive Auto Strategy Toggle
  // ═══════════════════════════════════════════════════════
  /// Enables the given [strategy]; if it was already active it turns it OFF.
  /// Enabling one strategy automatically deactivates the other — a single
  /// [_activeStrategy] value enforces mutual exclusivity.
  void _toggleAutoStrategy(IrrigationStrategy strategy) {
    HapticFeedback.heavyImpact();
    final wasActive = _activeStrategy == strategy;
    setState(() {
      _activeStrategy = wasActive ? IrrigationStrategy.none : strategy;
    });

    // Build the enabled-zones list to pass alongside the command
    final enabledZones = strategy == IrrigationStrategy.sensor
        ? [1, 2, 3].where((z) => _sensorZonesEnabled[z] == true).toList()
        : [1, 2, 3].where((z) => _timerZonesEnabled[z] == true).toList();

    if (_activeStrategy != IrrigationStrategy.none) {
      ref.read(dataServiceProvider)?.setWateringMode(
        'auto',
        strategy: _activeStrategy.name,
        timerHour:
            _activeStrategy == IrrigationStrategy.timer ? _autoTime.hour : null,
        timerMinute: _activeStrategy == IrrigationStrategy.timer
            ? _autoTime.minute
            : null,
        enabledZones: enabledZones,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Auto watering ON — ${_activeStrategy.name} mode',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF2BCC71),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } else {
      ref.read(dataServiceProvider)?.setWateringMode('manual');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Auto watering OFF',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF0F2027),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sensorData = ref.watch(sensorDataProvider);

    // ── Optimistic UI: Listen for per-zone pump status confirmation from Pi ──
    for (int zone = 1; zone <= 3; zone++) {
      final zoneIdx = zone - 1;
      ref.listen<SensorData>(sensorDataProvider, (prev, next) {
        final wasActive = prev != null &&
            zoneIdx < prev.pumpStatus.length &&
            prev.pumpStatus[zoneIdx];
        final isNowActive =
            zoneIdx < next.pumpStatus.length && next.pumpStatus[zoneIdx];
        final isLoading = ref.read(pumpLoadingProvider(zone));
        if (!wasActive && isNowActive && isLoading) {
          _onPumpConfirmed(zone);
        }
      });
    }

    final notifier = ref.read(sensorDataProvider.notifier);
    final isConnected = Platform.isLinux || !sensorData.isOffline;

    // Read hardware safety statuses
    final isTankLow = sensorData.isTankLow;
    final isPumpLockedSafe = sensorData.pumpLocked;

    // Auto-lock watering if tank is low, pump locked, or MASTER LOCKDOWN active
    if (isTankLow || isPumpLockedSafe || _masterLockdown) {
      for (var z in [1, 2, 3]) {
        _wateringActive[z] = false;
      }
      if (_activeStrategy != IrrigationStrategy.none) {
        _activeStrategy = IrrigationStrategy.none;
      }
    }

    // Get raw moisture per zone for safety checks
    final rawSoil = sensorData.soilMoistureRaw;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Irrigation Control',
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
      ),
      body: Stack(
        children: [
          // ── Background ──
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF0F172A), const Color(0xFF064E3B)]
                      : const [Color(0xFFF0FDF4), Color(0xFFCCFBF1)],
                ),
              ),
            ),
          ),
          _buildBlob(
              top: -50,
              right: -100,
              size: 300,
              color: const Color(0xFF2BCC71).withValues(alpha: 0.15)),
          _buildBlob(
              bottom: 100,
              left: -100,
              size: 400,
              color: Colors.blue.withValues(alpha: 0.1)),

          // ── Content ──
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAnimatedItem(
                      0,
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isConnected
                              ? const Color(0xFF2BCC71).withValues(alpha: 0.1)
                              : Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isConnected
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_off_rounded,
                                color: isConnected
                                    ? const Color(0xFF2BCC71)
                                    : Colors.redAccent,
                                size: 20),
                            const SizedBox(width: 8),
                            Text(
                              isConnected
                                  ? "System online and connected"
                                  : "System offline - commands disabled",
                              style: GoogleFonts.outfit(
                                color: isConnected
                                    ? const Color(0xFF2BCC71)
                                    : Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 24),

                  // Mode Selector Card
                  _buildAnimatedItem(
                      1,
                      _buildGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Operation Mode',
                                style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF0F2027))),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white10
                                    : Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SegmentedButton<String>(
                                style: SegmentedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  selectedForegroundColor:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? const Color(0xFF0F2027)
                                          : Colors.white,
                                  selectedBackgroundColor:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : const Color(0xFF0F2027),
                                  textStyle: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w600),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                segments: const [
                                  ButtonSegment(
                                      value: 'manual',
                                      label: Text('Manual'),
                                      icon: Icon(Icons.touch_app_rounded)),
                                  ButtonSegment(
                                      value: 'auto',
                                      label: Text('Auto'),
                                      icon: Icon(Icons.schedule_rounded)),
                                ],
                                selected: {_mode},
                                showSelectedIcon: false,
                                onSelectionChanged: (sel) =>
                                    setState(() => _mode = sel.first),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 20),

                  // Per-Zone Toggle Controls
                  if (_mode == 'manual') ...[
                    _buildAnimatedItem(
                        2,
                        _buildGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Manual Override",
                                  style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : const Color(0xFF0F2027))),
                              const SizedBox(height: 8),
                              Text("Tap to start watering, tap again to stop.",
                                  style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white70
                                          : const Color(0xFF4A6164))),
                              const SizedBox(height: 16),

                              // Safety warnings (currently bypassed by UI testing flags)

                              _buildZoneToggle(
                                zone: 1,
                                label: "Zone 1 (Left)",
                                moisture: rawSoil.isNotEmpty ? rawSoil[0] : 0,
                                target: sensorData.targetMoisture.isNotEmpty
                                    ? sensorData.targetMoisture[0]
                                    : 65.0,
                                isActive: _wateringActive[1] ?? false,
                                disabled: isPumpLockedSafe ||
                                    !isConnected ||
                                    isTankLow ||
                                    _masterLockdown,
                              ),
                              const SizedBox(height: 12),
                              _buildZoneToggle(
                                zone: 2,
                                label: "Zone 2 (Center)",
                                moisture: rawSoil.length > 1 ? rawSoil[1] : 0,
                                target: sensorData.targetMoisture.length > 1
                                    ? sensorData.targetMoisture[1]
                                    : 65.0,
                                isActive: _wateringActive[2] ?? false,
                                disabled: isPumpLockedSafe ||
                                    !isConnected ||
                                    isTankLow ||
                                    _masterLockdown,
                              ),
                              const SizedBox(height: 12),
                              _buildZoneToggle(
                                zone: 3,
                                label: "Zone 3 (Right)",
                                moisture: rawSoil.length > 2 ? rawSoil[2] : 0,
                                target: sensorData.targetMoisture.length > 2
                                    ? sensorData.targetMoisture[2]
                                    : 65.0,
                                isActive: _wateringActive[3] ?? false,
                                disabled: isPumpLockedSafe ||
                                    !isConnected ||
                                    isTankLow ||
                                    _masterLockdown,
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 24),
                  ],

                  if (_mode == 'auto') ...[
                    _buildAnimatedItem(2, _buildAutoModePanel(
                      isConnected: isConnected,
                      isPumpLockedSafe: isPumpLockedSafe,
                      isTankLow: isTankLow,
                      rawSoil: rawSoil,
                      sensorData: sensorData,
                    )),
                    const SizedBox(height: 24),
                  ],

                  // ── Emergency Stop / Lockdown Controller ──
                  _buildAnimatedItem(
                      3,
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: _masterLockdown
                            ? const EdgeInsets.all(16)
                            : EdgeInsets.zero,
                        decoration: BoxDecoration(
                            color: _masterLockdown
                                ? Colors.redAccent.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                            border: _masterLockdown
                                ? Border.all(
                                    color:
                                        Colors.redAccent.withValues(alpha: 0.3),
                                    width: 2)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: _masterLockdown
                                    ? Colors.redAccent.withValues(alpha: 0.1)
                                    : Colors.redAccent.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ]),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_masterLockdown) ...[
                              Row(
                                children: [
                                  const Icon(Icons.report_problem_rounded,
                                      color: Colors.redAccent, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text("MASTER LOCKDOWN ACTIVE",
                                            style: GoogleFonts.outfit(
                                                color: Colors.redAccent,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                                letterSpacing: 0.5)),
                                        Text(
                                            "All watering disabled for safety.",
                                            style: GoogleFonts.outfit(
                                                color: Colors.redAccent
                                                    .withValues(alpha: 0.7),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            SizedBox(
                              height: 56,
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: isConnected
                                    ? () {
                                        HapticFeedback.heavyImpact();
                                        if (!_masterLockdown) {
                                          notifier.emergencyStop();
                                          setState(() {
                                            _masterLockdown = true;
                                            _wateringActive[1] = false;
                                            _wateringActive[2] = false;
                                            _wateringActive[3] = false;
                                            _activeStrategy =
                                                IrrigationStrategy.none;
                                          });
                                        } else {
                                          setState(
                                              () => _masterLockdown = false);
                                        }
                                      }
                                    : null,
                                icon: Icon(
                                    _masterLockdown
                                        ? Icons.lock_open_rounded
                                        : Icons.power_settings_new_rounded,
                                    size: 24),
                                label: Text(
                                    _masterLockdown
                                        ? "RELEASE SYSTEM LOCK"
                                        : "EMERGENCY STOP",
                                    style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _masterLockdown
                                      ? const Color(0xFF1B1B1B)
                                      : Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Zone Toggle Card — tap ON/OFF like a switch
  // ═══════════════════════════════════════════════════════

  Widget _buildZoneToggle({
    required int zone,
    required String label,
    required double moisture,
    required double target,
    required bool isActive,
    bool disabled = false,
  }) {
    // Read loading state for this specific zone
    final isLoading = ref.watch(pumpLoadingProvider(zone));

    final isFault = moisture < 0;
    final isSaturated = moisture >= 100 && !isFault;
    final isLocked = disabled || isSaturated;
    final moistureStr = isFault ? '--' : '${moisture.toStringAsFixed(0)}%';

    // Determine lock reason
    String? lockReason;
    if (isSaturated) {
      lockReason = 'Soil saturated';
    } else if (disabled) {
      lockReason = 'Locked';
    }

    // Colors based on state (loading → amber; active → blue; idle → green)
    final Color bgColor;
    final Color borderColor;
    final Color iconBgColor;
    final Color iconColor;
    final Color toggleBgColor;
    final Color toggleIconColor;
    final String toggleLabel;

    if (isLocked) {
      // Locked state — greyed out
      bgColor = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2C2C2C)
          : Colors.grey.shade50;
      borderColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade800
          : Colors.grey.shade200;
      iconBgColor = Colors.grey.shade100;
      iconColor = Colors.grey.shade400;
      toggleBgColor = Colors.grey.shade200;
      toggleIconColor = Colors.grey.shade400;
      toggleLabel = lockReason ?? 'Locked';
    } else if (isLoading) {
      // Optimistic loading — waiting for Pi confirmation
      bgColor = Colors.orange.withValues(alpha: 0.06);
      borderColor = Colors.orange.withValues(alpha: 0.5);
      iconBgColor = Colors.orange.withValues(alpha: 0.15);
      iconColor = Colors.orange.shade700;
      toggleBgColor = Colors.orange.shade700;
      toggleIconColor = Colors.white;
      toggleLabel = 'Sending...';
    } else if (isActive) {
      // Confirmed active by Pi — vivid blue
      bgColor = const Color(0xFF29B6F6).withValues(alpha: 0.08);
      borderColor = const Color(0xFF29B6F6).withValues(alpha: 0.5);
      iconBgColor = const Color(0xFF29B6F6).withValues(alpha: 0.2);
      iconColor = const Color(0xFF0277BD);
      toggleBgColor = Colors.redAccent;
      toggleIconColor = Colors.white;
      toggleLabel = 'Stop';
    } else {
      // Idle state — ready to start
      bgColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.5);
      borderColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.white24
          : Colors.white;
      iconBgColor = const Color(0xFF2BCC71).withValues(alpha: 0.1);
      iconColor = const Color(0xFF2BCC71);
      toggleBgColor = const Color(0xFF2BCC71);
      toggleIconColor = Colors.white;
      toggleLabel = 'Water';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isActive ? 2.0 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Zone icon with animated pulse when active
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isActive ? Icons.waves_rounded : Icons.water_drop_rounded,
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // Zone info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isLocked
                                ? Colors.grey.shade400
                                : const Color(0xFF0F2027))),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text("Moisture: $moistureStr",
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                  color: isLocked
                                      ? Colors.grey.shade300
                                      : const Color(0xFF4A6164),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ),
                        if (isLoading) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('PENDING',
                                style: GoogleFonts.outfit(
                                    color: Colors.orange.shade800,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF29B6F6)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('WATERING',
                                style: GoogleFonts.outfit(
                                    color: const Color(0xFF0277BD),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                        if (isSaturated) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('SATURATED',
                                style: GoogleFonts.outfit(
                                    color: Colors.orange.shade700,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ── Right Action: Spinner / Stop / Lock ──
              if (isLoading)
                // LOADING: Spinner while waiting for Pi ACK
                Flexible(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('Sending...',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else if (isActive || isLocked)
                Flexible(
                  child: GestureDetector(
                    onTap: isLocked ? null : () => _toggleWatering(zone),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: toggleBgColor,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? Icons.stop_rounded : Icons.lock_rounded,
                            color: toggleIconColor,
                            size: 18,
                          ),
                          if (!isLocked) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(toggleLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                      color: toggleIconColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // 3-Button Manual Controls (when Idle and NOT loading)
          if (!isActive && !isLoading && !isLocked) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildManualOption(
                    label: "Burst",
                    duration: 5,
                    zone: zone,
                    color: const Color(0xFF29B6F6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildManualOption(
                    label: "Soak",
                    duration: 20,
                    zone: zone,
                    color: const Color(0xFF42A5F5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildManualOption(
                    label: "Flow",
                    duration: 600,
                    zone: zone,
                    color: const Color(0xFF2BCC71),
                    isFilled: true,
                  ),
                ),
              ],
            ),
          ],
          // ── Live Moisture Expansion Panel (visible when actively watering) ──
          AnimatedCrossFade(
            crossFadeState:
                isActive ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 400),
            sizeCurve: Curves.easeInOut,
            firstChild: const SizedBox.shrink(),
            secondChild: _LiveMoisturePanel(
              moisture: moisture,
              target: target,
              isFault: isFault,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualOption({
    required String label,
    required int duration,
    required int zone,
    required Color color,
    bool isFilled = false,
  }) {
    return GestureDetector(
      onTap: () => _toggleWatering(zone, duration: duration),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isFilled ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border:
              isFilled ? null : Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: isFilled
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isFilled ? Colors.white : color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ignore: unused_element — retained for when UI testing bypass is removed
  Widget _buildWarningBanner(
      {required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.outfit(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Auto Mode Panel — tabbed between Sensor Target / Daily Timer
  // ═══════════════════════════════════════════════════════

  Widget _buildAutoModePanel({
    required bool isConnected,
    required bool isPumpLockedSafe,
    required bool isTankLow,
    required List<double> rawSoil,
    required dynamic sensorData,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool globalDisabled =
        !isConnected || isPumpLockedSafe || isTankLow || _masterLockdown;

    // Tab accent colours
    const sensorColor = Color(0xFF29B6F6);
    const timerColor  = Color(0xFF2BCC71);
    final activeTabColor = _autoPageIndex == 0 ? sensorColor : timerColor;

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  color: activeTabColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Automatic Strategy',
                  style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F2027)),
                ),
              ),
              // Active badge
              if (_activeStrategy != IrrigationStrategy.none)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeTabColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: GoogleFonts.outfit(
                        color: activeTabColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Only one strategy can be active at a time.',
            style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : const Color(0xFF4A6164)),
          ),
          const SizedBox(height: 16),

          // ── Strategy page tab bar ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _buildPageTab(
                  index: 0,
                  label: 'Sensor Target',
                  icon: Icons.water_drop_rounded,
                  color: sensorColor,
                  isSelected: _autoPageIndex == 0,
                  isStrategyOn: _activeStrategy == IrrigationStrategy.sensor,
                ),
                const SizedBox(width: 4),
                _buildPageTab(
                  index: 1,
                  label: 'Daily Timer',
                  icon: Icons.access_time_filled_rounded,
                  color: timerColor,
                  isSelected: _autoPageIndex == 1,
                  isStrategyOn: _activeStrategy == IrrigationStrategy.timer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Page content (animated cross-fade) ──
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _autoPageIndex == 0
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _buildSensorTargetPage(
              isConnected: isConnected,
              isPumpLockedSafe: isPumpLockedSafe,
              isTankLow: isTankLow,
              rawSoil: rawSoil,
              sensorData: sensorData,
              globalDisabled: globalDisabled,
            ),
            secondChild: _buildDailyTimerPage(
              globalDisabled: globalDisabled,
            ),
          ),
        ],
      ),
    );
  }

  /// A single tab button for switching between strategy pages.
  Widget _buildPageTab({
    required int index,
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required bool isStrategyOn,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _autoPageIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: color.withValues(alpha: 0.45), width: 1.5)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white38 : Colors.grey.shade400)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? color
                          : (isDark ? Colors.white38 : Colors.grey.shade400)),
                ),
              ),
              if (isStrategyOn) ...[
                const SizedBox(width: 4),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Page 1: Sensor Target ──
  Widget _buildSensorTargetPage({
    required bool isConnected,
    required bool isPumpLockedSafe,
    required bool isTankLow,
    required List<double> rawSoil,
    required dynamic sensorData,
    required bool globalDisabled,
  }) {
    const color = Color(0xFF29B6F6);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _activeStrategy == IrrigationStrategy.sensor;

    // Compute if all zones are enabled
    final allOn = _sensorZonesEnabled.values.every((v) => v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Strategy description row
        _buildStrategyHeaderRow(
          icon: Icons.water_drop_rounded,
          color: color,
          title: 'Sensor Target',
          description: 'Waters when soil moisture drops ≤ start threshold.',
          isActive: isActive,
          disabled: globalDisabled,
          strategy: IrrigationStrategy.sensor,
        ),
        const SizedBox(height: 16),

        // Zone chips header (label only — All chip is inside the row)
        Text('Active Zones',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF4A6164))),
        const SizedBox(height: 10),

        // Zone enable chips row: [All] [Zone 1] [Zone 2] [Zone 3]
        Row(
          children: [
            // ── ALL chip ──
            Expanded(
              child: _buildZoneEnableChip(
                zone: 0,
                isAll: true,
                enabled: allOn,
                color: color,
                onToggle: () {
                  setState(() {
                    final newVal = !allOn;
                    _sensorZonesEnabled[1] = newVal;
                    _sensorZonesEnabled[2] = newVal;
                    _sensorZonesEnabled[3] = newVal;
                  });
                  if (isActive) _resendStrategyCommand();
                },
              ),
            ),
            const SizedBox(width: 8),
            // ── Individual zone chips ──
            for (int z = 1; z <= 3; z++) ...[
              Expanded(
                child: _buildZoneEnableChip(
                  zone: z,
                  moisture: z <= rawSoil.length ? rawSoil[z - 1] : null,
                  enabled: _sensorZonesEnabled[z] ?? true,
                  color: color,
                  onToggle: () {
                    setState(() {
                      _sensorZonesEnabled[z] = !(_sensorZonesEnabled[z] ?? true);
                    });
                    if (isActive) _resendStrategyCommand();
                  },
                ),
              ),
              if (z < 3) const SizedBox(width: 8),
            ],
          ],
        ),

        // Show warning if no zone is enabled
        if (_sensorZonesEnabled.values.every((v) => !v)) ...[
          const SizedBox(height: 10),
          _buildInlineWarning(
            'Enable at least one zone for the strategy to run.',
            Icons.warning_amber_rounded,
            Colors.amber,
          ),
        ],
      ],
    );
  }

  // ── Page 2: Daily Timer ──
  Widget _buildDailyTimerPage({required bool globalDisabled}) {
    const color = Color(0xFF2BCC71);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _activeStrategy == IrrigationStrategy.timer;
    final allOn = _timerZonesEnabled.values.every((v) => v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Strategy description row
        _buildStrategyHeaderRow(
          icon: Icons.access_time_filled_rounded,
          color: color,
          title: 'Daily Timer',
          description: 'Waters selected zones at the configured time each day.',
          isActive: isActive,
          disabled: globalDisabled,
          strategy: IrrigationStrategy.timer,
        ),
        const SizedBox(height: 16),

        // Zone chips header (label only)
        Text('Active Zones',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF4A6164))),
        const SizedBox(height: 10),

        // Zone enable chips row: [All] [Zone 1] [Zone 2] [Zone 3]
        Row(
          children: [
            // ── ALL chip ──
            Expanded(
              child: _buildZoneEnableChip(
                zone: 0,
                isAll: true,
                enabled: allOn,
                color: color,
                onToggle: () {
                  setState(() {
                    final newVal = !allOn;
                    _timerZonesEnabled[1] = newVal;
                    _timerZonesEnabled[2] = newVal;
                    _timerZonesEnabled[3] = newVal;
                  });
                  if (isActive) _resendStrategyCommand();
                },
              ),
            ),
            const SizedBox(width: 8),
            // ── Individual zone chips ──
            for (int z = 1; z <= 3; z++) ...[
              Expanded(
                child: _buildZoneEnableChip(
                  zone: z,
                  enabled: _timerZonesEnabled[z] ?? true,
                  color: color,
                  onToggle: () {
                    setState(() {
                      _timerZonesEnabled[z] = !(_timerZonesEnabled[z] ?? true);
                    });
                    if (isActive) _resendStrategyCommand();
                  },
                ),
              ),
              if (z < 3) const SizedBox(width: 8),
            ],
          ],
        ),

        if (_timerZonesEnabled.values.every((v) => !v)) ...[
          const SizedBox(height: 10),
          _buildInlineWarning(
            'Enable at least one zone for the timer to run.',
            Icons.warning_amber_rounded,
            Colors.amber,
          ),
        ],

        // Time picker (always visible in timer page)
        const SizedBox(height: 16),
        _buildTimerPicker(),
      ],
    );
  }

  /// Resends the current active strategy command after zone-config change.
  void _resendStrategyCommand() {
    final strategy = _activeStrategy;
    if (strategy == IrrigationStrategy.none) return;
    final enabledZones = strategy == IrrigationStrategy.sensor
        ? [1, 2, 3].where((z) => _sensorZonesEnabled[z] == true).toList()
        : [1, 2, 3].where((z) => _timerZonesEnabled[z] == true).toList();
    ref.read(dataServiceProvider)?.setWateringMode(
      'auto',
      strategy: strategy.name,
      timerHour: strategy == IrrigationStrategy.timer ? _autoTime.hour : null,
      timerMinute: strategy == IrrigationStrategy.timer ? _autoTime.minute : null,
      enabledZones: enabledZones,
    );
  }

  /// Strategy header row: icon, title, description, ON/OFF pill.
  Widget _buildStrategyHeaderRow({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
    required bool isActive,
    required bool disabled,
    required IrrigationStrategy strategy,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: disabled
            ? (isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade50)
            : isActive
                ? color.withValues(alpha: 0.09)
                : (isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: disabled
              ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
              : isActive
                  ? color.withValues(alpha: 0.55)
                  : (isDark ? Colors.white24 : Colors.white),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: disabled
                  ? Colors.grey.shade100
                  : color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: disabled ? Colors.grey.shade400 : color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: disabled
                            ? Colors.grey.shade400
                            : isDark
                                ? Colors.white
                                : const Color(0xFF0F2027))),
                const SizedBox(height: 2),
                Text(description,
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: disabled
                            ? Colors.grey.shade300
                            : isDark
                                ? Colors.white54
                                : const Color(0xFF4A6164))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: disabled ? null : () => _toggleAutoStrategy(strategy),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: disabled
                    ? Colors.grey.shade200
                    : isActive
                        ? color
                        : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.38),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    color: disabled
                        ? Colors.grey.shade400
                        : isActive
                            ? Colors.white
                            : color,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isActive ? 'ON' : 'OFF',
                    style: GoogleFonts.outfit(
                      color: disabled
                          ? Colors.grey.shade400
                          : isActive
                              ? Colors.white
                              : color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
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

  /// Zone enable/disable chip used inside auto strategy pages.
  /// Set [isAll] = true to render the special "All" master chip.
  Widget _buildZoneEnableChip({
    required int zone,
    required bool enabled,
    required Color color,
    required VoidCallback onToggle,
    double? moisture,
    bool isAll = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = isAll ? 'All' : 'Zone $zone';
    final moistureStr = (!isAll && moisture != null && moisture >= 0)
        ? '${moisture.toStringAsFixed(0)}%'
        : null;

    // All chip uses a slightly stronger border to stand out as the master toggle
    final chipBorderWidth = isAll ? (enabled ? 2.0 : 1.5) : (enabled ? 1.5 : 1.0);

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onToggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: isAll ? 0.15 : 0.1)
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: isAll ? 0.65 : 0.45)
                : (isDark ? Colors.white12 : Colors.grey.shade200),
            width: chipBorderWidth,
          ),
          boxShadow: (isAll && enabled)
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: enabled
                    ? color.withValues(alpha: isAll ? 0.25 : 0.18)
                    : (isDark ? Colors.white12 : Colors.grey.shade100),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAll
                    ? (enabled
                        ? Icons.select_all_rounded
                        : Icons.deselect_rounded)
                    : (enabled ? Icons.check_rounded : Icons.close_rounded),
                size: isAll ? 17 : 16,
                color: enabled
                    ? color
                    : (isDark ? Colors.white38 : Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: isAll ? FontWeight.w800 : FontWeight.w700,
                  color: enabled
                      ? (isDark ? Colors.white : const Color(0xFF0F2027))
                      : (isDark ? Colors.white38 : Colors.grey.shade400)),
            ),
            if (moistureStr != null) ...[
              const SizedBox(height: 2),
              Text(
                moistureStr,
                style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: enabled
                        ? color
                        : (isDark ? Colors.white24 : Colors.grey.shade300)),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              enabled ? 'ON' : 'OFF',
              style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: enabled
                      ? color
                      : (isDark ? Colors.white24 : Colors.grey.shade300)),
            ),
          ],
        ),
      ),
    );
  }

  /// Small inline amber/red warning banner.
  Widget _buildInlineWarning(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.outfit(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Per-Strategy Toggle Card (legacy — kept for reference)
  // ═══════════════════════════════════════════════════════

  // ignore: unused_element
  Widget _buildStrategyToggle({
    required IrrigationStrategy strategy,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required bool isActive,
    bool disabled = false,
    Widget? extra,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor;
    final Color borderColor;
    if (disabled) {
      bgColor = isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade50;
      borderColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    } else if (isActive) {
      bgColor = color.withValues(alpha: 0.09);
      borderColor = color.withValues(alpha: 0.55);
    } else {
      bgColor = isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.5);
      borderColor = isDark ? Colors.white24 : Colors.white;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isActive ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Icon badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: disabled
                      ? Colors.grey.shade100
                      : color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: disabled ? Colors.grey.shade400 : color, size: 20),
              ),
              const SizedBox(width: 12),
              // Title + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: disabled
                              ? Colors.grey.shade400
                              : isDark
                                  ? Colors.white
                                  : const Color(0xFF0F2027)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: disabled
                              ? Colors.grey.shade300
                              : isDark
                                  ? Colors.white54
                                  : const Color(0xFF4A6164)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // ON/OFF pill button
              GestureDetector(
                onTap: disabled ? null : () => _toggleAutoStrategy(strategy),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: disabled
                        ? Colors.grey.shade200
                        : isActive
                            ? color
                            : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.38),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive
                            ? Icons.toggle_on_rounded
                            : Icons.toggle_off_rounded,
                        color: disabled
                            ? Colors.grey.shade400
                            : isActive
                                ? Colors.white
                                : color,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'ON' : 'OFF',
                        style: GoogleFonts.outfit(
                          color: disabled
                              ? Colors.grey.shade400
                              : isActive
                                  ? Colors.white
                                  : color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Optional extra widget (e.g. time picker for Daily Timer)
          if (extra != null) ...[const SizedBox(height: 12), extra],
        ],
      ),
    );
  }

  /// Time picker tile — shown inside the Daily Timer card when active.
  Widget _buildTimerPicker() {
    return InkWell(
      onTap: () async {
        final time =
            await showTimePicker(context: context, initialTime: _autoTime);
        if (time != null) {
          setState(() => _autoTime = time);
          // Re-send updated timer command so the Pi adopts the new time.
          ref.read(dataServiceProvider)?.setWateringMode(
            'auto',
            strategy: 'timer',
            timerHour: time.hour,
            timerMinute: time.minute,
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF2BCC71).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF2BCC71).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm_rounded,
                    color: Color(0xFF2BCC71), size: 18),
                const SizedBox(width: 8),
                Text(
                  "Execution Time",
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: const Color(0xFF15803D)),
                ),
              ],
            ),
            Text(
              _autoTime.format(context),
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: const Color(0xFF2BCC71)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Legacy stub — retained to avoid stale references during hot-reload.
  // Not called from UI; use _buildStrategyToggle instead.
  // ═══════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildAutoModeToggle({
    required bool isActive,
    required bool disabled,
    required VoidCallback onToggle,
  }) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final IconData icon;
    final String label;
    final String subtitle;

    if (disabled) {
      bgColor = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2C2C2C)
          : Colors.grey.shade100;
      borderColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade800
          : Colors.grey.shade200;
      textColor = Colors.grey.shade400;
      icon = Icons.lock_rounded;
      label = 'Locked';
      subtitle = 'Cannot activate — tank level too low';
    } else if (isActive) {
      bgColor = const Color(0xFF2BCC71).withValues(alpha: 0.1);
      borderColor = const Color(0xFF2BCC71).withValues(alpha: 0.5);
      textColor = const Color(0xFF15803D);
      icon = Icons.toggle_on_rounded;
      label = 'Auto Mode ON';
      subtitle = 'Tap to deactivate';
    } else {
      bgColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.5);
      borderColor = const Color(0xFF0F2027).withValues(alpha: 0.15);
      textColor = const Color(0xFF0F2027);
      icon = Icons.toggle_off_rounded;
      label = 'Auto Mode OFF';
      subtitle = 'Tap to activate';
    }

    return GestureDetector(
      onTap: disabled ? null : onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isActive ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: textColor.withValues(alpha: 0.6))),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2BCC71).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('ACTIVE',
                    style: GoogleFonts.outfit(
                        color: const Color(0xFF15803D),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0F172A).withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white24
                : Colors.white,
            width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
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
              color.withValues(alpha: 0.8),
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        final start = index * 0.1;
        final curve = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start.clamp(0.0, 1.0), (start + 0.6).clamp(0.0, 1.0),
              curve: Curves.easeOutQuart),
        );
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curve.value)),
            child: child,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// Live Moisture Panel — expands inside zone card when watering
// ═══════════════════════════════════════════════════════
class _LiveMoisturePanel extends StatefulWidget {
  final double moisture;
  final double target;
  final bool isFault;

  const _LiveMoisturePanel({
    required this.moisture,
    required this.target,
    required this.isFault,
  });

  @override
  State<_LiveMoisturePanel> createState() => _LiveMoisturePanelState();
}

class _LiveMoisturePanelState extends State<_LiveMoisturePanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _statusLabel(double moisture, double target) {
    final gap = target - moisture;
    if (gap <= 0) return '✅ Target reached — tap Stop';
    if (gap <= 5) return 'Almost there — ${gap.toStringAsFixed(0)}% to target';
    if (gap <= 20) return 'Soil absorbing water...';
    return 'Watering in progress';
  }

  @override
  Widget build(BuildContext context) {
    final moisture = widget.moisture;
    final target = widget.target;
    final isFault = widget.isFault;
    final safeTarget = target > 0 ? target : 65.0;
    final progress = (moisture / safeTarget).clamp(0.0, 1.0);
    final targetFraction = (safeTarget / 100.0).clamp(0.0, 1.0);
    final moistureStr = isFault ? '--' : '${moisture.toStringAsFixed(0)}%';
    final nearTarget = !isFault && (safeTarget - moisture) <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24, color: Color(0x2029B6F6)),

        // ── Header: label + pulsing live indicator ──
        Row(
          children: [
            Text(
              'LIVE MOISTURE',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : const Color(0xFF4A6164),
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Opacity(
                opacity: _pulseAnim.value,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isFault ? Colors.redAccent : const Color(0xFF29B6F6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'LIVE',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isFault ? Colors.redAccent : const Color(0xFF29B6F6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Big moisture number + target ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              moistureStr,
              style: GoogleFonts.outfit(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                color: isFault
                    ? Colors.grey.shade400
                    : nearTarget
                        ? const Color(0xFF2BCC71)
                        : const Color(0xFF29B6F6),
                height: 1.0,
              ),
            ),
            const SizedBox(width: 14),
            if (!isFault)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Target',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : const Color(0xFF4A6164),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${safeTarget.toStringAsFixed(0)}%',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF2BCC71),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Progress bar with target tick ──
        if (!isFault) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final tickX =
                  (targetFraction * barWidth).clamp(0.0, barWidth - 4);
              return SizedBox(
                height: 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Background track
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF29B6F6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    // Animated fill
                    AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: nearTarget
                                ? [
                                    const Color(0xFF2BCC71),
                                    const Color(0xFF1BA85D)
                                  ]
                                : [
                                    const Color(0xFF29B6F6),
                                    const Color(0xFF0277BD)
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    // Target tick marker (glowing green line)
                    Positioned(
                      left: tickX,
                      top: -3,
                      bottom: -3,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2BCC71),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2BCC71)
                                  .withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%',
                  style: GoogleFonts.outfit(
                      fontSize: 9,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : const Color(0xFF4A6164),
                      fontWeight: FontWeight.w500)),
              Text('100%',
                  style: GoogleFonts.outfit(
                      fontSize: 9,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : const Color(0xFF4A6164),
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Sensor fault — moisture reading unavailable',
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent),
            ),
          ),
        ],
        const SizedBox(height: 10),

        // ── Contextual status label ──
        if (!isFault)
          Text(
            _statusLabel(moisture, safeTarget),
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: nearTarget
                  ? const Color(0xFF2BCC71)
                  : const Color(0xFF4A6164),
            ),
          ),
      ],
    );
  }
}
