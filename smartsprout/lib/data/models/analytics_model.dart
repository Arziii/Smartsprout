class DailyAnalytics {
  final int dayIndex; // 0 (oldest) to 6 (newest, today)
  final double avgMoisture;
  final double avgTemp;
  /// True when the Pi actually wrote telemetry for this day.
  /// False means no Firestore docs existed — chart should show a gap, not 0.
  final bool hasData;

  const DailyAnalytics({
    required this.dayIndex,
    required this.avgMoisture,
    required this.avgTemp,
    this.hasData = true,
  });
}
