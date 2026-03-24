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
10. CONCLUSION


═══════════════════════════════════════════════════════════════════


1. EXECUTIVE SUMMARY


This document outlines the architectural and functional specifications for the Smart Sprout mobile-enabled smart system control application, utilizing a "Zero-Trust" IoT architecture. The system's primary objective is to provide users with secure, seamless remote management capabilities for smart devices, exemplified by a watering system, accessible remotely via an encrypted cloud database, while strictly confining all local offline interactions to the Raspberry Pi's physical touchscreen. 

This dual operational mode—Secure IoT via Cloud and Local Offline via Touchscreen—completely eliminates local network vulnerabilities by removing Bluetooth (BLE) and Local Wi-Fi discovery logic. The Flutter application communicates exclusively through Cloud Firestore using a robust credential-based authentication system (Device ID + PIN), protecting user access and system integrity. This project aims to deliver a professional-grade solution that prioritizes data security, user experience, and system stability.


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
│ Dashboard       │ Live sensor cards, Tank visualization,    │ Cloud Only   │
│                 │ Sync Now button, Plant-image ghost BG,    │              │
│                 │ System Health navigable card              │              │
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


PHASE 4.2: FIREBASE & DEVICE-CENTRIC AUTHENTICATION [COMPLETED]
☑ Firebase Authentication (Anonymous Auth) + Firestore credential validation
☑ Device-centric login model (Device ID + PIN)
☑ Device-specific Firestore architecture implementations.
☑ Embedded Linux compatibility via `Platform.isLinux` lazy-loading (bypasses Firebase missing plugins).
☑ Physical Touchscreen Kiosk-mode authentication bypass.


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
☑ Simplified trigonometric math loops for water-wave animations on limited Pi 3B hardware.

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
☑ Pi stays in 30-min Eco-Mode 99% of the time; one tap wakes it for a sub-second cloud push.


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

PHASE 4.14: SYSTEM HEALTH SUMMARY PAGE [COMPLETED]
☑ System Health Page: New scrollable diagnostic screen with 5 status cards.
☑ Cards: Overall Status banner, Controller Connection, Reservoir Status, Sensor Integrity, Zone Breakdown.
☑ Dashboard Navigation: System Overview card wrapped in GestureDetector → pushes to SystemHealthPage.

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

PHASE 4.17: DIFFERENTIAL SYNC (ECO-MODE 2.0) [COMPLETED]
☑ Threshold Logic: Immediate cloud push if Temp Δ>1.5°C, Soil Δ>3%, or Tank Δ>5%.
☑ `_last_sent_telemetry` tracks baseline; `_should_differential_push()` checks deltas.
☑ Preserves 30-min Eco-Mode timer for normal conditions while catching critical changes.

PHASE 4.18: HARDWARE SAFETY & LED FEEDBACK [COMPLETED]
☑ Reset LED (GPIO 18): Rapid blink during 5s hold, solid ON on trigger, OFF on cancel.
☑ Pump Watchdog: `pump_watchdog.py` daemon auto-kills any relay ON > 120s at GPIO level.
☑ Works without internet — pure hardware-level flood prevention.

PHASE 4.19: MULTI-TIER PLATFORM OPTIMIZATION [COMPLETED]
☑ Platform Helpers: Created `platform_utils.dart` providing `isLiteMode`, `isPremiumMode`, `isDesktopMode`.
☑ Linux GPU Relief: Safely scrubbed heavy `BackdropFilter` (glassmorphism) and vector shadows (`BoxShadow`) from Kiosk UI.
☑ Memory Safety: Embedded 50MB `imageCache` limit exclusively for Linux to prevent Pi 3B 1GB RAM exhaustion.
☑ Desktop UX: Implemented `MouseRegion` hover glows and always-visible `Scrollbar` wrappers for Windows.
☑ Cross-Platform Firebase: Fallback to `firebase_stub.dart` enables zero-code-change Windows Desktop compilation.


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


Mobile App                           Cloud Firestore                          Raspberry Pi
───────────                          ───────────────                          ───────────
     │                                     │                                       │
     │───── Authenticate (ID+PIN) ────────►│                                       │
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

┌───────────────────────┬───────────────────────────┬─────────────────────────────┐
│ Component             │ Interface                 │ Physical Pin Allocation     │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ BME280 (Temp/Hum/Pres)│ I2C Bus 1 (0x76/77)       │ SDA: GPIO 2, SCL: GPIO 3    │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Non-Contact Tank Level│ Digital GPIO              │ Yellow (OUT): GPIO 5        │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ ADS1115 ADC (I2C)     │ I2C Bus 1 (Address 0x48)  │ SDA: GPIO 2, SCL: GPIO 3    │
│  ↳ Soil Moisture Bed 1│ Analog                    │ ADC Channel A0              │
│  ↳ Soil Moisture Bed 2│ Analog                    │ ADC Channel A1              │
│  ↳ Soil Moisture Bed 3│ Analog                    │ ADC Channel A2              │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Relay Header (Pump)   │ Digital GPIO (Active-Low) │ GPIO 17 (IN1)               │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Relay Header (Valve 1)│ Digital GPIO (Active-Low) │ GPIO 27 (IN2)               │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Relay Header (Valve 2)│ Digital GPIO (Active-Low) │ GPIO 22 (IN3)               │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Relay Header (Valve 3)│ Digital GPIO (Active-Low) │ GPIO 23 (IN4)               │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Factory Reset Button  │ Digital GPIO (Pull-Up)    │ GPIO 24 (Active-LOW to GND) │
│                       │                           │ Hold 5 seconds to trigger   │
├───────────────────────┼───────────────────────────┼─────────────────────────────┤
│ Reset Feedback LED    │ Digital GPIO (Output)     │ GPIO 18 (220Ω → LED → GND)  │
│                       │                           │ Blink/Solid/Off feedback    │
└───────────────────────┴───────────────────────────┴─────────────────────────────┘



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
(calculated via ultrasonic distance). The system utilizes a device-centric authentication model, where users gain 
access by verifying device-specific credentials (Device ID and PIN) via 
Firebase Authentication. Cloud Firestore provides the scalable database 
backend, naturally supporting offline-first data caching and automatic 
Technical Validation: Field testing demonstrated seamless cloud 
orchestration and multi-device concurrency. Multiple administrative 
clients were observed to receive real-time telemetry updates 
simultaneously, with command arbitration handled effectively by the 
Firestore-to-Python listener queue. The application maintains full 
systemic integrity...


═══════════════════════════════════════════════════════════════════


END OF DOCUMENT