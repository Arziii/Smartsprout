import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/utils/platform_utils.dart';
import '../presentation/providers/sensor_provider.dart';
import '../data/services/data_service.dart';

class CalibrationPage extends ConsumerStatefulWidget {
  final int zoneNumber;
  final String zoneName;

  const CalibrationPage({
    super.key,
    required this.zoneNumber,
    required this.zoneName,
  });

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0; // 0=intro, 1=dry, 2=wet, 3=done

  bool _dryDone = false;
  bool _wetDone = false;
  bool _dryRunning = false;
  bool _wetRunning = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  int get _zoneIndex => widget.zoneNumber - 1;

  Future<void> _runDryCalibration() async {
    final dataService = ref.read(dataServiceProvider);
    if (dataService == null) return;
    setState(() => _dryRunning = true);
    try {
      await dataService.runDryCalibration(widget.zoneNumber);
      // Pi samples 10 ADC readings @ 20ms each = ~200ms, plus command latency
      await Future.delayed(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[CAL] Dry calibration error: $e');
    }
    if (mounted) {
      setState(() {
        _dryRunning = false;
        _dryDone = true;
      });
    }
  }

  Future<void> _runWetCalibration() async {
    final dataService = ref.read(dataServiceProvider);
    if (dataService == null) return;
    setState(() => _wetRunning = true);
    try {
      await dataService.runWetCalibration(widget.zoneNumber);
      await Future.delayed(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[CAL] Wet calibration error: $e');
    }
    if (mounted) {
      setState(() {
        _wetRunning = false;
        _wetDone = true;
      });
    }
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  // ─── Build ───────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currentMoisture = sensorData.soilMoisture.length > _zoneIndex
        ? sensorData.soilMoisture[_zoneIndex]
        : -1.0;
    final isFault = sensorData.hasBedFault(_zoneIndex);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "${widget.zoneName} Calibration",
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F2027),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back_rounded,
                  color: isDark ? Colors.white : const Color(0xFF0F2027),
                  size: 20),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF0F172A), const Color(0xFF1A2C2E)]
                      : [const Color(0xFFF0FDF4), const Color(0xFFCCFBF1)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildProgressBar(isDark),
                _buildLiveReadingChip(currentMoisture, isFault, isDark),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildIntroPage(isDark),
                      _buildDryPage(isDark),
                      _buildWetPage(isDark),
                      _buildDonePage(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Progress bar ────────────────────────────────────
  Widget _buildProgressBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Row(
        children: List.generate(3, (i) {
          final stepIdx = i + 1;
          final isActive = _currentStep == stepIdx;
          final isDone = _currentStep > stepIdx;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: isDone
                    ? const Color(0xFF2BCC71)
                    : isActive
                        ? const Color(0xFF29B6F6)
                        : (isDark
                            ? Colors.white12
                            : const Color(0xFFDEE7E9)),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Live reading chip ───────────────────────────────
  Widget _buildLiveReadingChip(
      double moisture, bool isFault, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isFault
                    ? Colors.orange.withValues(
                        alpha: 0.5 + _pulseController.value * 0.5)
                    : const Color(0xFF2BCC71).withValues(
                        alpha: 0.5 + _pulseController.value * 0.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isFault
                ? "Zone ${widget.zoneNumber} — Sensor fault"
                : "Zone ${widget.zoneNumber} — ${moisture.toStringAsFixed(1)}% moisture (live)",
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : const Color(0xFF4A6164),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Page 0: Intro ──────────────────────────────────
  Widget _buildIntroPage(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF29B6F6), Color(0xFF2BCC71)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: isLiteMode
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF2BCC71).withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
              ),
              child:
                  const Icon(Icons.tune_rounded, color: Colors.white, size: 52),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "2-Step Calibration",
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F2027),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Sets the 0% and 100% moisture references for ${widget.zoneName}. Takes about 30 seconds.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : const Color(0xFF4A6164),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _buildStepPreview(
            "Step 1",
            "Dry Point — 0%",
            "Remove probe from soil and expose to air",
            Icons.air_rounded,
            const Color(0xFFFFA726),
            isDark,
          ),
          const SizedBox(height: 10),
          _buildStepPreview(
            "Step 2",
            "Wet Point — 100%",
            "Submerge probe fully in clean water",
            Icons.water_drop_rounded,
            const Color(0xFF29B6F6),
            isDark,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _nextPage,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2BCC71),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              "Start Calibration →",
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPreview(String label, String title, String subtitle,
      IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE8F1F2)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.5)),
                Text(title,
                    style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF0F2027))),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF4A6164))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Page 1: Dry calibration ─────────────────────────
  Widget _buildDryPage(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepBadge("Step 1 of 2 — Dry Point", const Color(0xFFFFA726)),
          const SizedBox(height: 14),
          Text("Set Dry Point",
              style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F2027),
                  letterSpacing: -0.5)),
          Text("0% Reference",
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFFA726))),
          const SizedBox(height: 20),
          _buildInstructionCard(
            icon: Icons.air_rounded,
            iconColor: const Color(0xFFFFA726),
            borderColor: const Color(0xFFFFA726),
            header: "Prepare the probe",
            steps: const [
              "Remove the probe from the soil.",
              "Wipe it dry with a clean cloth.",
              "Leave it in open air for 10–15 seconds.",
              "Tap \"Set Dry Point\" once ready.",
            ],
            isDark: isDark,
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _dryDone
                ? _buildSuccessBtn(
                    "Dry Point Set ✓ — Next →", _nextPage, const Color(0xFF2BCC71))
                : _dryRunning
                    ? _buildLoadingBtn("Calibrating…", const Color(0xFFFFA726))
                    : FilledButton(
                        onPressed: _runDryCalibration,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFA726),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text("Set Dry Point (0%)",
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Page 2: Wet calibration ─────────────────────────
  Widget _buildWetPage(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepBadge("Step 2 of 2 — Wet Point", const Color(0xFF29B6F6)),
          const SizedBox(height: 14),
          Text("Set Wet Point",
              style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F2027),
                  letterSpacing: -0.5)),
          Text("100% Reference",
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF29B6F6))),
          const SizedBox(height: 20),
          _buildInstructionCard(
            icon: Icons.water_drop_rounded,
            iconColor: const Color(0xFF29B6F6),
            borderColor: const Color(0xFF29B6F6),
            header: "Submerge the probe",
            steps: const [
              "Get a container of clean water.",
              "Submerge the probe fully — up to the cable end.",
              "Hold steady for 5 seconds.",
              "Tap \"Set Wet Point\" while still submerged.",
            ],
            isDark: isDark,
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _wetDone
                ? _buildSuccessBtn(
                    "Wet Point Set ✓ — Finish", _nextPage, const Color(0xFF2BCC71))
                : _wetRunning
                    ? _buildLoadingBtn("Calibrating…", const Color(0xFF29B6F6))
                    : FilledButton(
                        onPressed: _runWetCalibration,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF29B6F6),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text("Set Wet Point (100%)",
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Page 3: Done ────────────────────────────────────
  Widget _buildDonePage(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFF2BCC71).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF2BCC71), size: 58),
            ),
          ),
          const SizedBox(height: 20),
          Text("Calibration Complete!",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F2027),
                  letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(
            "${widget.zoneName} now shows accurate 0%–100% moisture based on your environment.",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF4A6164),
                height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2BCC71)
                  .withValues(alpha: isDark ? 0.1 : 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF2BCC71).withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF2BCC71), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Tap 'Force Sync' to push the updated calibration to Firestore and see new readings immediately.",
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF4A6164),
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              final ds = ref.read(dataServiceProvider);
              if (ds != null) await ds.forceSync();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Force sync sent — readings will update shortly."),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: Text("Force Sync",
                style: GoogleFonts.outfit(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF29B6F6),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                  color: isDark ? Colors.white24 : const Color(0xFFDEE7E9)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text("Close",
                style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF4A6164))),
          ),
        ],
      ),
    );
  }

  // ─── Shared helpers ──────────────────────────────────
  Widget _buildStepBadge(String label, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ),
      ],
    );
  }

  Widget _buildInstructionCard({
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required String header,
    required List<String> steps,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 12),
              Text(header,
                  style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F2027))),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(bottom: e.key < steps.length - 1 ? 8 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFF0F7F4),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text("${e.key + 1}",
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white60
                                    : const Color(0xFF4A6164))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF4A6164),
                              height: 1.4)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSuccessBtn(String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      key: ValueKey('success_$label'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBtn(String label, Color color) {
    return Container(
      key: ValueKey('loading_$label'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}
