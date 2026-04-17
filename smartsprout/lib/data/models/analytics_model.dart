class DailyAnalytics {
  final int dayIndex; // 0 (oldest) to 6 (newest, today)
  final double avgMoisture;
  final double avgTemp;
  /// True when the Pi actually wrote telemetry for this day.
  /// False means no Firestore docs existed — chart should show a gap, not 0.
  final bool hasData;
  /// True when at least one sensor reading for this day was -1 (fault/disconnected).
  /// The chart plots this day at 0 with **amber** color coding so the user
  /// can tell the sensor was faulty — distinct from green (valid) and red (offline).
  final bool hasFault;

  const DailyAnalytics({
    required this.dayIndex,
    required this.avgMoisture,
    required this.avgTemp,
    this.hasData = true,
    this.hasFault = false,
  });
}
