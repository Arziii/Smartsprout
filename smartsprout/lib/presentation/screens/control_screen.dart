import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/sensor_provider.dart';
import '../../data/services/data_service.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen>
    with SingleTickerProviderStateMixin {
  String _mode = 'manual';
  String _autoStrategy = 'sensor';
  TimeOfDay _autoTime = const TimeOfDay(hour: 8, minute: 0);
  late AnimationController _entranceController;

  // Track which zones are actively watering
  final Map<int, bool> _wateringActive = {1: false, 2: false, 3: false};

  // Track if auto mode is active
  bool _autoModeActive = false;

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

  /// Toggle watering for a specific zone
  void _toggleWatering(int zone) {
    final isActive = _wateringActive[zone] ?? false;
    final notifier = ref.read(sensorDataProvider.notifier);

    if (isActive) {
      // STOP watering this zone
      HapticFeedback.heavyImpact();
      notifier.emergencyStop();
      setState(() {
        _wateringActive[1] = false;
        _wateringActive[2] = false;
        _wateringActive[3] = false;
      });
    } else {
      // START watering this zone (continuous until user stops)
      HapticFeedback.lightImpact();
      // Send force_water with a long duration (user will manually stop)
      notifier.forceWater(zone, durationSeconds: 600); // 10 min max safety
      setState(() {
        // Only one zone can water at a time for safety
        _wateringActive[1] = false;
        _wateringActive[2] = false;
        _wateringActive[3] = false;
        _wateringActive[zone] = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);
    final notifier = ref.read(sensorDataProvider.notifier);
    final isConnected = Platform.isLinux || !sensorData.isOffline;
    final pumpLocked = sensorData.pumpLocked;
    final tankLevel = sensorData.tankLevel;
    // Block watering if: tank fault (-1), empty (0%), or below 10%
    final isTankLow = tankLevel < 10;

    // Auto-lock watering if tank is low or pump locked
    if (isTankLow || pumpLocked) {
      for (var z in [1, 2, 3]) {
        _wateringActive[z] = false;
      }
      if (_autoModeActive) _autoModeActive = false;
    }

    // Get raw moisture per zone for safety checks
    final rawSoil = sensorData.soilMoistureRaw;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Irrigation Control',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F2027),
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
                ),
              ),
            ),
          ),
          _buildBlob(top: -50, right: -100, size: 300, color: const Color(0xFF2BCC71).withOpacity(0.15)),
          _buildBlob(bottom: 100, left: -100, size: 400, color: Colors.blue.withOpacity(0.1)),

          // ── Content ──
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   _buildAnimatedItem(0, Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isConnected ? const Color(0xFF2BCC71).withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, 
                          color: isConnected ? const Color(0xFF2BCC71) : Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isConnected ? "System online and connected" : "System offline - commands disabled",
                          style: GoogleFonts.outfit(
                            color: isConnected ? const Color(0xFF2BCC71) : Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),

                  // Mode Selector Card
                  _buildAnimatedItem(1, _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Operation Mode',
                            style: GoogleFonts.outfit(
                                fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SegmentedButton<String>(
                            style: SegmentedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              selectedForegroundColor: Colors.white,
                              selectedBackgroundColor: const Color(0xFF0F2027),
                              textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    _buildAnimatedItem(2, _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Manual Override",
                              style: GoogleFonts.outfit(
                                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                          const SizedBox(height: 8),
                          Text("Tap to start watering, tap again to stop.",
                              style: GoogleFonts.outfit(
                                  fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF4A6164))),
                          const SizedBox(height: 16),

                          // Safety warnings
                          if (pumpLocked || isTankLow)
                            _buildWarningBanner(
                              icon: Icons.lock_rounded,
                              text: tankLevel < 0
                                  ? "Pump LOCKED — tank sensor fault."
                                  : "Pump LOCKED — tank level critically low (${tankLevel.toStringAsFixed(0)}%).",
                              color: Colors.redAccent,
                            ),

                          _buildZoneToggle(
                            zone: 1,
                            label: "Zone 1 (Left)",
                            moisture: rawSoil.isNotEmpty ? rawSoil[0] : 0,
                            isActive: _wateringActive[1] ?? false,
                            disabled: pumpLocked || !isConnected || isTankLow,
                          ),
                          const SizedBox(height: 12),
                          _buildZoneToggle(
                            zone: 2,
                            label: "Zone 2 (Center)",
                            moisture: rawSoil.length > 1 ? rawSoil[1] : 0,
                            isActive: _wateringActive[2] ?? false,
                            disabled: pumpLocked || !isConnected || isTankLow,
                          ),
                          const SizedBox(height: 12),
                          _buildZoneToggle(
                            zone: 3,
                            label: "Zone 3 (Right)",
                            moisture: rawSoil.length > 2 ? rawSoil[2] : 0,
                            isActive: _wateringActive[3] ?? false,
                            disabled: pumpLocked || !isConnected || isTankLow,
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],

                  if (_mode == 'auto') ...[
                    _buildAnimatedItem(2, _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Automatic Strategy",
                              style: GoogleFonts.outfit(
                                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: SegmentedButton<String>(
                              style: SegmentedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                selectedForegroundColor: Colors.white,
                                selectedBackgroundColor: const Color(0xFF29B6F6),
                                textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 'sensor',
                                  label: Text('Sensor Target'),
                                  icon: Icon(Icons.water_drop_rounded),
                                ),
                                ButtonSegment(
                                  value: 'timer',
                                  label: Text('Daily Timer'),
                                  icon: Icon(Icons.access_time_filled_rounded),
                                ),
                              ],
                              selected: {_autoStrategy},
                              showSelectedIcon: false,
                              onSelectionChanged: (sel) => setState(() => _autoStrategy = sel.first),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          if (_autoStrategy == 'sensor') ...[
                             Row(
                               children: [
                                 Container(
                                   padding: const EdgeInsets.all(12),
                                   decoration: BoxDecoration(color: const Color(0xFF29B6F6).withOpacity(0.15), shape: BoxShape.circle),
                                   child: const Icon(Icons.water_drop_rounded, color: Color(0xFF29B6F6)),
                                 ),
                                 const SizedBox(width: 16),
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text("Sensor Thresholds", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F2027))),
                                       Text("Waters automatically when soil moisture drops below your calibration level.", style: GoogleFonts.outfit(color: const Color(0xFF4A6164), fontSize: 13, fontWeight: FontWeight.w500)),
                                     ]
                                   )
                                 )
                               ]
                             )
                          ] else ...[
                             Row(
                               children: [
                                 Container(
                                   padding: const EdgeInsets.all(12),
                                   decoration: BoxDecoration(color: const Color(0xFF29B6F6).withOpacity(0.15), shape: BoxShape.circle),
                                   child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFF29B6F6)),
                                 ),
                                 const SizedBox(width: 16),
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text("Daily Schedule", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F2027))),
                                       Text("Waters all zones every day at the time selected below.", style: GoogleFonts.outfit(color: const Color(0xFF4A6164), fontSize: 13, fontWeight: FontWeight.w500)),
                                     ]
                                   )
                                 )
                               ]
                             ),
                             const SizedBox(height: 16),
                             InkWell(
                               onTap: () async {
                                 final time = await showTimePicker(context: context, initialTime: _autoTime);
                                 if (time != null) setState(() => _autoTime = time);
                               },
                               borderRadius: BorderRadius.circular(12),
                               child: Container(
                                 padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                 decoration: BoxDecoration(
                                   color: Colors.white.withOpacity(0.8),
                                   borderRadius: BorderRadius.circular(12),
                                   border: Border.all(color: const Color(0xFF29B6F6).withOpacity(0.3)),
                                 ),
                                 child: Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                   children: [
                                     Text("Execution Time", style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15, color: const Color(0xFF0F2027))),
                                     Text(_autoTime.format(context), style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF29B6F6))),
                                   ]
                                 )
                               )
                             )
                          ],

                          // Safety warning for auto mode too
                          if (pumpLocked || isTankLow) ...[                            const SizedBox(height: 16),
                            _buildWarningBanner(
                              icon: Icons.lock_rounded,
                              text: tankLevel < 0
                                  ? "Auto mode disabled — tank sensor fault."
                                  : "Auto mode disabled — tank level critically low (${tankLevel.toStringAsFixed(0)}%).",
                              color: Colors.redAccent,
                            ),
                          ],

                          const SizedBox(height: 24),
                          // ── Auto Mode Toggle Switch ──
                          _buildAutoModeToggle(
                            isActive: _autoModeActive,
                            disabled: !isConnected || pumpLocked || isTankLow,
                            onToggle: () {
                              HapticFeedback.heavyImpact();
                              setState(() => _autoModeActive = !_autoModeActive);
                              if (_autoModeActive) {
                                ref.read(dataServiceProvider)?.setWateringMode(
                                  'auto',
                                  strategy: _autoStrategy,
                                  timerHour: _autoTime.hour,
                                  timerMinute: _autoTime.minute,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Auto watering ON — $_autoStrategy mode',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                                    backgroundColor: const Color(0xFF2BCC71),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                );
                              } else {
                                ref.read(dataServiceProvider)?.setWateringMode('manual');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Auto watering OFF',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                                    backgroundColor: const Color(0xFF0F2027),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],

                  // Emergency Stop
                  _buildAnimatedItem(3, Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ]
                    ),
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: isConnected
                            ? () {
                                HapticFeedback.heavyImpact();
                                notifier.emergencyStop();
                                setState(() {
                                  _wateringActive[1] = false;
                                  _wateringActive[2] = false;
                                  _wateringActive[3] = false;
                                });
                              }
                            : null,
                        icon: const Icon(Icons.power_settings_new_rounded, size: 24),
                        label: Text("EMERGENCY STOP",
                            style: GoogleFonts.outfit(
                                fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                      ),
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
    required bool isActive,
    bool disabled = false,
  }) {
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

    // Colors based on state
    final Color bgColor;
    final Color borderColor;
    final Color iconBgColor;
    final Color iconColor;
    final Color toggleBgColor;
    final Color toggleIconColor;
    final String toggleLabel;

    if (isLocked) {
      // Locked state — greyed out
      bgColor = Colors.grey.shade50;
      borderColor = Colors.grey.shade200;
      iconBgColor = Colors.grey.shade100;
      iconColor = Colors.grey.shade400;
      toggleBgColor = Colors.grey.shade200;
      toggleIconColor = Colors.grey.shade400;
      toggleLabel = lockReason ?? 'Locked';
    } else if (isActive) {
      // Actively watering — vivid blue/green pulse
      bgColor = const Color(0xFF29B6F6).withOpacity(0.08);
      borderColor = const Color(0xFF29B6F6).withOpacity(0.5);
      iconBgColor = const Color(0xFF29B6F6).withOpacity(0.2);
      iconColor = const Color(0xFF0277BD);
      toggleBgColor = Colors.redAccent;
      toggleIconColor = Colors.white;
      toggleLabel = 'Stop';
    } else {
      // Idle state — ready to start
      bgColor = Colors.white.withOpacity(0.5);
      borderColor = Colors.white;
      iconBgColor = const Color(0xFF2BCC71).withOpacity(0.1);
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
      child: Row(
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
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isLocked
                            ? Colors.grey.shade400
                            : const Color(0xFF0F2027))),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text("Moisture: $moistureStr",
                        style: GoogleFonts.outfit(
                            color: isLocked
                                ? Colors.grey.shade300
                                : const Color(0xFF4A6164),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF29B6F6).withOpacity(0.2),
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
                          color: Colors.orange.withOpacity(0.15),
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

          // Toggle button
          GestureDetector(
            onTap: isLocked ? null : () => _toggleWatering(zone),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: toggleBgColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : (isLocked
                        ? null
                        : [
                            BoxShadow(
                              color:
                                  const Color(0xFF2BCC71).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive
                        ? Icons.stop_rounded
                        : (isLocked
                            ? Icons.lock_rounded
                            : Icons.play_arrow_rounded),
                    color: toggleIconColor,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(toggleLabel,
                      style: GoogleFonts.outfit(
                          color: toggleIconColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(
      {required IconData icon,
      required String text,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.outfit(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Auto Mode Toggle — like a big ON/OFF switch
  // ═══════════════════════════════════════════════════════

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
      bgColor = Colors.grey.shade100;
      borderColor = Colors.grey.shade200;
      textColor = Colors.grey.shade400;
      icon = Icons.lock_rounded;
      label = 'Locked';
      subtitle = 'Cannot activate — tank level too low';
    } else if (isActive) {
      bgColor = const Color(0xFF2BCC71).withOpacity(0.1);
      borderColor = const Color(0xFF2BCC71).withOpacity(0.5);
      textColor = const Color(0xFF15803D);
      icon = Icons.toggle_on_rounded;
      label = 'Auto Mode ON';
      subtitle = 'Tap to deactivate';
    } else {
      bgColor = Colors.white.withOpacity(0.5);
      borderColor = const Color(0xFF0F2027).withOpacity(0.15);
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
                          color: textColor.withOpacity(0.6))),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2BCC71).withOpacity(0.2),
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
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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

  Widget _buildBlob({double? top, double? left, double? right, double? bottom, required double size, required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(color: Colors.transparent),
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
          curve: Interval(start.clamp(0.0, 1.0), (start + 0.6).clamp(0.0, 1.0), curve: Curves.easeOutQuart),
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
