import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

import 'core/constants/app_theme.dart';
import 'routes/app_router.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // ── Lite Mode: Cap image cache at 50 MB to protect Pi 3B's 1 GB RAM ──
  if (Platform.isLinux) {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  }

  if (!Platform.isLinux) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Disable Firestore offline persistence to avoid stale cache issues
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  runApp(
    const ProviderScope(
      child: SmartSproutApp(),
    ),
  );
}

class SmartSproutApp extends ConsumerStatefulWidget {
  const SmartSproutApp({super.key});

  @override
  ConsumerState<SmartSproutApp> createState() => _SmartSproutAppState();
}

class _SmartSproutAppState extends ConsumerState<SmartSproutApp> {
  @override
  Widget build(BuildContext context) {
    final goRouter = ref.watch(routerProvider);

    return MaterialApp.router(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Smart Sprout',
      theme: AppTheme.lightTheme,
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
