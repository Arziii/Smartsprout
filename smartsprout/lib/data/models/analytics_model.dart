class DailyAnalytics {
  final int dayIndex; // 0 (oldest) to 6 (newest, today)
  final double avgMoisture;
  final double avgTemp;

  const DailyAnalytics({
    required this.dayIndex,
    required this.avgMoisture,
    required this.avgTemp,
  });
}
