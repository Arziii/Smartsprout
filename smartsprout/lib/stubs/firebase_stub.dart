// ═══════════════════════════════════════════════════════
// Firebase Stub for Linux (Raspberry Pi) Builds
// This file provides dummy classes that mirror the
// exact API surface used by the SmartSprout app.
// The Dart compiler sees these instead of the native
// Firebase packages, preventing linker crashes.
// ═══════════════════════════════════════════════════════

// ── firebase_core stubs ──
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
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.authDomain,
    this.storageBucket,
    this.measurementId,
    this.iosBundleId,
  });
}

// ── firebase_auth stubs ──
class FirebaseAuth {
  static final FirebaseAuth instance = FirebaseAuth._();
  FirebaseAuth._();
  Object? get currentUser => null;
  Future<void> signInAnonymously() async {}
  Future<void> signOut() async {}
}

// ── cloud_firestore stubs ──
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

class StubQuerySnapshot {
  List<StubQueryDocumentSnapshot> get docs => [];
}

class StubQueryDocumentSnapshot {
  Map<String, dynamic> data() => {};
}

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

class FieldValue {
  static dynamic serverTimestamp() => null;
}

class Settings {
  const Settings({dynamic persistenceEnabled});
}

class GetOptions {
  const GetOptions({dynamic source});
}

class Source {
  static const server = 'server';
}
