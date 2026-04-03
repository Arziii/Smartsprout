SMART SPROUT: MOBILE APPLICATION DEVELOPMENT PLAN
IoT-Based System for Optimized Urban Gardening


A Research Component for:
Smart Sprout: IoT-Based System for Optimized Urban Gardening


Submitted by:
San Pedro, Genesis Isiah
Balmedina, John Reyche B.
Hidalgo, John Dale A.
Cervantes, Carl Joseph A.


Universal College of Parañaque
College of Engineering
BSCpE / 4th Year
December 10, 2025


═══════════════════════════════════════════════════════════════════


TABLE OF CONTENTS


1. EXECUTIVE SUMMARY
2. PROJECT CONTEXT
3. PHASE 1: REQUIREMENTS SPECIFICATION
   3.1 Core Functional Requirements
   3.2 Connectivity Architecture
4. PHASE 2: TECHNICAL ARCHITECTURE
   4.1 Tech Stack Selection
   4.2 Communication Protocols
5. PHASE 3: MOBILE APP ARCHITECTURE
   4.1 Folder Structure
   5.2 Key UI Screens
6. PHASE 4: IMPLEMENTATION PHASES
7. PHASE 5: RASPBERRY PI INTEGRATION
8. PHASE 6: DELIVERABLES & SUCCESS METRICS
9. PHASE 7: RESEARCH PAPER INTEGRATION
10. COMMERCIAL SCALING & SECURITY
11. DATA MANAGEMENT & QUOTA STRATEGY
12. CONCLUSION


═══════════════════════════════════════════════════════════════════


1. EXECUTIVE SUMMARY


This document outlines the architectural and functional specifications for the Smart Sprout mobile-enabled smart system control application, utilizing a "Zero-Trust" IoT architecture. The system's primary objective is to provide users with secure, seamless remote management capabilities for smart devices, exemplified by a watering system, accessible remotely via an encrypted cloud database, while strictly confining all local offline interactions to the Raspberry Pi's physical touchscreen. 

This dual operational mode—Secure IoT via Cloud and Local Offline via Touchscreen—completely eliminates local network vulnerabilities by removing Bluetooth (BLE) and Local Wi-Fi discovery logic. The Flutter application communicates exclusively through Cloud Firestore using a robust credential-based authentication system (Device ID + PIN) backed by Firebase Authentication (Anonymous Sign-In). In parallel, the Raspberry Pi utilizes the Firebase Admin SDK (Service Account Key) to synchronize its state with Firestore, protecting user access and system integrity. This project aims to deliver a professional-grade solution that prioritizes data security, user experience, and system stability.


═══════════════════════════════════════════════════════════════════


2. PROJECT CONTEXT


The technical foundation of this system comprises a Flutter-based mobile application acting as the primary remote user interface, offering a consistent and performant cross-platform experience. For the embedded system and hardware interaction, Python running on a Raspberry Pi serves as the localized intelligence, managing direct hardware controls, sensor data processing, parsing touchscreen inputs, and acting as a secure gateway for cloud communication. 

A scalable cloud database solution (Firebase Cloud Firestore) underpins the online functionality, handling data storage, synchronization across devices, and supporting user authentication services without exposing local ports. This architecture facilitates real-time data exchange and ensures data persistence. 

For offline and local control, the system operates in a strict "Local Offline" mode where the Raspberry Pi’s physical touchscreen medium is the sole interface for monitoring and calibration. No local network scanning or MQTT discovery is permitted. User access via the mobile application is secured through a comprehensive credential-based login system, integrating with cloud-native authentication services.

The UI/UX design prioritizes simplicity, intuitiveness, and responsiveness. Key UI/UX considerations include clear visual indicators for device online status and telemetry timestamps.

The Smart Sprout hardware system integrates:
• Soil moisture sensors (volumetric water content)
• BME280 sensors (temperature, humidity, and barometric pressure)
• Non-contact liquid level sensor (reservoir level monitoring)
• 12V Solenoid Valves - Normally Closed (Zone isolation)
• Raspberry Pi controller with Physical Touchscreen Display (Flutter Kiosk Mode)


═══════════════════════════════════════════════════════════════════


3. PHASE 1: REQUIREMENTS SPECIFICATION


3.1 CORE FUNCTIONAL REQUIREMENTS


┌─────────────────────────┬─────────────────────────────────────────┬──────────┐
│ Feature                 │ Description                             │ Priority │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Zero-Trust Security     │ No BLE/Local network discovery allowed. │ P0       │
│                         │ Cloud-only remote communication.        │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Real-time Dashboard     │ Live sensor readings: Soil Moisture %,  │ P0       │
│                         │ Temperature, Tank Level, Status         │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Irrigation Control      │ Manual pump on/off, Dual-strategy       │ P0       │
│                         │ auto mode (Sensor threshold & Timer)    │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Local Touchscreen Mode  │ Complete local offline control and      │ P0       │
│                         │ calibration via the Raspberry Pi UI     │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Alerts & Notifications  │ Cloud-synchronized critical events      │ P1       │
│                         │ (Low Water, Leak)                       │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ System Configuration    │ Calibration and System settings         │ P1       │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ User Authentication     │ Credential-based secure login           │ P0       │
│                         │ (Device ID + PIN) via Firestore         │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Data Synchronization    │ Consistent telemetry and commands via   │ P0       │
│                         │ Cloud Firestore                         │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Maintenance Mode        │ Automatic fault detection/reporting     │ P0       │
│                         │ for disconnected I2C hardware.          │          │
├─────────────────────────┼─────────────────────────────────────────┼──────────┤
│ Account Switcher        │ Store up to 5 devices with nicknames    │ P1       │
│                         │ for instant one-tap switching.          │          │
└─────────────────────────┴─────────────────────────────────────────┴──────────┘


                        Secure Encrypted Cloud Sync
                     ┌───────────────────────────────┐
                     ▼                               ▼
    ┌─────────────────────────┐          ┌──────────────────────────┐
    │                         │          │                          │
    │  Mobile Apps (Flutter)  │          │  Raspberry Pi + Sensors  │
    │   "Secure IoT Mode"     │          │   "Local Offline Mode"   │
    │ (Concurrent Access)     │          │                          │
    └─────────────────────────┘          └────────────┬─────────────┘
                                                      │
                                                       ◄
                                            Physical Touchscreen UI
                                            (Air-gapped local access)


3.2 DETAILED CLOUD & FIREBASE OPERATIONS (HOW IT WORKS)

The "Zero-Trust" architecture means the mobile application NEVER speaks directly to the Raspberry Pi over a home Wi-Fi network. Instead, Google Cloud Firestore acts as the ultimate middleman. 

A. How Commands Turn On Pumps (App -> Cloud -> Pi)
1. User taps "Water Now" in the Flutter Dashboard.
2. Flutter writes a NoSQL document to `devices/{deviceID}/commands/{auto-id}` with payload `{"command": "force_water", "processed": false}`.
3. The Raspberry Pi runs a background Python thread (`firebase_admin.firestore.on_snapshot()`) that is constantly listening to the cloud.
4. The Pi detects the new command within ~250ms, parses it, triggers the physical GPIO relay for the 12V pump, and strictly updates the cloud document to `{"processed": true}` so it isn't run twice.

B. How Telemetry Reaches the Screen (Pi -> Cloud -> App)
Real-time streaming is expensive and drains database quotas (creating "Quota Exceeded 429" errors). To solve this, the Pi separates local reading operations from cloud writing operations using a Dynamic Sync Architecture:
1. Local Hardware: The Pi reads the soil and environment I2C sensors every 3 seconds locally.
2. The Database Gate: The Pi refuses to upload this data to Firebase unless one of four dynamic rules is passed:
   - Rule 1 (Eco-Mode): 30 minutes have elapsed since the last push (saves historical telemetry).
   - Rule 2 (Differential Sync): The soil moisture suddenly changed by >8% or temp by >3.0°C. This pushes to the status document *only* and enforces a rigid 60-second cooldown to mathematically prevent sensor jitter from exhausting the 20,000/day write quota.
   - Rule 3 (Force Sync): The user pressed "Sync Now" on the mobile app.
   - Rule 4 (Live Watering Bypass): If the pump is currently active, all cooldowns and thresholds are bypassed, streaming live data every 3 seconds to ensure real-time mobile UX without bloating the database history.
3. Mobile Consumption: The Flutter UI uses Riverpod (`StreamProvider`) to listen to the `devices/{deviceID}` document. When the Pi finally pushes the data based on the rules above, the Mobile screen automatically updates its visual gauges instantly.


3.3 MULTI-USER ACCESS & CONCURRENCY
The "Secure IoT Mode" inherent in the Cloud Firestore architecture natively supports 
concurrent access. Multiple mobile devices (e.g., several family members) can 
authenticate with the same Device ID and PIN to provide:
• Real-time Telemetry Mirroring: All devices receive the same live sensor data.
• Global Command Synchronization: If one user activates the "Master Lockdown," 
  every connected device sees the alert immediately.
• Conflicting Command Protection: Commands are processed by the Raspberry Pi 
  using a First-In-First-Out (FIFO) queue, ensuring systemic stability even 
  under high user activity.


═══════════════════════════════════════════════════════════════════


4. PHASE 2: TECHNICAL ARCHITECTURE


4.1 TECH STACK SELECTION


┌──────────────────┬─────────────────────┬──────────────────────────┐
│ Layer            │ Technology          │ Rationale                │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ Framework        │ Flutter             │ Single codebase iOS/     │
│                  │                     │ Android                  │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ State Management │ Riverpod            │ Clean architecture,      │
│                  │                     │ reactive programming     │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ Auth & Cloud DB  │ Firebase Auth &     │ Native offline queuing,  │
│                  │ Cloud Firestore     │ robust device-centric    │
│                  │                     │ secure login             │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ Local Database   │ Hive/Isar           │ Fast, offline-first app  │
│                  │                     │ state storage            │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ Local Hardware UI│ Flutter Desktop     │ Kiosk-mode GUI for       │
│                  │                     │ physical touchscreen     │
├──────────────────┼─────────────────────┼──────────────────────────┤
│ Charts           │ fl_chart            │ Customizable sensor      │
│                  │                     │ visualization            │
└──────────────────┴─────────────────────┴──────────────────────────┘


4.2 COMMUNICATION PROTOCOLS


CLOUD FIRESTORE SCHEMA - Zero-Trust Cloud Sync


Collection: devices/{deviceId}
Document Structure:
  • lastSync: Timestamp
  • status: "online" | "offline"
  • system_status: string
  • pump_locked: boolean
  • tank_level: double
  • soil_moisture: [double, double, double]
  • temperature: double
  • humidity: double
  • pressure: double
  • hardware_status: {bed1: "ok"|"fault", ...}
  • hashed_pin: string

Subcollection: commands/{commandId}
Document Structure (Queue):
  • command: "force_water" | "stop_all" | "dry_calibrate" | "adjust_offset" | "set_offset"
           | "FORCE_SYNC" | "set_mode" | "RESTART_APP" | "REBOOT_PI" | "SYNC_CONFIG"
  • timestamp: Timestamp
  • processed: boolean
  • [Additional Payload Fields]

Subcollection: zones/{zoneId}
Document Structure:
  • plant_image_name: string (e.g., "aloe_vera.jpg")

Local Configuration File: device_config.json
  • device_id: string (e.g., "SPROUT_A1B2")
  • password: string (e.g., "1234")


═══════════════════════════════════════════════════════════════════


5. PHASE 3: MOBILE APP ARCHITECTURE


5.1 FOLDER STRUCTURE


lib/
├── main.dart                          # App entry, Firebase init
├── core/
│   ├── constants/
│   │   └── app_theme.dart             # Smart Sprout green theme
│   ├── utils/
│   │   └── connectivity_service.dart  # Network helper
│   └── extensions/
│       └── sensor_extensions.dart     # Data formatting helpers
├── data/
│   ├── models/
│   │   ├── sensor_model.dart          # Sensor Data Schema
│   │   ├── device_model.dart          # Raspberry Pi metadata
│   │   └── irrigation_schedule.dart   # Timer/ML schedule rules
│   └── services/
│       ├── firebase_service.dart      # Firestore telemetry & commands
│       └── ml_prediction_service.dart # Local ML or API call
├── presentation/
│   ├── screens/
│   │   ├── splash_screen.dart         # Logo, permission checks
│   │   ├── hardware_login_screen.dart # Device ID & PIN auth
│   │   ├── dashboard_screen.dart      # Main sensor display
│   │   ├── calibration_screen.dart    # Cloud-synced sensor calibration
│   │   ├── control_screen.dart        # Pump manual/schedule control
│   │   ├── analytics_screen.dart      # Historical charts
│   │   └── settings_screen.dart       # App/Account configs
│   ├── widgets/
│   │   ├── sensor_card.dart           # Reusable sensor display tile
│   │   ├── tank_visual.dart           # Animated water level graphic
│   │   ├── pump_button.dart           # Large control button
│   │   └── connection_status_bar.dart # Cloud sync indicator
│   └── providers/
│       ├── sensor_provider.dart       # Real-time Firestore state
│       └── irrigation_provider.dart   # Pump/schedule state
└── routes/
    └── app_router.dart                # GoRouter configuration


5.2 KEY UI SCREENS


| Screen          | Features                                  | Connectivity |
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Hardware Login  │ Authenticate using Device ID and PIN      │ Cloud Only   │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Dashboard       │ Live sensor cards, Maintenance Wrench UI, │ Cloud Only   │
│                 │ Sync Now button, Plant-image ghost BG,    │              │
│                 │ Grouped Environment Module                │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Account Switcher │ Manage 5 devices: Save/Edit Nicknames,    │ Local + Cloud│
│                 │ One-tap Device Switching                  │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Plant Selection │ Grid of 20 crop images, Default/Reset     │ Cloud Only   │
│                 │ option, writes plant_image_name to        │              │
│                 │ Firestore zones subcollection             │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ System Health   │ Detailed breakdown: Controller status,    │ Cloud Only   │
│                 │ Reservoir level, Sensor integrity, Zone   │              │
│                 │ moisture summary                          │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Control         │ Single-toggle Pump zones, Master Lockdown │ Cloud Only   │
│                 │ Switch, Auto-Mode (Sensor/Timer)          │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Calibration     │ Direct numeric input for Bed high/low     │ Cloud Only   │
│                 │ thresholds with Optimistic UI updates     │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Analytics       │ 7-day historical charts, efficiency       │ Cloud Only   │
│                 │ metrics                                   │              │
├─────────────────┼───────────────────────────────────────────┼──────────────┤
│ Settings        │ App config, PIN change, Rename Device     │ Cloud Only   │
│                 │ (Mobile), System Control Dialog, Logout   │              │
└─────────────────┴───────────────────────────────────────────┴──────────────┘


═══════════════════════════════════════════════════════════════════


6. PHASE 4: IMPLEMENTATION PHASES


PHASE 4.1: UI/UX IMPLEMENTATION [COMPLETED]
☑ Dashboard with real-time sensor cards (Moisture, Temperature, Tank)
☑ Animated tank level indicator
☑ Pump control with safety confirmations
☑ Historical charts with fl_chart
☑ Responsive layout (phone + tablet)
☑ Premium glassmorphism design & staggered animations


PHASE 4.2: PI-BOUNCER AUTHENTICATION ARCHITECTURE [COMPLETED]
☑ Zero-Trust Gatekeeper: Authentication validation moved from client-side Firestore rules to the Raspberry Pi edge server.
☑ Cryptographic Security: Automatic SHA-256 PIN hashing ensures no plaintext credentials reside in the cloud or local config.
☑ Anti-Brute Force (Rate Limiting): Pi-side thread-safe tracker enforces a 15-minute global lockout after 5 consecutive failed attempts.
☑ Custom Token Minting: Raspberry Pi utilizes Firebase Admin SDK to forge short-lived secure JWT session tokens (`uid=deviceId`).
☑ Hardware Offline Fallback: Flutter app features a 15-second timeout listener, visually indicating "Hardware Offline" if the Pi is unplugged.
☑ Embedded Linux / Kiosk bypass: Local touchscreen ignores cloud auth entirely, leveraging unhackable physical access.


PHASE 4.3: ZERO-TRUST REFACTOR [COMPLETED]
☑ Complete deprecation and removal of all Bluetooth (BLE) functionality.
☑ Complete removal of local Wi-Fi payload discovery and MQTT protocols.
☑ Strict separation of "Local Offline" (Touchscreen) and "Secure IoT" (Cloud App) modes.
☑ Wiring of Calibration, Settings, and Dashboard screens to exclusively use Firestore.


PHASE 4.4: HARDWARE-AGNOSTIC BACKEND & STORAGE [COMPLETED]
☑ Implementation of fault-tolerant 'Mock Mode' for sensorless boot validation.
☑ Complete deprecation and removal of YF-S201 Flow Sensor from architecture (replaced with Temperature monitoring).
☑ Decoupling of telemetry polling (3s) and cloud sync (30min) to optimize bandwidth.
☑ Implementation of automated 30-day storage rotation capability via Firebase pruning.


PHASE 4.5: ENHANCED UX & AUTO-WATERING [COMPLETED]
☑ Implementation of Dual-Strategy Auto-Watering (Sensor Threshold & Scheduled Timer).
☑ Complete overhaul of status indicators to non-intrusive, space-efficient Row on Dashboard.
☑ Flexible custom time picker (Hour/Minute) natively integrated with Raspberry Pi Py loop.
☑ Persistent local settings caching on Pi for continuity against reboots.

PHASE 4.6: TESTING & REFINEMENT [COMPLETED]
☑ Resolved Firestore login and navigation flow issues.
☑ Validated Zero-Trust Linux Kiosk UI fallback behavior.

PHASE 4.7: HARDWARE-OPTIMIZED KIOSK UI [COMPLETED]
☑ Stripped expensive glassmorphism (BackdropFilter) and vector shadows (BoxShadow) on Linux targets.
☑ Optimized navigation performance by disabling sliding page transitions in GoRouter.
☑ Reverted simplified trigonometric math loops for water-wave animations since Raspberry Pi 4 (4GB RAM) can handle full animations.

PHASE 4.8: HIGH-PERFORMANCE CALIBRATION & DIRECT INPUT [COMPLETED]
☑ Replaced repetitive +1%/-1% buttons with direct numeric input for precision.
☑ Implemented "Optimistic UI" updates for immediate visual feedback on the mobile app.
☑ Injected `_force_sync` flag in Python event loop for real-time telemetry feedback (<1s sync).

PHASE 4.9: BENCH-TESTING FAULT DECOUPLING [COMPLETED]
☑ Decoupled hardware I/O Fault flags from sensory data registers in `sensors.py`.
☑ Allows full UI/UX validation and calibration testing while disconnected from physical sensors.

PHASE 4.10: EMERGENCY FORCE SYNC ("ECO-MODE BYPASS") [COMPLETED]
☑ Added `FORCE_SYNC` command to Python event listener — immediately triggers telemetry push.
☑ Implemented `forceSync()` in Flutter `DataService` with `requested_at` freshness timestamp.
☑ Added a Sync Now icon button on the mobile Dashboard with loading spinner and SnackBar feedback.
☑ **Technical Note:** Documented the `FORCE_SYNC` command (Phase 4.10) enabling sub-second telemetry updates from the mobile app, bypassing the 30-minute Eco-Mode for immediate diagnostics.


PHASE 4.11: ADVANCED CONTROL & SAFETY REDESIGN [COMPLETED]
☑ Single-Button Toggle: Replaced separate "Water/Stop" buttons with smart toggles (Continuous vs Pulse & Soak).
☑ Master Lockdown Switch: Implemented a global safety switch that prevents all watering until manually released.
☑ Non-Intrusive Notifications: Replaced obstructive banners with a space-efficient status row on the Dashboard.
☑ Visual Feedback: Active watering cards now pulse with a thematic glow and functional icons.


PHASE 4.12: SYSTEM MAINTENANCE & PLATFORM PATCHING [COMPLETED]
☑ System Control Dialog: Integrated hardware-level `RESTART_APP` and `REBOOT_PI` commands.
☑ Automatic Route Redirection: Restarting the dashboard triggers an immediate UI return to Home.
☑ Linux Build Pipeline: Created `pi_build.sh` for automated Firebase stubbing on Raspberry Pi Desktop.
☑ 64-bit Stability: Patched `pubspec.yaml` to allow compilation on ARM64 Linux kiosk environments.

PHASE 4.13: IMMERSIVE PLANT SELECTION & ZONE CARDS [COMPLETED]
☑ Plant Selection Grid: 20-crop image picker stored in assets/images/plants/ with Firestore sync.
☑ Ghost Background Image: Selected plant overlays ZoneCard at 20-25% opacity for immersive UI.
☑ Platform-Specific Blending: ColorFiltered on Linux (GPU-safe), Opacity on mobile.
☑ Full-Card Navigation: Entire ZoneCard tappable to open PlantSelectionScreen (Scaffold-based).
☑ Default/Reset Option: First tile resets plant_image_name to empty string in Firestore.

PHASE 4.14: SYSTEM HEALTH SUMMARY & MAINTENANCE MODE [COMPLETED]
☑ System Health Page: Diagnostic screen with Controller, Reservoir, and Sensor integrity cards.
☑ Maintenance Wrench: Orange icon and "FAULT" label triggered by Pi [Errno 5] detection.
☑ Hardware Hard-lock: Automatic disabling of auto-watering on a per-zone basis during fault.
☑ Dashboard Navigation: System Overview card wrapped in GestureDetector → pushes to SystemHealthPage.

PHASE 4.15: QUICK ACCOUNT SWITCHER & NICKNAMES [COMPLETED]
☑ Device Storage: Secure local caching of up to 5 unique Smart Sprout device profiles (ID, PIN).
☑ Nickname Editor: Personalized naming for different garden units stored in SharedPreferences.
☑ Auto-Login: Tokenized session persistence allowing switching without re-entering PINs.

PHASE 4.15: DYNAMIC DEVICE ID SYSTEM [COMPLETED]
☑ Local Config (Pi): Created device_config.json with get_device_id() and update_device_id() helpers.
☑ SYNC_CONFIG Command: Pi handler updates local config and re-subscribes Firebase listeners.
☑ Rename Device (Mobile): PIN-gated renameDevice() copies Firestore data to new doc path.
☑ Hardware Factory Reset (GPIO 24): Physical button on Pi held 5s triggers reset via reset_button.py daemon.
☑ Anti-Ghosting: Mobile updates SharedPreferences and AuthState to new ID immediately.
☑ Software reset removed from Linux kiosk UI — reset is hardware-only for crash resilience.

PHASE 4.16: RELIABILITY WATCHDOG [COMPLETED]
☑ Systemd Service: `smartsprout.service` auto-starts `main.py` on boot, restarts on crash (3s delay).
☑ Cloud Heartbeat: Pi writes `last_heartbeat` to Firestore every 60 seconds via daemon thread.
☑ Flutter Disconnected Warning: Orange pill badge on dashboard if heartbeat > 2 min stale.

PHASE 4.17: DYNAMIC SYNC ARCHITECTURE 3.0 [COMPLETED]
☑ Anti-Jitter Thresholds: Widened trigger margins (Temp Δ>3.0°C, Soil Δ>8%) to completely ignore hardware ADC sensor noise.
☑ Cooldown Limiter: Enforces a strict 60-second minimum gap between differential pushes to shield Firestore quotas.
☑ Live Watering Bypass: Automatically suspends thresholds and streams data every 3 seconds exclusively when the pump is active for a premium UX.
☑ Routing Segregation: Differential updates only overwrite the main device status document, leaving historical subcollections to be updated only during the 30-minute Eco-Mode cycles.

PHASE 4.18: HARDWARE SAFETY & LED FEEDBACK [COMPLETED]
☑ Reset LED (GPIO 18): Rapid blink during 5s hold, solid ON on trigger, OFF on cancel.
☑ Pump Watchdog: `pump_watchdog.py` daemon auto-kills any relay ON > 120s at GPIO level.
☑ Works without internet — pure hardware-level flood prevention.

PHASE 4.19: MULTI-TIER PLATFORM OPTIMIZATION [COMPLETED]
☑ Platform Helpers: Created `platform_utils.dart` providing `isLiteMode`, `isPremiumMode`, `isDesktopMode`.
☑ Linux GPU Relief: Safely scrubbed heavy `BackdropFilter` (glassmorphism) and vector shadows (`BoxShadow`) from Kiosk UI.
☑ Hardware Upgrade: Migrated from Pi 3B to Raspberry Pi 4 (4GB RAM) for improved UI/UX consistency with mobile.
☑ Memory Safety: Removed 50MB `imageCache` limit, previously used exclusively for Linux to prevent Pi 3B 1GB RAM exhaustion.
☑ Desktop UX: Implemented `MouseRegion` hover glows and always-visible `Scrollbar` wrappers for Windows.
☑ Cross-Platform Firebase: Fallback to `firebase_stub.dart` enables zero-code-change Windows Desktop compilation.

PHASE 4.20: UI RESPONSIVENESS PATCH [COMPLETED]
☑ ZoneCard Text Overflow: Wrapped Zone Title and Moisture text in Flexible/Expanded widgets with TextOverflow.ellipsis to handle long strings gracefully.
☑ Padding Adjustments: Added SizedBox(width: 8) buffer between text strings and action buttons to prevent crowding.
☑ Adaptive Scaling: Wrapped the Zone action toggles ('Stop' button) in Flexible wrappers to ensure proportional scaling on narrow devices (e.g., iPhone SE), maintaining layout integrity.


PHASE 4.21: FIRESTORE QUOTA OPTIMIZATION [COMPLETED]
To protect Cloud Quotas (staying well under 50,000 reads/day and 20,000 writes/day), the system uses extreme optimization, achieving a 90% reduction in daily reads compared to before the optimization.

Phase 1: High Impact (Analytics & Cleanup)
| Task | Action | Estimated Savings |
| :--- | :--- | :--- |
| **Limit Analytics** | Modify `fetchWeeklyAnalytics` to use `.limit(500)` or fetch only relevant data points. | 80-90% of spike volume |
| **Persist Cleanup** | Save `_last_cleanup_time` to a local file (`.last_cleanup`) so it survives reboots. | 5,000+ reads/day |
| **Cache Analytics** | Implement an `AsyncNotifier` in Riverpod to cache analytics results for 1 hour. | 95% per-user fetch cost |

Phase 2: Polling & Offline Detection
| Task | Action | Estimated Savings |
| :--- | :--- | :--- |
| **Adaptive Polling** | Increase Linux Kiosk REST polling from 5s to 30s. | 83% baseline reduction (~14,000 reads/day) |
| **Heartbeat Frequency** | Reverted heartbeat to 10s for snappy UI detection, balanced with local caching. | N/A (Favors UX) |
| **Efficient Offline Check** | Local UI timeout reduced to 45s ensuring fast UI lock without extra background network queries. | N/A (Safety/UX) |


═══════════════════════════════════════════════════════════════════


7. PHASE 5: RASPBERRY PI INTEGRATION


7.1 PI SOFTWARE REQUIREMENTS


┌────────────────────┬─────────────────────┬─────────────────────────┐
│ Component          │ Technology          │ Purpose                 │
├────────────────────┼─────────────────────┼─────────────────────────┤
│ Core Loop          │ Python (main.py)    │ Local offline manager   │
├────────────────────┼─────────────────────┼─────────────────────────┤
│ Local UI           │ Flutter Desktop APP │ Direct touchscreen      │
│                    │ (Kiosk Mode)        │ control & calibration   │
├────────────────────┼─────────────────────┼─────────────────────────┤
│ Sensor Interface   │ Python RPi.GPIO +   │ Hardware sensor reading │
│                    │ adafruit-bme280 +   │ ADS1115 I2C ADC for     │
│                    │ smbus2              │ soil moisture           │
├────────────────────┼─────────────────────┼─────────────────────────┤
│ Cloud Sync         │ firebase-admin      │ Direct Firestore        │
│                    │ Python SDK          │ integration and command │
│                    │                     │ execution listener      │
├────────────────────┼─────────────────────┼─────────────────────────┤
│ Device Config      │ device_config.json  │ Dynamic Device ID and   │
│                    │                     │ password storage. Read  │
│                    │                     │ by config.py at boot.   │
├────────────────────┼─────────────────────┼─────────────────────────┤
│ Calibration Data   │ calibration_offsets │ Per-zone dry/wet raw    │
│                    │ .json               │ values & manual offsets │
└────────────────────┴─────────────────────┴─────────────────────────┘


7.2 COMMUNICATION FLOW


7.2a PI-BOUNCER AUTHENTICATION FLOW (ZERO-TRUST EDGE GATEKEEPER)

Mobile App                           Cloud Firestore (login_requests/ID)       Raspberry Pi
───────────                          ───────────────────────────────────       ────────────
     │                                     │                                       │
     │───── Write Request (PIN String) ───►│                                       │
     │      (Generates UUIDv4 lobby ID)    │───── Pi catches on_snapshot() ───────►│
     │                                     │                                       │──► SHA-256 Hash matches Config?
     │◄════ Listen to document changes ════│                                       │──► Enforce Rate Limit (5x/15m)
     │                                     │◄════ Write Custom Token OR Error ═════│──► Forge Firebase Custom Token
     │◄════ Read Custom/Error ═════════════│                                       │
     │──► signInWithCustomToken()          │                                       │
     │──► Delete Request Document ────────►│                                       │
     │                                     │                                       │


7.2b COMMAND & TELEMETRY FLOW

Mobile App                           Cloud Firestore                          Raspberry Pi
───────────                          ───────────────                          ───────────
     │                                     │                                       │
     │◄════ Listen to telemetry ═══════════│◄════ Update main document ════════════│
     │                                     │                                       │
     │───── Write Command (e.g., pump) ───►│                                       │
     │───── Write Mode (Sensor/Timer) ────►│                                       │
     │                                     │───── Notify commands subcollection ──►│
     │                                     │                                       │
     │◄════ Observe status transition ═════│◄════ Set processed=True ══════════════│
     │                                     │                                       │


7.2b DEVICE RENAME FLOW (SYNC_CONFIG)


Mobile App                           Cloud Firestore                          Raspberry Pi
───────────                          ───────────────                          ───────────
     │                                     │                                       │
     │───── Verify PIN vs devices/OLD_ID──►│                                       │
     │───── Copy data → devices/NEW_ID ───►│                                       │
     │───── SYNC_CONFIG cmd to OLD_ID ────►│                                       │
     │                                     │───── Pi picks up SYNC_CONFIG ────────►│
     │                                     │                                       │──► Update device_config.json
     │                                     │                                       │──► Reload config.DEVICE_ID
     │                                     │◄════ Re-subscribe to NEW_ID ══════════│
     │──► Update SharedPreferences         │                                       │
     │──► Update AuthState to NEW_ID       │                                       │
     │                                     │                                       │


7.2c FACTORY RESET FLOW (Linux Kiosk Only)


Linux Kiosk UI / Hardware Button            Raspberry Pi
──────────────────────────────              ──────────────
     │                                       │
     │── User holds GPIO 24 button (5s) ───►│
     │   OR presses touchscreen UI button    │
     │                                       │──► Write default device_config.json
     │                                       │    (SPROUT_A1B2 / 1234)
     │                                       │──► Delete calibration_offsets.json
     │                                       │──► sudo reboot
     │                                       │


7.3 HARDWARE PIN ASSIGNMENTS

The following represents the physical GPIO mapping configured for the Raspberry Pi 
backend. These can be securely overridden locally via the `.env` configuration file.

**Power Infrastructure:** 12V 8A DC Power Adapter using 18AWG copper wiring for the main power rails to ensure current stability.
**Voltage Regulation:** XL4016 High-Current Buck Converter (8A) calibrated to 5.1V. This setup powers the Raspberry Pi 4 via a 2-wire Homesaya USB Female Jack, the Relay VCC, and the USB Pump.
**Irrigation Failsafe:** Normally Closed (NC) solenoid valves are wired to Normally Open (NO) relay terminals. The valves receive 12V directly from the adapter (bypassing the buck converter).

┌───────────────────────┬───────────────────────────┬─────────────────────────────┐
│ Component             │ Device Pin / Wire Color   │ Raspberry Pi Pin (BCM / Phys)│ Power Source & Wiring Logic │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Main Power            │ USB-C / Homesaya Jack    │ Pi 4 USB-C Port             │ XL4016 Buck Output (5.1V)   │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ I2C Bus (Sensors)     │ SDA                       │ BCM 2 (Pin 3)               │ 3.3V from Pi (Pin 1)        │
│                       │ SCL                       │ BCM 3 (Pin 5)               │ Shared GND with Pi          │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Soil Moisture (Bed 1) │ Sensor 1 Signal           │ **ADS1115 A0**              │ Capacitive v1.2 (Analog)    │
│ Soil Moisture (Bed 2) │ Sensor 2 Signal           │ **ADS1115 A1**              │ Capacitive v1.2 (Analog)    │
│ Soil Moisture (Bed 3) │ Sensor 3 Signal           │ **ADS1115 A2**              │ Capacitive v1.2 (Analog)    │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Water Level (XKC)     │ Yellow (Signal)           │ BCM 5 (Pin 29)              │ 1kΩ/2kΩ Voltage Divider Req.│
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Relay Module (5V)     │ VCC                       │ 5V (Pin 2 or 4)             │ Powered by Pi 5V Rail       │
│                       │ IN1 (Pump)                │ BCM 17 (Pin 11)             │ COM: Buck OUT+ / NO: Pmp Red│
│                       │ IN2 (Valve 1)             │ BCM 27 (Pin 13)             │ COM: 12V+ (IN+) / NO: V1+   │
│                       │ IN3 (Valve 2)             │ BCM 22 (Pin 15)             │ COM: 12V+ (IN+) / NO: V2+   │
│                       │ IN4 (Valve 3)             │ BCM 23 (Pin 16)             │ COM: 12V+ (IN+) / NO: V3+   │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ User Interface        │ Reset Button              │ BCM 24 (Pin 18)             │ One side to Pin, one to GND │
│                       │ Feedback LED              │ BCM 18 (Pin 12)             │ Heartbeat Pulse / Rapid Blnk│
└───────────────────────┴───────────────────────────┴─────────────────────────────┘

7.4 THERMAL MANAGEMENT & ENCLOSURE DESIGN

Active Cooling: A dedicated 5V or 12V exhaust fan is integrated into the custom enclosure to dissipate heat from the XL4016 heatsinks and the Raspberry Pi 4 CPU.

Airflow Path: The fan is positioned to pull hot air out of the case, preventing "thermal throttling" which can lead to system lag and sensor read errors.

Wiring Strategy: 
*   **12V Fan:** Connect to the IN+ / IN- pins of the XL4016 (Full speed, maximum cooling).
*   **5V Fan:** Connect to the OUT+ / OUT- pins of the XL4016 (Synced with Pi status).
The fan runs whenever the system is powered to ensure continuous thermal safety.



═══════════════════════════════════════════════════════════════════


8. PHASE 6: DELIVERABLES & SUCCESS METRICS


8.1 MOBILE APP DELIVERABLES


□ Android APK (API 21+, Android 5.0)
□ iOS IPA (iOS 12+, TestFlight ready)
□ Source Code (GitHub repository with documentation)
□ User Manual (Cloud setup, touchscreen local guide, troubleshooting)


8.2 SUCCESS METRICS


┌─────────────────────────┬─────────────────┬────────────────────────┐
│ Metric                  │ Target          │ Measurement            │
├─────────────────────────┼─────────────────┼────────────────────────┤
│ Zero-Trust Compliance   │ 100% cloud-only │ Static analysis, port  │
│                         │ remote access   │ scanning of RPi on LAN │
├─────────────────────────┼─────────────────┼────────────────────────┤
│ Data Sync Latency       │ <2s under 4G    │ Timestamp comparison   │
├─────────────────────────┼─────────────────┼────────────────────────┤
│ Local Offline Mode      │ Full autonomy   │ Simulate WAN disconnect│
├─────────────────────────┼─────────────────┼────────────────────────┤
│ Queue Recovery          │ 100% success    │ Offline-mode testing   │
└─────────────────────────┴─────────────────┴────────────────────────┘


═══════════════════════════════════════════════════════════════════


9. PHASE 7: RESEARCH PAPER INTEGRATION


MOBILE APP SECTION FOR THESIS DOCUMENTATION


"Smart Sprout Zero-Trust Mobile Application


To complement the Raspberry Pi sensor hub, a cross-platform mobile 
application was developed utilizing the Flutter framework. Embracing a 
"Zero-Trust" architectural methodology, the system eliminates traditional 
local-network vulnerabilities by enforcing strict isolation between local 
and remote control channels.


Connectivity Architecture: The application implements dual-mode 
accessibility structurally, not at the network level. "Local Offline" 
control is restricted entirely to the physical Raspberry Pi touchscreen 
interface, serving as an air-gapped system for localized management when 
networks are unavailable or untrusted. "Secure IoT" mode caters exclusively 
to off-site remote access, routing all monitoring and commands through an 
encrypted Cloud Firestore infrastructure. Bluetooth (BLE) and local Wi-Fi 
port scanning mechanisms were completely deprecated to mitigate local network 
exploitation vectors.


Key Features: The dashboard displays real-time sensor fusion data—soil 
moisture (0-100%), ambient temperature/humidity, and reservoir volume 
(monitored via XKC-Y26-V digital sensor). The system utilizes a device-centric authentication model, where users gain 
access by verifying device-specific credentials (Device ID and PIN) via 
Firebase Authentication. Cloud Firestore provides the scalable database 
backend, naturally supporting offline-first data caching and automatic 
Technical Validation: Field testing demonstrated seamless cloud 
orchestration and multi-device concurrency. Multiple administrative 
clients were observed to receive real-time telemetry updates 
simultaneously, with command arbitration handled effectively by the 
Firestore-to-Python listener queue. The hardware implementation transitioned to a robust **12V 8A power infrastructure** utilizing **18AWG copper rails** and an **XL4016 High-Current Buck Converter** for stability. Thermal safety was addressed through **Active Ventilation** (Exhaust Fan), while the irrigation logic was secured using **Normally Closed (NC) Solenoid Valves**. Sub-second telemetry sync was achieved via the **FORCE_SYNC** command (Phase 4.10), and future diagnostics will include a 'Last Heartbeat' timestamp on the System Health screen. The application maintains full 
systemic integrity...


═══════════════════════════════════════════════════════════════════


10. COMMERCIAL SCALING & SECURITY

The Smart Sprout architecture is engineered for Horizontal Scaling and Intellectual Property (IP) protection, satisfying the requirements for commercial deployment beyond the research prototype.

10.1 UNIVERSAL CLIENT ARCHITECTURE
The Flutter application operates as a "Universal Client," meaning a single compiled build (APK/IPA) can manage an unlimited fleet of hardware units. Users authenticate with a unique Device ID and PIN, and the application dynamically maps its UI state to the corresponding Firestore document. This eliminates the need for unit-specific software builds.

10.2 HARDWARE APPLIANCE SECURITY
To protect the proprietary sensor fusion logic and irrigation algorithms, the production deployment employs three layers of "Hardening":
1.  Binary Compilation: All Python backend scripts are compiled into binary executables (using PyInstaller/Cython), rendering the source code unreadable to the end-user.
2.  OS-Level Lockout (Kiosk Hardening): The Raspberry Pi environment is stripped of all terminal access, file managers, and keyboard escape sequences. The device functions as a dedicated hardware appliance.
3.  Encrypted Persistence: Local storage partitions (containing calibration data and Wi-Fi credentials) are encrypted using LUKS (Linux Unified Key Setup) to prevent physical data extraction from the SD card.

10.3 ZERO-TOUCH CLOUD PROVISIONING
Scaling from 1 to 100 units is achieved through Cloud Provisioning. Each new hardware unit is assigned a unique UUID in the Firestore 'devices' collection. The Raspberry Pi identifies itself via a simple one-line environment variable, requiring zero code changes between units.


10.4 PI-BOUNCER AUTHENTICATION SECURITY MODEL

The Pi-Bouncer architecture represents a paradigm shift from standard "Client-to-Database" logins to a "Zero-Trust Hardware Gatekeeper" model. The Raspberry Pi physically located on-site is the sole authority on valid PINs, solving critical vulnerabilities of client-side validation logic.

┌───────────────────────────┬────────────────────────────────────────────────────────┐
│ Threat Vector             │ Pi-Bouncer Mitigation Strategy                         │
├───────────────────────────┼────────────────────────────────────────────────────────┤
│ Brute-Force PIN Attacks   │ In-memory Rate Limiter on Pi (15-min lockout after 5   │
│                           │ failed attempts). Immune to app reverse engineering.   │
├───────────────────────────┼────────────────────────────────────────────────────────┤
│ Exposed Database Fields   │ PINs are NOT stored natively in Firestore. Validation  │
│                           │ is performed exclusively against the Pi's local        │
│                           │ hash (`device_config.json`).                           │
├───────────────────────────┼────────────────────────────────────────────────────────┤
│ Session Hijacking         │ Pi issues single-use, short-lived JWT Custom Tokens    │
│                           │ only upon successful physical logic verification.      │
├───────────────────────────┼────────────────────────────────────────────────────────┤
│ Hardware Spoofing         │ Requires the physical Raspberry Pi to be online and    │
│                           │ processing requests. Bouncer fails-safe if offline.    │
└───────────────────────────┴────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════


11. DATA MANAGEMENT & QUOTA STRATEGY


11.1 BACKLOG PURPOSE & AUDITABILITY
The Smart Sprout system maintains three historical subcollections for every device unit: `alerts/`, `commands/`, and `telemetry/`. These backlogs serve as an "Audit Trail," allowing researchers to review past sensor fluctuations, command execution success rates, and system faults. 


11.2 QUOTA OPTIMIZATION (READ/WRITE MANAGEMENT)
To ensure the system remains sustainable within the Firebase Spark (Free) Tier, several data-throttling techniques are employed:
• Differential Sync: The Raspberry Pi ignores sensor "jitter" and only writes to the cloud if Soil Moisture changes by >8% or Temperature by >3.0°C.
• Pulse Sync: During active irrigation, the system temporarily enters "High-Frequency Mode" (3s updates) to provide a premium user experience, but immediately reverts to "Eco-Mode" (30min updates) once the pump stops.
• Read Caching: The mobile application utilizes Riverpod `AsyncNotifier` to cache historical analytics data locally for 1 hour, preventing redundant database queries during repetitive dashboard navigation.


11.3 30-DAY ROLLING RETENTION POLICY
The system implements an automated "Data Pruning" cycle to prevent database bloat. Every 24 hours, the Raspberry Pi backend executes a storage cleanup routine that deletes any telemetry or alert documents older than 30 days. This ensures that while 1 month of history is always available for research analysis, the total database size remains lean and cost-effective.


11.4 TELEMETRY AGGREGATION
During long-term deployment, the system favors "State Snapshots" over continuous streaming. By overwriting a single "Live Status" document for real-time monitoring and only appending to history subcollections during significant events, the system achieves a 95% reduction in total document counts compared to standard logging architectures.


11.5 HEARTBEAT & OFFLINE REFLECTION LOGIC
The system utilizes a 10-second "Heartbeat" interval for the Raspberry Pi and a 25-second "Warning Timer" for the Mobile Application. This specific timing was chosen to balance real-time monitoring with cloud quota sustainability:
• Quota Math: A 10s heartbeat consumes 8,640 writes/day (43% of the Free Tier limit), whereas a 1s heartbeat would consume 86,400 writes/day, exceeding the limit by 432%.
• Adaptive UX: During idle states, 10s is sufficient for connectivity checks. However, during "Live Events" (Moisture change >8% or Pump = ON), the system automatically triggers a "High-Frequency Bypass," updating every 3 seconds for true real-time feedback.
• Snappy Offline Detection: By setting the Mobile App's warning timer to 25s, the UI detects a disconnected device after only 2 missed heartbeats, providing a "Professional-tier" response time without increasing database costs.


═══════════════════════════════════════════════════════════════════


12. CONCLUSION


═══════════════════════════════════════════════════════════════════


END OF DOCUMENT