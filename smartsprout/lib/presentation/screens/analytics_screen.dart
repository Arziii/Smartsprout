import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Garden background
          Positioned.fill(
            child: Image.asset(
              'assets/images/dashboard_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFFF0F4EE)),
            ),
          ),
          // 60% white frosted overlay
          Positioned.fill(
            child: Container(color: Colors.white.withValues(alpha: 0.60)),
          ),
          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildChartCard(
                    context,
                    title: 'Soil Moisture Trend (7 Days)',
                    color: Colors.brown,
                    spots: const [
                      FlSpot(0, 45),
                      FlSpot(1, 40),
                      FlSpot(2, 35),
                      FlSpot(3, 80),
                      FlSpot(4, 75),
                      FlSpot(5, 68),
                      FlSpot(6, 60),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildChartCard(
                    context,
                    title: 'Water Usage (Liters)',
                    color: Colors.blue,
                    spots: const [
                      FlSpot(0, 2.5),
                      FlSpot(1, 2.0),
                      FlSpot(2, 2.8),
                      FlSpot(3, 1.5),
                      FlSpot(4, 3.0),
                      FlSpot(5, 2.2),
                      FlSpot(6, 2.4),
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context,
      {required String title,
      required Color color,
      required List<FlSpot> spots}) {
    return Card(
      elevation: 4,
      color: Colors.white.withValues(alpha: 0.90),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
