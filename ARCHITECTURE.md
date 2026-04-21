# Project Architecture Documentation

This document outlines the folder architecture for the Smart Sprout project, covering both the **Flutter Application** (Linux Kiosk & Mobile) and the **Raspberry Pi Controller**.

## 1. Flutter Application Architecture (`/smartsprout`)

The Flutter project follows a modular pattern inspired by Clean Architecture, separating data, logic, and presentation.

| Folder | Purpose | Database Connection |
| :--- | :--- | :--- |
| `lib/core/` | Global constants, app themes, and infrastructure utilities. | N/A |
| `lib/data/` | **Data Layer**: Handles all external data communication. | Connects to Firestore & Local Cache. |
| `lib/data/models/` | Data classes (POJOs) like `SensorData` and `DailyAnalytics`. | Reflects Firestore document schemas. |
| `lib/data/services/` | API wrappers. `DataService` handles Firestore REST/Native calls. | Directly queries `/devices`, `/commands`, `/telemetry`. |
| `lib/presentation/` | **UI Layer**: Everything the user sees and interacts with. | N/A |
| `lib/presentation/providers/` | State management using Riverpod. Bridges data to UI. | Reactive listeners to Firestore Snapshots. |
| `lib/presentation/screens/` | Primary page widgets (Dashboard, Settings, Analytics). | N/A |
| `lib/presentation/widgets/` | Reusable UI components (Gauge, KioskTextField, Charts). | N/A |
| `lib/routes/` | Navigation logic and route definitions. | N/A |

---

## 2. Raspberry Pi Controller Architecture (`/smartsproutrasberry`)

The Pi controller focuses on hardware interaction and cloud synchronization.

| Folder | Purpose | Database Connection |
| :--- | :--- | :--- |
| `drivers/` | Hardware-level code (`sensors.py`, `pump_watchdog.py`). | Reads hardware, Prep for `/telemetry`. |
| `network/` | Connectivity logic (`wifi_bridge.py`, `firebase_manager.py`, `auth_bouncer.py`). | Pushes to `/telemetry`, Pulls from `/commands`. |
| `storage/` | Local persistence (`local_db.py`, `device_config.json`, `telemetry.db`). | Local fallback for Firestore `/telemetry`. |
| `tools/` | Utility scripts for maintenance (`diagnose_pin.py`, `reset_button.py`). | N/A |
| (Root) | Entry points and configuration (`main.py`, `config.py`). | Orchestrates all DB interactions. |

---

## 3. Database Schema Mapping (Firestore)

The folder architecture is designed to support the following Firestore structure:

### `devices/{deviceId}` (Root Document)
- **Folder: `lib/data/models/sensor_model.dart`**
- Purpose: Stores live system status, offsets, and configuration.
- Fields: `systemStatus`, `soil_offsets`, `target_moisture`, `manual_heartbeat`, `system_lock`.

### `devices/{deviceId}/telemetry` (Subcollection)
- **Folder: `lib/data/models/analytics_model.dart`**
- Purpose: Persistent logs for historical analysis and charts.
- Fields: `timestamp`, `soil_moisture` (Map), `temperature`.

### `devices/{deviceId}/commands` (Subcollection)
- **Folder: `lib/data/services/data_service.dart`**
- Purpose: Asynchronous command queue for remote control.
- Fields: `command`, `payload`, `processed`, `timestamp`.

### `devices/{deviceId}/zones` (Subcollection)
- **Folder: `lib/presentation/screens/settings_screen.dart`**
- Purpose: Metadata for specific monitoring zones (e.g., plant images).
- Fields: `plant_image_name`.

---

## 4. Maintenance Notes

- **Adding Sensors**: New hardware drivers should be placed in `smartsproutrasberry/drivers/` and imported into `main.py`.
- **Database Changes**: If adding new Firestore collections, update `lib/data/services/data_service.dart` and define a corresponding model in `lib/data/models/`.
- **Local Persistence**: The `storage/telemetry.db` is the primary data source for the Linux Kiosk when internet connectivity is lost.
