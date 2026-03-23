# 📱 Smart Sprout — Flutter Application

This directory contains the cross-platform Dart/Flutter source code for the Smart Sprout control interface. The application is designed to compile into two distinct targets safely sharing a Zero-Trust Firebase architecture:

1.  **Premium Interface (iOS / Android / Windows Desktop)**: Provides high-fidelity remote "Secure IoT Mode" access via Cloud Firestore.
2.  **Kiosk Interface (Linux ARM64)**: Runs directly on the Raspberry Pi's physical touchscreen, providing an air-gapped "Local Offline Mode" with performance optimizations.

---

## 🛠️ Tech Stack & Architecture

*   **Framework**: Flutter (Dart)
*   **State Management**: Riverpod (`flutter_riverpod`)
*   **Local Storage**: `shared_preferences` (for caching offline device credentials)
*   **Cloud Navigation**: Firebase `cloud_firestore` & `firebase_auth` (Mobile) / Firebase REST API (Linux)
*   **Routing**: `go_router` for deep linking and seamless navigation.
*   **Charts**: `fl_chart` for historical data analytics and beautiful UI reporting.

## 🚀 Getting Started

### Prerequisites

*   Flutter SDK (stable channel)
*   Firebase Project configured with valid `google-services.json` (Android) / `GoogleService-Info.plist` (iOS).

### Running Locally (Mobile)

```bash
flutter clean
flutter pub get
flutter run
```

### Building for Raspberry Pi (Linux Kiosk)

*Note: You must run this command directly on the Raspberry Pi.*

```bash
flutter config --enable-linux-desktop
flutter build linux
```

_For detailed Raspberry Pi environment setup, refer to `../RASPBERRY_PI_GUIDE.md`._

---

## 🔒 Security Model

The Flutter application relies strictly on a **Credential-Based Cloud Sync** mechanism:
- **No Local Network Access**: The app does not scan local IPs, use Bluetooth (BLE), or connect to local MQTT brokers.
- **Heartbeat Monitoring**: The UI actively listens to a `last_heartbeat` timestamp injected by the Python hardware controller. If the controller is offline or crashed for > 2 minutes, the UI automatically displays a **Controller Disconnected** warning overlay.
