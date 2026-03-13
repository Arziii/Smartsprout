import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sensor_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensorData = ref.watch(sensorDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Sprout Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO Navigate to settings
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSensorGrid(sensorData, context),
              const SizedBox(height: 24),
              _buildTankVisual(sensorData.tankLevel, context),
              const SizedBox(height: 24),
              _buildFlowRateCard(sensorData.flowRate, context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorGrid(sensorData, BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildSensorCard(
          context,
          title: 'Soil Moisture',
          value: '${sensorData.soilMoisture.toStringAsFixed(1)}%',
          icon: Icons.water_drop,
          color: Colors.brown.shade400,
        ),
        _buildSensorCard(
          context,
          title: 'Temperature',
          value: '${sensorData.temperature.toStringAsFixed(1)}°C',
          icon: Icons.thermostat,
          color: Colors.orange.shade400,
        ),
        _buildSensorCard(
          context,
          title: 'Humidity',
          value: '${sensorData.humidity.toStringAsFixed(1)}%',
          icon: Icons.cloud,
          color: Colors.lightBlue.shade300,
        ),
      ],
    );
  }

  Widget _buildSensorCard(BuildContext context,
      {required String title,
      required String value,
      required IconData icon,
      required Color color}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              color.withOpacity(0.1),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTankVisual(double tankLevel, BuildContext context) {
    Color waterColor = Colors.lightBlue;
    if (tankLevel < 20) {
      waterColor = Colors.redAccent;
    } else if (tankLevel < 40) {
      waterColor = Colors.orangeAccent;
    }

    return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(children: [
              // Mock Tank Graphic
              Container(
                height: 100,
                width: 60,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 100 * (tankLevel / 100),
                  decoration: BoxDecoration(
                      color: waterColor.withOpacity(0.8),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6))),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Reservoir Level',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('${tankLevel.toStringAsFixed(0)}%',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: waterColor)),
                    const SizedBox(height: 8),
                    if (tankLevel < 20)
                      const Row(children: [
                        Icon(Icons.warning, color: Colors.redAccent, size: 16),
                        SizedBox(width: 8),
                        Text('Low Water Warning!',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                      ])
                  ]))
            ])));
  }

  Widget _buildFlowRateCard(double flowRate, BuildContext context) {
    return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.waves, color: Colors.teal.shade400)),
                    const SizedBox(width: 16),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Flow Rate',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('Current Output',
                              style: Theme.of(context).textTheme.bodySmall)
                        ])
                  ]),
                  Text('${flowRate.toStringAsFixed(1)} L/min',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary))
                ])));
  }
}
