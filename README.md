# 🌱 Smart Sprout — IoT Garden Automation System

A **Local-First, Cloud-Synced** smart garden system built with a Raspberry Pi controller and a cross-platform Flutter application. 

Smart Sprout employs a pristine **Zero-Trust Architecture**: it strictly prohibits local network discovery (no BLE, no local MQTT). All remote communication is fully encrypted and routed through Firebase Cloud Firestore, while local operations are air-gapped to the physical Raspberry Pi touchscreen (Kiosk Mode).

---

## 📑 Table of Contents
- [System Architecture](#-system-architecture)
- [Core Features](#-core-features)
- [Hardware Pin Mapping](#-hardware-pin-mapping)
- [Quick Start Guide](#-quick-start-guide)
- [Repository Structure](#-repository-structure)
- [License & Academic Context](#-license--academic-context)

---

## 🏗️ System Architecture

```text
                     Secure Encrypted Cloud Sync
                  ┌───────────────────────────────┐
                  ▼                               ▼
 ┌─────────────────────────┐          ┌──────────────────────────┐
 │                         │          │                          │
 │ Flutter App (Mobile/PC) │          │  Raspberry Pi (Python)   │
 │   "Secure IoT Mode"     │          │   "Local Offline Mode"   │
 │ (Concurrent Access)     │          │  + Flutter Kiosk UI      │
 └─────────────────────────┘          └────────────┬─────────────┘
                                                   │
                                      ┌────────────┴─────────────┐
                                      │    Hardware Layer        │
                                      │                          │
                                      │ ADS1115  ─► 3x Soil      │
                                      │ BME280   ─► Temp/Hum/Pres│
                                      │ XKC-Y26-V─► Tank Level   │
                                      │ 4ch Relay─► Pump/Valves  │
                                      └──────────────────────────┘
```

---

## ✨ Core Features

*   **Zero-Trust Security**: Remote access is strictly credential-based (Device ID + PIN) via Cloud Firestore. No local ports are exposed. Environment variables (`.env`) are used to manage secrets securely.
*   **Dual Operation Modes**: 
    *   **Secure IoT**: Monitor and control your garden globally via the iOS, Android, and Windows Desktop apps.
    *   **Air-Gapped Local**: Full operation and calibration via the Raspberry Pi's physical touchscreen, independent of internet connectivity.
*   **Centralized Power Distribution**: Utilizes a single 12V source with a 5V/5A Buck Module, providing clean 5.1V logic power via USB-C and isolated 5V motor power for pump noise suppression.
*   **Advanced Irrigation Control**:
    *   **Pulse & Soak**: Intelligent auto-watering that pulses water for 5s followed by a 20s soak period to ensure optimal absorption and prevent runoff.
    *   **Manual Modes**: Dedicated controls for "Continuous Flow" (fixed duration) and "Pulse & Soak" manual triggers.
*   **Safety & Lockdown**:
    *   **Master Lockdown Switch**: A global safety switch that instantly kills all active watering and prevents new cycles until manually released.
    *   **Normally Closed (NC) Safety**: All valves are NC, ensuring they fail-safe to a closed position during power or software failures.
    *   **Pump Watchdog**: A dedicated GPIO-level Python daemon forces the water pump OFF if it runs longer than 120 seconds, preventing floods.
*   **Hardware-Aware Maintenance Mode**: Gracefully handles I2C disconnects (Errno 5) and BME280 sensor faults. The UI displays a "Maintenance Required" wrench icon and hard-locks auto-watering for affected zones.
*   **Integrated Environment Module**: Groups Temperature, Humidity, and Pressure into a unified real-time dashboard card.
*   **Physical Factory Reset**: A dedicated hardware button (BCM 24) with LED feedback (BCM 18) for secure persistence resets.

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
pip install -r requirements.txt adafruit-circuitpython-bme280 --break-system-packages

# 3. Configure Security & Credentials
# Place your `firebase_credentials.json` in the `smartsproutrasberry/` directory.
cp .env.example .env 
# Update .env with your specific:
# DEVICE_ID="SPROUT_XXXX"
# DEVICE_PIN="1234"
# FIREBASE_CREDENTIALS_PATH="firebase_credentials.json"

# 4. Install the Reliability Watchdog (Systemd)
sudo cp smartsprout.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable smartsprout
sudo systemctl start smartsprout
```

### 2. Mobile App Setup (Flutter)

```bash
cd Smartsprout/smartsprout

# 1. Install dependencies
flutter pub get

# 2. Run on your target device (iOS/Android)
flutter run
```

---

## 📁 Repository Structure

```text
Smartsprout/
├── README.md                   # This overview
├── HARDWARE_SETUP.md           # Detailed physical wiring & sensor specs
├── RASPBERRY_PI_GUIDE.md       # OS, Kiosk, and VNC setup guide
├── Smart Sprout Flutter.md     # Comprehensive architectural thesis
│
├── smartsprout/                # Flutter UI (Mobile & Kiosk)
│   ├── lib/
│   │   ├── data/               # Firestore services, Models, Config parsing
│   │   ├── presentation/       # Riverpod providers, UI flow
│   │   └── screens/            # Dashboard, Calibration, Setup
│   └── pubspec.yaml
│
└── smartsproutrasberry/        # Python Hardware Controller
    ├── main.py                 # Telemetry loop & differential sync
    ├── firebase_manager.py     # Firestore interaction & heartbeats
    ├── pump_watchdog.py        # Hardware safety shutoff daemon
    ├── reset_button.py         # Factory reset logic & LED feedback
    └── sensors.py              # Hardware abstraction (I2C, GPIO)
```

---

## 📄 License & Academic Context

This project is part of a senior engineering capstone research initiative at the Universal College of Parañaque, focusing on scalable, secure, zero-trust IoT systems for urban agriculture.
