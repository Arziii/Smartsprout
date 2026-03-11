# 🌱 Smart Sprout — IoT Garden Automation System

A **Local-First, Cloud-Synced** smart garden system built with a Raspberry Pi controller and a Flutter mobile application.

---

## Architecture Overview

```
┌─────────────────┐        MQTT (Local)        ┌──────────────────────┐
│   Flutter App    │ ◄──────────────────────► │  Raspberry Pi 4      │
│  (Mobile/Touch)  │    smartsprout/telemetry   │  (Controller)        │
│                  │    smartsprout/command     │                      │
│  • Dashboard     │                            │  • main.py           │
│  • Control       │                            │  • sensors.py        │
│  • Analytics     │                            │  • config.py         │
└─────────────────┘                            └──────────┬───────────┘
                                                          │
                                              ┌───────────┴───────────┐
                                              │   Hardware Layer      │
                                              │                       │
                                              │  ADS1115 ─► 3x Soil  │
                                              │  DHT22  ─► Temp/Hum  │
                                              │  HC-SR04 ─► Tank     │
                                              │  YF-S201 ─► Flow     │
                                              │  4ch Relay ─► Pump   │
                                              │              + Valves │
                                              └───────────────────────┘
```

---

## GPIO Pin Mapping

| Component | GPIO (BCM) | Physical Pin | Direction | Notes |
|---|---|---|---|---|
| **ADS1115 SDA** | GPIO 2 | Pin 3 | I2C | Soil sensors via ADC |
| **ADS1115 SCL** | GPIO 3 | Pin 5 | I2C | Soil sensors via ADC |
| **DHT22 Data** | GPIO 4 | Pin 7 | IN | + 10kΩ pull-up to 3.3V |
| **HC-SR04 Trigger** | GPIO 5 | Pin 29 | OUT | Ultrasonic tank sensor |
| **HC-SR04 Echo** | GPIO 6 | Pin 31 | IN | **Through voltage divider** (1kΩ + 2kΩ) |
| **YF-S201 Pulse** | GPIO 13 | Pin 33 | IN (IRQ) | **Through voltage divider** (1kΩ + 2kΩ) |
| **Relay IN1 (Pump)** | GPIO 17 | Pin 11 | OUT | 12V DC Diaphragm Pump |
| **Relay IN2 (Valve 1)** | GPIO 27 | Pin 13 | OUT | Solenoid — Bed 1 |
| **Relay IN3 (Valve 2)** | GPIO 22 | Pin 15 | OUT | Solenoid — Bed 2 |
| **Relay IN4 (Valve 3)** | GPIO 23 | Pin 16 | OUT | Solenoid — Bed 3 |
| **5V Power** | — | Pin 2 | PWR | From LM2596 Buck Converter |
| **Ground** | — | Pin 6 | GND | Common ground |

> ⚠️ **CRITICAL**: The HC-SR04 Echo and YF-S201 Pulse pins output 5V. You **MUST** use voltage dividers (1kΩ + 2kΩ) to step down to 3.3V before connecting to the Pi's GPIO.

---

## MQTT Topics

| Topic | Direction | Payload | QoS |
|---|---|---|---|
| `smartsprout/telemetry` | Pi → App | Full sensor JSON every 3s | 0 |
| `smartsprout/command` | App → Pi | `{"command": "force_water", "zone": 1}` | 1 |
| `smartsprout/status` | Pi → App | `{"status": "online"}` (retained) | 1 |
| `smartsprout/alert` | Pi → App | `{"type": "tank_empty", ...}` | 1 |

### Telemetry Payload Example
```json
{
  "timestamp": 1709712345,
  "soil_moisture": [45.2, 60.1, 25.8],
  "temperature": 31.5,
  "humidity": 68.0,
  "tank_level": 75.0,
  "flow_rate": 1.2,
  "pump_locked": false,
  "system_status": "ok",
  "alerts": []
}
```

---

## Quick Start

### 1. Raspberry Pi Setup

```bash
# Install Mosquitto MQTT Broker
sudo apt update
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable mosquitto

# Clone and setup the Python backend
cd smartsproutrasberry
cp ../.env.example .env   # Edit with your actual values
pip install -r requirements.txt

# Run the controller
python main.py
```

### 2. Flutter App Setup

```bash
cd smartsprout

# Install dependencies
flutter pub get

# Update the Pi's IP address in:
# lib/presentation/providers/sensor_provider.dart
# Change: MqttService(host: '192.168.1.100')

# Run the app
flutter run
```

---

## Safety Logic

The system follows a **strict safety-first** approach:

| Sensor | Condition | Action |
|---|---|---|
| **Ultrasonic (Tank)** | Level < 10% | **LOCK pump** — prevent dry running |
| **Soil Moisture** | Below plant preset | Open zone valve + start pump |
| **Flow Sensor** | 0 L/min while pump is ON | **Alert**: possible clog/leak |
| **Battery/Solar** | Voltage < 11.5V | Enter power-save mode |

---

## Project Structure

```
Smartsprout/
├── .env.example              # GPIO + Network config template
├── README.md                 # This file
├── smartsprout/              # Flutter Mobile App
│   ├── lib/
│   │   ├── core/             # Theme, constants, BLE UUIDs
│   │   ├── data/
│   │   │   ├── models/       # SensorData model
│   │   │   ├── services/     # MqttService (live connection)
│   │   │   └── plant_data.dart
│   │   ├── presentation/
│   │   │   ├── providers/    # Riverpod state (sensorDataProvider)
│   │   │   └── screens/      # Pairing, Control, Analytics, Settings
│   │   ├── routes/           # GoRouter + Frosted NavBar
│   │   ├── screens/          # Dashboard, Plant Selector
│   │   └── widgets/          # ZoneCard, VitalCard
│   └── pubspec.yaml
└── smartsproutrasberry/      # Raspberry Pi Python Backend
    ├── main.py               # Main event loop + MQTT
    ├── sensors.py            # Hardware abstraction layer
    ├── config.py             # Pin mapping from .env
    └── requirements.txt
```

---

## License

This project is part of an academic / personal IoT initiative.
