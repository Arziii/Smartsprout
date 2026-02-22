import 'package:flutter/material.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  bool _isPumpOn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Irrigation Control'),
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
                  _buildModeSelector(context),
                  const SizedBox(height: 32),
                  _buildPumpControlCard(context),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.white.withValues(alpha: 0.90),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Operation Mode',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'manual',
                    label: Text('Manual'),
                    icon: Icon(Icons.touch_app)),
                ButtonSegment(
                    value: 'auto',
                    label: Text('Auto'),
                    icon: Icon(Icons.schedule)),
                ButtonSegment(
                    value: 'ml',
                    label: Text('Smart (ML)'),
                    icon: Icon(Icons.psychology)),
              ],
              selected: const {'manual'},
              onSelectionChanged: (Set<String> newSelection) {},
              style: ButtonStyle(
                side: WidgetStateProperty.all(BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.5))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPumpControlCard(BuildContext context) {
    return Card(
      elevation: 4,
      color: _isPumpOn
          ? Colors.teal.shade50.withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.90),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 20.0),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.water_drop,
                key: ValueKey(_isPumpOn),
                size: 64,
                color: _isPumpOn ? Colors.teal : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                    color:
                        _isPumpOn ? Colors.teal.shade800 : Colors.grey.shade600,
                  ),
              child: Text(_isPumpOn ? 'Pump is running...' : 'Pump is OFF'),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 60,
              child: ElevatedButton(
                onPressed: () => setState(() => _isPumpOn = !_isPumpOn),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPumpOn
                      ? Colors.redAccent
                      : Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  elevation: 6,
                ),
                child: Text(
                  _isPumpOn ? 'STOP PUMP' : 'START PUMP',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
