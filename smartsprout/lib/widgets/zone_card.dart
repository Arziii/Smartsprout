import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/platform_utils.dart';
import '../presentation/providers/sensor_provider.dart';
import '../widgets/plant_selection_grid.dart';
import '../data/services/data_service.dart';

class ZoneCard extends ConsumerStatefulWidget {
  final String zoneId;
  final String zoneName;
  final int rawMoisture; // Actual sensor reading from the Pi/database
  final double calibratedValue; // User-set threshold from Calibration screen
  final double targetMoisture; // Precision saturation target
  final int temp;
  final Animation<double> pulseAnim;
  final bool isFault;
  final VoidCallback? onCalibrate;

  const ZoneCard({
    super.key,
    required this.zoneId,
    required this.zoneName,
    this.rawMoisture = 0,
    this.calibratedValue = 0.0,
    this.targetMoisture = 65.0,
    required this.temp,
    required this.pulseAnim,
    this.isFault = false,
    this.onCalibrate,
  });

  @override
  ConsumerState<ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends ConsumerState<ZoneCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  bool get isTempFault => widget.temp <= -1;

  Color getMoodColor() {
    if (widget.isFault || widget.rawMoisture < 0) return Colors.grey.shade400;

    final val = widget.rawMoisture;
    final target = widget.targetMoisture.round();
    if (val < target - 15) return const Color(0xFFFFA726); // Dry
    if (val > target + 15) return const Color(0xFF29B6F6); // Wet
    return const Color(0xFF2BCC71); // Healthy
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = getMoodColor();
    final plantImageAsync = ref.watch(plantImageProvider(widget.zoneId));
    final plantImageName = plantImageAsync.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter:
          Platform.isWindows ? (_) => setState(() => _isHovered = true) : null,
      onExit:
          Platform.isWindows ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlantSelectionGrid(
                onPlantSelected: (filename) async {
                  final dataService = ref.read(dataServiceProvider);
                  if (dataService != null) {
                    await dataService.updateZoneImage(widget.zoneId, filename);
                  }
                },
              ),
            ),
          );
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A2C2E)
                  : Colors.white.withValues(alpha: isLiteMode ? 1.0 : 0.9),
              borderRadius: BorderRadius.circular(28),
              boxShadow: isLiteMode
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                      if (_isPressed)
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.2),
                          blurRadius: 15,
                          spreadRadius: -5,
                        ),
                      // Windows hover glow
                      if (_isHovered && Platform.isWindows)
                        BoxShadow(
                          color:
                              const Color(0xFF2BCC71).withValues(alpha: 0.25),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                    ],
              border: Border.all(
                color: isDark
                    ? Colors.white10
                    : Colors.white.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                // ── Full Background Image ──
                if (plantImageName != null && plantImageName.isNotEmpty) ...[
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/plants/$plantImageName',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.85),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            statusColor.withValues(alpha: 0.1),
                            statusColor.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(
                      Icons.local_florist_rounded,
                      size: 150,
                      color: statusColor.withValues(alpha: 0.1),
                    ),
                  ),
                ],

                // ── TOP-LEFT: Zone Name ──
                Positioned(
                  top: 16,
                  left: 14,
                  right: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.zoneName.replaceFirst(' (', '\n('),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color(0xFF0F2027),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── TOP-RIGHT: Current Moisture & Target Moisture Pills ──
                Positioned(
                  top: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Current Moisture
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.water_drop_rounded,
                                size: 14, color: Color(0xFF0277BD)),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.calibratedValue.round()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0277BD),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Target Moisture
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.eco_rounded,
                                size: 14, color: Color(0xFF1B8E4F)),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.targetMoisture.round()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1B8E4F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── BOTTOM: Moisture value OR Fault banner ──
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: widget.isFault || widget.rawMoisture < 0
                      // ── FAULT state ──
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0)
                                .withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.orange.shade200, width: 1.5),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'FAULT',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: Colors.orange,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      'Sensor disconnected',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                        color: Colors.orange,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      // ── CONNECTED state: live moisture + calibrate button ──
                      : Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFF2BCC71)
                                          .withValues(alpha: 0.4),
                                      width: 1.2),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.water_drop_rounded,
                                        color: Color(0xFF2BCC71), size: 16),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '${widget.rawMoisture}% moisture',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: Color(0xFF1B8E4F),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (widget.onCalibrate != null) ...[  
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: widget.onCalibrate,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFF29B6F6)
                                            .withValues(alpha: 0.4),
                                        width: 1.2),
                                  ),
                                  child: const Icon(Icons.tune_rounded,
                                      size: 18,
                                      color: Color(0xFF0277BD)),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
