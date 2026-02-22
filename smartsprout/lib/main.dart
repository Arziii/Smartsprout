import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_theme.dart';
import 'routes/app_router.dart';

void main() {
  runApp(
    const ProviderScope(
      child: SmartSproutApp(),
    ),
  );
}

class SmartSproutApp extends StatelessWidget {
  const SmartSproutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Smart Sprout',
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
