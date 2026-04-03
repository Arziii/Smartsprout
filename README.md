# 🌱 Smart Sprout — IoT Garden Automation System

A **Local-First, Cloud-Synced** smart garden system built with a Raspberry Pi 4 controller and a cross-platform Flutter application.

Smart Sprout employs a **Zero-Trust, Pi-Bouncer Authentication Architecture**: all PIN validation is performed exclusively on the trusted hardware node (Raspberry Pi), never on the client device. Remote communication is fully encrypted and routed through Firebase Cloud Firestore while local operations are air-gapped to the physical Raspberry Pi touchscreen (Kiosk Mode).

---

## 📑 Table of Contents
- [System Architecture](#-system-architecture)
- [Authentication Flow — Pi-Bouncer](#-authentication-flow--pi-bouncer)
- [Core Features](#-core-features)
- [Security Model](#-security-model)
- [Hardware Pin Mapping](#-hardware-pin-mapping)
- [Quick Start Guide](#-quick-start-guide)
- [Scaling & Deployment](#-scaling--deployment)
- [Repository Structure](#-repository-structure)
- [License & Academic Context](#-license--academic-context)

---

## 🏗️ System Architecture

```text
                     Secure Encrypted Cloud Sync
                  ┌───────────────────────────────┐
                  ▼                               ▼
 ┌─────────────────────────┐          ┌──────────────────────────────────┐
 │                         │          │                                  │
 │ Flutter App (Mobile/PC) │          │  Raspberry Pi 4 (Python)         │
 │  "Pi-Bouncer Auth"      │          │  ├─ Sensor & Telemetry Loop       │
 │  + Riverpod State Mgmt  │          │  ├─ Auth Bouncer (auth_bouncer.py)│
 │  + Custom Token Auth    │          │  ├─ Firebase Admin SDK            │
 └─────────────────────────┘          │  └─ Flutter Kiosk UI             │
                                      └────────────┬─────────────────────┘
                                                   │
                                      ┌────────────┴─────────────┐
                                      │    Hardware Layer         │
                                      │                           │
                                      │ ADS1115  ─► 3x Soil      │
                                      │ BME280   ─► Temp/Hum/Pres │
                                      │ XKC-Y26-V─► Tank Level   │
                                      │ 4ch Relay─► Pump/Valves  │
                                      └──────────────────────────┘
```

---

## 🔐 Authentication Flow — Pi-Bouncer

The Pi-Bouncer is the cornerstone of Smart Sprout's security model. Instead of comparing PINs client-side, the Raspberry Pi acts as a **hardware-rooted authentication server**.

### Flow Diagram

```
Flutter App              Firestore              Raspberry Pi 4
──────────               ─────────              ──────────────

① Generate UUID
  Write login_requests/
  {requestId}:           ──── CREATE ──────►
  { deviceId, pin,
    status:"pending" }
                                               ② on_snapshot fires
                                                  Pi reads request
                                               ③ Rate-limit check
                                                  (In-memory store)
                                               ④ SHA-256(pin) verify
                                                  vs stored hash
                                                  ✗ Fail →
                         ◄─── status:"error" ─────────────────
                                                  5th fail →
                         ◄─ status:"rate_limited" ────────────
                         locked_until:<epoch>
                                                  ✓ Pass →
                                               ⑤ mint Custom Token
                                                  uid = deviceId
                         ◄─ status:"approved" ────────────────
                            token:"<JWT>"
⑥ signInWithCustomToken()
   Delete request doc
   Navigate → Dashboard
```

### State Table

| App State | Trigger | UI |
|---|---|---|
| `isLoading: true` | Login request written to Firestore | Spinner + "Contacting hardware..." |
| `status: approved` | Pi validated PIN, token returned | Green snackbar → Dashboard |
| `status: error` | Incorrect PIN | Red error banner |
| `status: rate_limited` | 5 failed attempts | Amber countdown banner (15 min) |
| Timeout (15s) | Pi offline / no response | "Hardware Offline" banner |
| Quick Switch (Option B) | Firebase session still valid | Instant switch, no PIN needed |

---

## ✨ Core Features

- **Pi-Bouncer Zero-Trust Auth**: PIN validation runs exclusively on the Raspberry Pi via Firebase Admin SDK. The Flutter app never sees the stored hash. Rate limiting enforces a 15-minute lockout after 5 failed attempts.
- **Firebase Custom Token Auth**: On success, the Pi mints a Custom Token (`uid = deviceId`). Firestore Security Rules use `request.auth.uid == deviceId` to restrict all device data to the authenticated owner.
- **Session-Reuse Quick Switch**: Saved accounts use Option B logic — if a Firebase Custom Token session is still valid, the app switches instantly with zero network round-trip. Expired sessions prompt re-authentication.
- **Dual Operation Modes**:
  - **Secure IoT**: Monitor and control globally via iOS, Android, and Windows Desktop apps.
  - **Air-Gapped Local**: Full operation via Pi's physical touchscreen, independent of internet.
- **Eco-Mode + Differential Sync**: Hardware polling (3s) is decoupled from Firebase writes (30-min ceiling). Writes only fire on: ≥8% moisture delta, ≥3°C temperature delta, tank level change, system-status change, or manual FORCE_SYNC command.
- **Pulse & Soak Auto-Watering**: Pulses water 5s → soaks 20s → re-reads moisture → repeats until target saturation reached or safety timeout fires.
- **Dead-Man's Switch**: During manual watering, a 10s heartbeat is required from the mobile app. If missed for >5s, the Pi kills all pumps immediately.
- **Pump Safety Watchdog**: GPIO-level daemon forces pump OFF if it runs >120 seconds.
- **Physical Factory Reset**: Hardware button (BCM 24) with LED feedback (BCM 18).

---

## 🛡️ Security Model

### Firestore Security Rules Summary

| Collection | Create | Read | Update | Delete |
|---|---|---|---|---|
| `devices/{deviceId}` | Pi (Admin SDK) | `auth.uid == deviceId` | `auth.uid == deviceId` | Pi only |
| `devices/{id}/telemetry` | Pi only | `auth.uid == deviceId` | Pi only | Pi only |
| `devices/{id}/commands` | `auth.uid == deviceId` | `auth.uid == deviceId` | Pi only | Pi only |
| `login_requests/{requestId}` | Anyone (validated payload) | Anyone (UUID secrecy) | Pi only | Anyone |

### Rate Limiting

| Parameter | Value |
|---|---|
| Max failed attempts | 5 |
| Lockout duration | 15 minutes |
| State storage | In-memory (resets on Pi reboot) |
| Lockout signal | `status: "rate_limited"` + `locked_until` epoch |

### PIN Security

| Property | Detail |
|---|---|
| Storage | SHA-256 hash in `device_config.json` (plaintext auto-migrated on first boot) |
| Comparison | Pi-side only — Flutter never reads stored hash |
| Transmission | Raw PIN sent to `login_requests`, never to `devices/` |
| Post-auth storage | PIN **not** stored locally on mobile (removed from `SavedDevice`) |

---

## 🔌 Hardware Pin Mapping (BCM Reference)

| Component | Device Pin / Color | Pin (BCM / Phys) | Power Source & Wiring Logic |
| :--- | :--- | :--- | :--- |
| **Main Power** | USB-C Input | **USB-C Port** | From 5V/5A Buck Module Primary |
| **I2C SDA** | SDA | **BCM 2** (Pin 3) | 3.3V from Pi (Pin 1) |
| **I2C SCL** | SCL | **BCM 3** (Pin 5) | Shared GND with Pi |
| **Water Level**| Yellow (Signal) | **BCM 5** (Pin 29) | Requires 1k/2k Voltage Divider |
| **Relay: Pump** | IN1 (Pump) | **BCM 17** (Pin 11) | COM: Buck OUT+ / NO: Pump Red |
| **Relay: Valve 1**| IN2 (Valve 1) | **BCM 27** (Pin 13) | COM: 12V+ / NO: Valve 1+ |
| **Relay: Valve 2**| IN3 (Valve 2) | **BCM 22** (Pin 15) | COM: 12V+ / NO: Valve 2+ |
| **Relay: Valve 3**| IN4 (Valve 3) | **BCM 23** (Pin 16) | COM: 12V+ / NO: Valve 3+ |
| **Reset Button**| Button Pin | **BCM 24** (Pin 18) | One side to Pin, one to GND |
| **Status LED** | Anode (+) | **BCM 18** (Pin 12) | Long leg (+) to Pin / GND |

---

## 🚀 Quick Start Guide

### 1. Raspberry Pi Setup (Controller & Kiosk)

For detailed OS preparation, see the [Raspberry Pi Kiosk Guide](./RASPBERRY_PI_GUIDE.md).

```bash
# 1. Install system dependencies
sudo apt-get update && sudo apt-get install -y i2c-tools python3-pip python3-dev libgpiod-dev

# 2. Clone the repository and setup Python environment
cd /home/smartsprout/Smartsprout/smartsproutrasberry
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 3. Configure credentials
cp .env.example .env
# Edit .env — set DEVICE_ID and FIREBASE_CREDENTIALS_PATH
# Place your firebase-adminsdk.json in smartsproutrasberry/

# 4. IMPORTANT: On first boot, auth_bouncer.py auto-migrates the plaintext
# 'password' field in device_config.json to a SHA-256 hash.
# No manual action needed. Watch for this log line:
#   [AUTH_BOUNCER] ✅ PIN migrated to SHA-256 hash. Plaintext removed.

# 5. Install the Reliability Watchdog (Systemd)
sudo cp smartsprout.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable smartsprout
sudo systemctl start smartsprout
```

### 2. Mobile App Setup (Flutter)

```bash
cd Smartsprout/smartsprout

# 1. Install dependencies (includes uuid package)
flutter pub get

# 2. Run on your target device (iOS/Android)
flutter run
```

### 3. First-Time Device Registration

1. Create a document in Firestore: `devices/{YOUR_DEVICE_ID}`
2. Add a minimal document body:
   ```json
   { "device_name": "My Garden", "status": "offline" }
   ```
3. The Pi-Bouncer reads the PIN from `device_config.json` — **no PIN stored in Firestore**.

---

## 🚀 Scaling & Deployment

The system is designed for **Zero-Touch Scaling**. To deploy multiple units:

### 1. Unified App Architecture
The Flutter app is a **Universal Client**. One APK/IPA works for all devices.

### 2. Per-Unit Pi Configuration

| Step | Action |
|---|---|
| 1 | Clone `smartsproutrasberry/` to the new Pi |
| 2 | Set `DEVICE_ID="SPROUT_NNN"` in `.env` |
| 3 | Set `password` in `device_config.json` (auto-hashed on first boot) |
| 4 | Register `SPROUT_NNN` as a new document in Firestore `devices/` |
| 5 | Provide customer with Device ID + default PIN |

### 3. Customer Experience
The customer enters their unique **Device ID** and included **PIN**. The app routes through the Pi-Bouncer, receives a Custom Token, and connects exclusively to their device's data.

---

## 📁 Repository Structure

```text
Smartsprout/
├── README.md                   # This overview
├── HARDWARE_SETUP.md           # Physical wiring & sensor specs
├── RASPBERRY_PI_GUIDE.md       # OS, Kiosk, and deployment guide
├── Smart Sprout Flutter.md     # Comprehensive Flutter architecture guide
├── DefensePreparation.md       # Defense Q&A, Firebase ops, security diagrams
│
├── smartsprout/                # Flutter UI (Mobile & Kiosk)
│   ├── firestore.rules         # ← Zero-Trust security rules (Pi-Bouncer)
│   ├── lib/
│   │   ├── data/               # Firestore services, Models, Config parsing
│   │   ├── presentation/
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart  # ← Pi-Bouncer login flow (Riverpod)
│   │   │   └── screens/
│   │   │       └── hardware_login_screen.dart  # ← Rate-limit UI & countdown
│   │   └── screens/            # Dashboard, Calibration, Setup
│   └── pubspec.yaml
│
└── smartsproutrasberry/        # Python Hardware Controller
    ├── main.py                 # Telemetry loop & differential sync
    ├── auth_bouncer.py         # ← Pi-Bouncer auth daemon (NEW)
    ├── firebase_manager.py     # Firestore telemetry & heartbeats
    ├── pump_watchdog.py        # Hardware safety shutoff daemon
    ├── reset_button.py         # Factory reset logic & LED feedback
    ├── sensors.py              # Hardware abstraction (I2C, GPIO)
    └── device_config.json      # Stores hashed_pin (auto-migrated)
```

---

## 📄 License & Academic Context

This project is part of a senior engineering capstone research initiative at the Universal College of Parañaque, focusing on scalable, secure, zero-trust IoT systems for urban agriculture.
