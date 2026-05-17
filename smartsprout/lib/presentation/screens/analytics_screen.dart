import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analytics_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    // Always fetch fresh data when the screen opens — bypasses the 1-hour
    // cache so the kiosk shows up-to-date analytics on every visit.
    Future.microtask(() {
      ref.read(analyticsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Analytics',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F2027),
              letterSpacing: -0.5,
            )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: isDark ? Colors.white70 : const Color(0xFF4A6164)),
            tooltip: 'Refresh Analytics',
            onPressed: () {
              ref.read(analyticsProvider.notifier).refresh();
            },
          ),
          const SizedBox(width: 8),
        ],
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
            child: ref.watch(analyticsProvider).when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2BCC71)),
                  ),
                  error: (e, st) => Center(
                      child: Text('Error loading analytics: $e',
                          style: const TextStyle(color: Colors.red))),
                  data: (data) {
                    // Anchor day labels to today: dayIndex 0 = 6 days ago, 6 = today
                    final today = DateTime.now();
                    final cutoff = DateTime(today.year, today.month, today.day)
                        .subtract(const Duration(days: 6));

                    // Generate UI FlSpots. By filtering out days with no data, 
                    // fl_chart will draw a continuous line connecting the available points.
                    final hasAnyData = data.any((d) => d.hasData == true);

                    final moistureSpots = hasAnyData
                        ? data
                            .where((d) => d.hasData == true)
                            .map((d) => FlSpot(d.dayIndex.toDouble(), d.avgMoisture))
                            .toList()
                        : const [FlSpot(0, 0)];

                    final tempSpots = hasAnyData
                        ? data
                            .where((d) => d.hasData == true)
                            .map((d) => FlSpot(d.dayIndex.toDouble(), d.avgTemp))
                            .toList()
                        : const [FlSpot(0, 0)];

                    return RefreshIndicator(
                      color: const Color(0xFF2BCC71),
                      onRefresh: () =>
                          ref.read(analyticsProvider.notifier).refresh(),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAnimatedItem(
                                0,
                                _buildChartCard(
                                  title: 'Soil Moisture Trend (7 Days)',
                                  subtitle: 'Average across all zones',
                                  color: const Color(0xFF8D6E63),
                                  icon: Icons.grass_rounded,
                                  spots: moistureSpots,
                                  cutoff: cutoff,
                                  hasAnyData: hasAnyData,
                                  dataPoints: data,
                                )),
                            const SizedBox(height: 24),
                            _buildAnimatedItem(
                                1,
                                _buildChartCard(
                                  title: 'Temperature Trend (7 Days)',
                                  subtitle: 'Daily average in °C',
                                  color: const Color(0xFFFF7043),
                                  icon: Icons.thermostat_rounded,
                                  spots: tempSpots,
                                  cutoff: cutoff,
                                  hasAnyData: hasAnyData,
                                  dataPoints: data,
                                )),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  /// Returns the short weekday name for [dayIndex] relative to [cutoff].
  /// dayIndex 0 = cutoff (6 days ago), dayIndex 6 = today.
  String _dayLabel(int dayIndex, DateTime cutoff) {
    final date = cutoff.add(Duration(days: dayIndex));
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1]; // DateTime.weekday: 1=Mon, 7=Sun
  }

  bool _isToday(int dayIndex) => dayIndex == 6;

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required List<FlSpot> spots,
    required DateTime cutoff,
    required bool hasAnyData,
    required List dataPoints,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Count how many days have gaps in this 7-day window
    final missingCount = dataPoints.where((d) => !(d.hasData as bool)).length;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: isDark ? Colors.white24 : Colors.white, width: 2),
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
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F2027))),
                          Text(subtitle,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF4A6164),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                // ── No-data legend chip ──
                if (missingCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 2,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1),
                            color: Colors.grey.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$missingCount day${missingCount == 1 ? '' : 's'} with no sensor data (shown as gaps)',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color:
                                isDark ? Colors.white38 : Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 220,
                  child: LineChart(
                    LineChartData(
                      // ── Always span all 7 days so every label renders ──
                      minX: 0,
                      maxX: 6,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                              color: const Color(0xFF4A6164)
                                  .withValues(alpha: 0.1),
                              strokeWidth: 1,
                              dashArray: [5, 5]);
                        },
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              // Hide min and max values to prevent overlapping with regular interval labels
                              // Only hide them if they are not the same (i.e., not a flat line)
                              if (meta.min != meta.max && (value == meta.min || value == meta.max)) {
                                return const SizedBox.shrink();
                              }
                              
                              return SideTitleWidget(
                                meta: meta,
                                space: 8,
                                child: Text(meta.formattedValue,
                                    style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: const Color(0xFF4A6164)
                                            .withValues(alpha: 0.7),
                                        fontWeight: FontWeight.w600)),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            reservedSize: 52,
                            getTitlesWidget: (value, meta) {
                              if (value != value.toInt()) {
                                return const SizedBox.shrink();
                              }
                              final idx = value.toInt();
                              if (idx < 0 || idx > 6) {
                                return const SizedBox.shrink();
                              }
                              final isToday = _isToday(idx);
                              final label =
                                  isToday ? 'Today' : _dayLabel(idx, cutoff);
                              final dp = dataPoints[idx];
                              final dayHasData = dp.hasData as bool;
                              final dayHasFault = dp.hasFault as bool;

                              // Look up the actual chart value for THIS chart
                              // (moisture or temperature) to decide color.
                              final spotIdx = spots.indexWhere((s) => s.x == idx);
                              final chartValue = spotIdx != -1 ? spots[spotIdx].y : null;

                              Color getLabelColor() {
                                if (!dayHasData) {
                                  return isDark ? Colors.red.shade400 : Colors.red.shade600; // Pi offline
                                }
                                // Valid data > 0 overrides fault — some sensors worked
                                if (chartValue != null && chartValue > 0) {
                                  return isDark ? Colors.green.shade400 : Colors.green.shade600;
                                }
                                // Value is 0 AND sensors faulted — amber
                                if (dayHasFault) {
                                  return isDark ? Colors.amber.shade400 : Colors.amber.shade600;
                                }
                                return isDark ? Colors.green.shade400 : Colors.green.shade600; // Valid green
                              }
                              
                              final isFaultDisplay = dayHasFault && (chartValue == null || chartValue <= 0);
                              final labelColor = getLabelColor();

                              return Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      label,
                                      style: GoogleFonts.outfit(
                                        fontSize: isToday ? 11 : 12,
                                        height: 1.2,
                                        color: labelColor,
                                        fontWeight: !dayHasData || isToday || isFaultDisplay
                                            ? FontWeight.w900
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    // ── Indicator dot/dash under the label ──
                                    if (!dayHasData)
                                      Text(
                                        '—',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          height: 1.0,
                                          color: labelColor,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: labelColor,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: color,
                          barWidth: 4,
                          isStrokeCapRound: true,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) {
                              return FlDotCirclePainter(
                                radius: 4,
                                color: Colors.white,
                                strokeWidth: 2,
                                strokeColor: color,
                              );
                            },
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: 0.3),
                                color.withValues(alpha: 0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
        final start = index * 0.15;
        final curve = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start.clamp(0.0, 1.0), (start + 0.6).clamp(0.0, 1.0),
              curve: Curves.easeOutQuart),
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
}
