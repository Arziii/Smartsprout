import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/analytics_model.dart';
import '../../data/services/data_service.dart';

final analyticsProvider = FutureProvider.autoDispose<List<DailyAnalytics>>((ref) async {
  final firebase = ref.watch(dataServiceProvider);
  if (firebase == null) {
    // Return empty metrics if no connection
    return List.generate(7, (i) => DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0));
  }
  return await firebase.fetchWeeklyAnalytics();
});
