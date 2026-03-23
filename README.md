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
                                      │ DHT22    ─► Temp/Hum     │
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
*   **Advanced Irrigation Control**:
    *   **Pulse & Soak**: Intelligent auto-watering that pulses water for 5s followed by a 20s soak period to ensure optimal absorption and prevent runoff.
    *   **Manual Modes**: Dedicated controls for "Continuous Flow" (fixed duration) and "Pulse & Soak" manual triggers.
*   **Safety & Lockdown**:
    *   **Master Lockdown Switch**: A global safety switch that instantly kills all active watering and prevents new cycles until manually released.
    *   **Pump Watchdog**: A dedicated GPIO-level Python daemon forces the water pump OFF if it runs longer than 120 seconds, preventing floods.
*   **Non-Intrusive Notifications**: Real-time system alerts (e.g., Low Water, Connection Stale) are delivered via a space-efficient notification row on the dashboard, replacing obstructive banners.
*   **Differential Data Sync**: Eco-Mode 2.0 pushes telemetry instantly only during critical environmental changes (e.g., Temp Δ > 1.5°C), saving bandwidth while maintaining real-time responsiveness.
*   **Physical Factory Reset**: A dedicated hardware button (GPIO 24) with LED feedback (GPIO 18) allows secure, physical persistence resets.

---

## 🔌 Hardware Pin Mapping

| Component | GPIO (BCM) | Physical Pin | Direction | Notes |
|:---|:---|:---|:---|:---|
| **I2C SDA (ADS1115 & BME280)** | GPIO 2 | Pin 3 | I2C | Soil + Temp/Hum |
| **I2C SCL (ADS1115 & BME280)** | GPIO 3 | Pin 5 | I2C | Soil + Temp/Hum |
| **Water Level (XKC-Y26-V)** | GPIO 5 | Pin 29 | IN | Digital High/Low |
| **Relay IN1 (Pump)** | GPIO 17 | Pin 11 | OUT | 12V DC Pump |
| **Relay IN2 (Valve 1)** | GPIO 27 | Pin 13 | OUT | Solenoid — Zone 1 |
| **Relay IN3 (Valve 2)** | GPIO 22 | Pin 15 | OUT | Solenoid — Zone 2 |
| **Relay IN4 (Valve 3)** | GPIO 23 | Pin 16 | OUT | Solenoid — Zone 3 |
| **Factory Reset Button** | GPIO 24 | Pin 18 | IN | Pull-Up, Active-Low (5s hold) |
| **Factory Reset LED** | GPIO 18 | Pin 12 | OUT | Blink/Solid/Off feedback |

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
