import 'package:flutter/material.dart';

void main() => runApp(const TestApp());

class TestApp extends StatefulWidget {
  const TestApp({super.key});
  @override
  State<TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  bool _visible = false;
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Overlay(
          initialEntries: [
            OverlayEntry(builder: (context) {
              return Stack(
                children: [
                  Center(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _visible = !_visible),
                      child: Text('Toggle (_visible = $_visible)'),
                    ),
                  ),
                  if (_visible)
                    Positioned(
                      top: 50,
                      left: 50,
                      child: Container(width: 100, height: 100, color: Colors.red),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
