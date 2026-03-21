#!/bin/bash
# ═══════════════════════════════════════════════════════
# SmartSprout Pi Linux Build Script
# Run from: ~/Smartsprout/smartsprout
# ═══════════════════════════════════════════════════════
set -e

echo "=========================================="
echo "  SmartSprout Pi Build Script"
echo "=========================================="

# ── Step 1: Comment out Firebase packages from pubspec.yaml ──
echo "[1/4] Patching pubspec.yaml to remove native Firebase..."
sed -i 's/^  firebase_core:/#  firebase_core:/' pubspec.yaml
sed -i 's/^  firebase_auth:/#  firebase_auth:/' pubspec.yaml
sed -i 's/^  cloud_firestore:/#  cloud_firestore:/' pubspec.yaml

# ── Step 2: Create the stub directory and file ──
echo "[2/4] Writing lib/stubs/firebase_stub.dart..."
mkdir -p lib/stubs
cat > lib/stubs/firebase_stub.dart << 'STUBEOF'
class Firebase {
  static Future<void> initializeApp({dynamic options}) async {}
}
class FirebaseOptions {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? authDomain;
  final String? storageBucket;
  final String? measurementId;
  final String? iosBundleId;
  const FirebaseOptions({
    required this.apiKey, required this.appId,
    required this.messagingSenderId, required this.projectId,
    this.authDomain, this.storageBucket, this.measurementId, this.iosBundleId,
  });
}
class FirebaseAuth {
  static final FirebaseAuth instance = FirebaseAuth._();
  FirebaseAuth._();
  Object? get currentUser => null;
  Future<void> signInAnonymously() async {}
  Future<void> signOut() async {}
}
class FirebaseFirestore {
  static final FirebaseFirestore instance = FirebaseFirestore._();
  FirebaseFirestore._();
  dynamic settings;
  StubCollectionReference collection(String path) => StubCollectionReference();
}
class StubCollectionReference {
  StubDocumentReference doc([String? path]) => StubDocumentReference();
  StubCollectionReference where(dynamic field, {dynamic isGreaterThanOrEqualTo}) => this;
  StubCollectionReference orderBy(dynamic field, {dynamic descending}) => this;
  Future<StubQuerySnapshot> get([dynamic options]) async => StubQuerySnapshot();
  Future<void> add(Map<String, dynamic> data) async {}
}
class StubQuerySnapshot { List<StubQueryDocumentSnapshot> get docs => []; }
class StubQueryDocumentSnapshot { Map<String, dynamic> data() => {}; }
class StubDocumentReference {
  Future<StubDocumentSnapshot> get([dynamic options]) async => StubDocumentSnapshot();
  Future<void> update(Map<String, dynamic> data) async {}
  Future<void> set(Map<String, dynamic> data, [dynamic options]) async {}
  Stream<StubDocumentSnapshot> snapshots() => const Stream.empty();
  StubCollectionReference collection(String path) => StubCollectionReference();
}
class SetOptions {
  final bool? merge;
  const SetOptions({this.merge});
}
class StubDocumentSnapshot {
  bool get exists => false;
  Map<String, dynamic>? data() => null;
}
class FieldValue { static dynamic serverTimestamp() => null; }
class Settings { const Settings({dynamic persistenceEnabled}); }
class GetOptions { const GetOptions({dynamic source}); }
class Source { static const server = 'server'; }
STUBEOF

# ── Step 3: Replace ALL Firebase imports across the entire lib/ tree ──
echo "[3/4] Replacing all Firebase imports with stub..."
find lib -type f -name '*.dart' -print0 | xargs -0 sed -i \
  "s|import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;|import 'package:smartsprout/stubs/firebase_stub.dart';|g"
find lib -type f -name '*.dart' -print0 | xargs -0 sed -i \
  "s|import 'package:firebase_core/firebase_core.dart';|import 'package:smartsprout/stubs/firebase_stub.dart';|g"
find lib -type f -name '*.dart' -print0 | xargs -0 sed -i \
  "s|import 'package:firebase_auth/firebase_auth.dart';|import 'package:smartsprout/stubs/firebase_stub.dart';|g"
find lib -type f -name '*.dart' -print0 | xargs -0 sed -i \
  "s|import 'package:cloud_firestore/cloud_firestore.dart';|import 'package:smartsprout/stubs/firebase_stub.dart';|g"

# ── Step 4: Clean Build ──
echo "[4/4] Running flutter clean + build..."
flutter clean
flutter pub get
flutter build linux --release

echo "=========================================="
echo "  BUILD COMPLETE"
echo "  Output: build/linux/arm64/release/bundle/"
echo "=========================================="
