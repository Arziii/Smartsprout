# 🌱 Smart Sprout — IoT Garden Automation System

A **Local-First, Cloud-Synced** smart garden system built with a Raspberry Pi 4 controller and a cross-platform Flutter application.

Smart Sprout employs a **Zero-Trust, Pi-Bouncer Authentication Architecture**: all PIN validation is performed exclusively on the trusted hardware node (Raspberry Pi), never on the client device. Remote communication is fully encrypted and routed through Firebase Cloud Firestore while local operations are air-gapped to the physical Raspberry Pi touchscreen (Kiosk Mode).

---

## 📑 Table of Contents
- [System Architecture](#-system-architecture)
- [Authentication Flow — Pi-Bouncer](#-authentication-flow--pi-bouncer)
- [Core Features](#-core-features)
- [Analytics Engine](#-analytics-engine)
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

The Pi-Bouncer is the cornerstone of Smart Sprout's security model. Instead of comparing passwords client-side, the Raspberry Pi acts as a **hardware-rooted authentication server** with enterprise-grade PBKDF2-HMAC-SHA256 hashing.

### Flow Diagram

```text
Flutter App              Firestore              Raspberry Pi 4
──────────               ─────────              ──────────────

① Generate UUID
  Write login_requests/
  {requestId}:           ──── CREATE ──────►
  { deviceId:"MyAlias",
    pin:"SecurePass1!",
    status:"pending" }
                                               ② on_snapshot fires
                                                  Pi reads request
                                               ③ Strict Alias Resolving
                                                  Does deviceId match Alias?
                                                  ✗ Fail → "not_found"
                                               ④ Rate-limit check
                                                  (In-memory store)
                                               ⑤ PBKDF2 vs stored hash
                                                  (Salting + 600k Iterations)
                                                  ✗ Fail →
                         ◄─── status:"error" ─────────────────
                                                  5th fail →
                         ◄─ status:"rate_limited" ────────────
                         locked_until:<epoch>
                                                  ✓ Pass →
                                               ⑥ mint Custom Token
                                                  uid = HW_MAC_ID (Immutable)
                         ◄─ status:"approved" ────────────────
                            token:"<JWT>"
⑦ signInWithCustomToken()
   Delete request doc
   Navigate → Dashboard
```

### State Table

| App State | Trigger | UI |
|---|---|---|
| `isLoading: true` | Login request written to Firestore | Spinner + "Contacting hardware..." |
| `status: approved` | Pi validated password, Token returned | Green snackbar → Dashboard |
| `status: error` | Incorrect password | Red error banner |
| `status: rate_limited` | 5 failed attempts | Amber countdown banner (15 min) |
| `status: not_found` | Alias/ID mismatch on hardware | "Device not found" banner |
| Timeout (15s) | Pi offline / no response | "Hardware Offline" banner |
| Quick Switch (Option B) | Firebase session still valid | Instant switch, no password needed |

---

## ✨ Core Features

- **Pi-Bouncer Zero-Trust Auth**: Password validation runs exclusively on the Raspberry Pi via Firebase Admin SDK. The Flutter app never sees the stored hash. Rate limiting enforces a 15-minute lockout after 5 failed attempts (defending against brute force).
- **Strict Alias Login**: If a custom device name (e.g., "Reyche's Garden") is set, the hardware explicitly disables the raw Hardware MAC ID for logins. This prevents unauthorized access even if the factory MAC is known, requiring an attacker to know both the private alias and the password.
- **Enterprise Password Standard**: Enforces complex passwords (uppercase, lowercase, numbers, symbols) rather than legacy 4-digit PINs. Verification utilizes constant-time `hmac`-based comparisons to mitigate timing attacks.
- **Firebase Custom Token Auth**: On success, the Pi mints a Custom Token (`uid = HW_MAC_ID`). Firestore Security Rules use `request.auth.uid == deviceId` to restrict all device data to the authenticated owner.
- **Session-Reuse Quick Switch**: Saved accounts use Option B logic — if a Firebase Custom Token session is still valid, the app switches instantly with zero network round-trip. Expired sessions prompt re-authentication.
- **Dual Operation Modes**:
  - **Secure IoT**: Monitor and control globally via iOS, Android, and Windows Desktop apps. Features a beautifully persistent, theme-aware Dark Mode and optimized Snackbars for rapid, non-obtrusive feedback (1.5s).
  - **Air-Gapped Local**: Full operation via Pi's physical touchscreen, independent of internet, bypassing Firebase to use the local memory telemetry cache.
- **Eco-Mode + Differential Sync**: Hardware polling (3s) is decoupled from Firebase writes (30-min ceiling). Writes only fire on: ≥8% moisture delta, ≥3°C temperature delta, tank level change, system-status change, or manual FORCE_SYNC command. The Linux Kiosk UI reads directly from a local telemetry cache (`telemetry_cache.json`) to achieve zero-API-cost real-time responsiveness.
- **Pulse & Soak Auto-Watering**: Pulses water 5s → soaks 20s → re-reads moisture → repeats until target saturation reached or safety timeout fires.
- **Dead-Man's Switch**: During manual watering, a 10s heartbeat is required from the mobile app. If missed for >5s, the Pi kills all pumps immediately.
- **Pump Safety Watchdog**: GPIO-level daemon forces pump OFF if it runs >120 seconds.
- **Physical Factory Reset**: Hardware button (BCM 24) with LED feedback (BCM 18).

---

## 📊 Analytics Engine

The Analytics Screen provides a **rolling 7-day trend** of soil moisture and temperature, computed directly from Firestore telemetry history documents.

### Rolling Window Definition

| Variable | Value | Description |
|---|---|---|
| `today` | `DateTime.now()` | Current device time |
| `cutoff` | `today − 6 days` | Oldest day in the window |
| `dayIndex 0` | `cutoff` | 6 days ago |
| `dayIndex 6` | `today` | Always "Today" |

The window **slides forward every day automatically** — no manual refresh needed. On Monday the window is Mon→Sun (previous), on Tuesday it shifts to Tue→Mon, etc.

### Formula: Average Soil Moisture per Day

```
For each telemetry document on day N:

  soil_values = [bed1, bed2, bed3]   (from Firestore Map)
  avgSoil_doc = Σ(soil_values) / count(soil_values)

For the full day:

  avgMoisture[N] = Σ(avgSoil_doc for all docs in day N)
                  ─────────────────────────────────────
                         count(valid docs in day N)
```

### Formula: Average Temperature per Day

```
avgTemp[N] = Σ(temperature for all valid docs in day N)
             ────────────────────────────────────────────
                     count(valid docs in day N)
```

### Data Processing Pipeline

| Step | Location | Action |
|---|---|---|
| 1. Query | `DataService.fetchWeeklyAnalytics()` | Fetch telemetry docs where `timestamp ≥ cutoffSeconds`, limited to 500 docs |
| 2. Group | `data_service.dart` | Assign each doc to `dayIndex` via `date.difference(cutoff).inDays` |
| 3. Normalize types | `safeDouble()` helper | Cast Firestore `int`/`double`/`null` → `double` safely using `(v as num?)?.toDouble() ?? 0.0` |
| 4. Aggregate | Per-day loop | Sum moisture & temperature across all documents, divide by `validDocs` |
| 5. Flag gaps | `hasData` field | Set `hasData: false` if day has zero docs OR all docs threw parse errors |
| 6. Render | `analytics_screen.dart` | `hasData == true` → `FlSpot(x, y)`; `hasData == false` → `FlSpot.nullSpot` (visible gap) |

### Sentinel Value: `-1.0`

When the Pi cannot read a sensor (disconnected, I2C fault, BME280 failure), it writes **`-1.0`** instead of a real value. This is the Pi's fault indicator:

| Field | Normal Range | Fault Value | Meaning |
|---|---|---|---|
| `temperature` | 15.0 – 45.0 °C | `-1.0` | BME280 read failure |
| `soil_moisture.bedN` | 0.0 – 100.0 % | `-1.0` | ADS1115 / sensor disconnect |
| `humidity` | 10.0 – 100.0 % | `-1.0` | BME280 read failure |

> **Note:** `-1.0` is included in the daily average calculation. If the Pi was running but all sensors were disconnected, the chart correctly shows `-1` for that day — which is visually distinguishable from `0` (no data/gap).

### Chart Behavior Reference

| Condition | `hasData` | Chart Renders | Bottom Label |
|---|---|---|---|
| Pi published docs, sensors OK | `true` | Line segment with dot | Day name + ● colored dot |
| Pi published docs, sensors faulty | `true` | Line at `-1` | Day name + ● colored dot |
| Pi was off / no docs in Firestore | `false` | Gap (no line) | Day name + `—` grey dash |
| All docs on that day failed parsing | `false` | Gap (no line) | Day name + `—` grey dash |

### Firestore Quota Impact

| Operation | Frequency | Cost |
|---|---|---|
| Analytics fetch | On screen open + 1-hour cache | 1 read per query (max 500 docs counted) |
| Cache hit (navigating back) | Any time within 1 hour | **0 reads** |
| `limit(500)` cap | Always enforced | Prevents unbounded reads on large datasets |

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

### Password Security

| Property | Detail |
|---|---|
| **Hashing Algorithm** | PBKDF2-HMAC-SHA256 (600,000 iterations) with Per-Device Random Salting |
| **Verification** | Constant-time `hmac.compare_digest` to prevent Timing Attacks |
| **Storage Format** | `pbkdf2:<salt>:<hash>` in `device_config.json` (auto-migrated from legacy formats) |
| **Comparison** | Pi-side only — Flutter never evaluates hashing or logic locally. |
| **Transmission** | Raw password transmitted encrypted over TLS to `login_requests`, never directly written to `devices/` |
| **Post-auth Storage** | Password **not** stored locally on mobile (clean memory state) |

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
# 'password' or legacy 'hashed_pin' field in device_config.json to PBKDF2.
# No manual action needed. Watch for this log line:
#   [AUTH_BOUNCER] ✅ PIN silently upgraded from SHA-256 to PBKDF2-HMAC-SHA256.

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
