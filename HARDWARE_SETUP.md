# Smart Sprout Hardware & System Setup

This document serves as the permanent reference for configuring the **Raspberry Pi 4** and wiring the specific sensor array for the Smart Sprout system.

---

## 📑 Table of Contents
1. [Centralized Power Distribution](#1-centralized-power-distribution)
2. [Physical Sensor Specifications](#2-physical-sensor-specifications)
3. [One-Line Install Script](#3-one-line-install-script)
4. [System Configuration Checklist](#4-system-configuration-checklist)
5. [Pinout Reference Table (BCM Mapping)](#5-pinout-reference-table-bcm-mapping)
6. [Solenoid & Pump Control Logic](#6-solenoid--pump-control-logic)
7. [Critical Voltage Protection (Input/Output)](#7-critical-voltage-protection)
8. [Maintenance Note & Troubleshooting](#8-maintenance-note--troubleshooting)

---

## 1. Centralized Power Distribution

To prevent I2C `[Errno 5]` errors and system instability, the project utilizes a **High-Current Single-Source Power Strategy** with an **XL4016 DC-DC Buck Module (8A)**.

*   **Master Input:** 12V 8A DC Power Adapter (Powers the 12V Solenoid Rail and the Buck Module) using **18AWG copper wiring** for rail stability.
*   **Logic Power:** The XL4016 steps 12V down to **5.1V**. This is delivered via a **Homesaya USB Female Jack** (2-wire) to the Raspberry Pi 4 to meet its 3.0A peak demand.
*   **Peripheral Power:** The Buck Module’s secondary output terminals provide dedicated 5V power to the **USB Pump** and **Relay VCC**, isolating motor noise from the Pi’s internal power rail.

---

## 2. Physical Sensor Specifications

*   **Soil Moisture:** Capacitive v1.2 (Analog 1.2V-2.5V).
    *   *Note:* The Raspberry Pi doesn't have built-in analog pins. These sensors require the **ADS1115 I2C ADC** to convert analog signals to digital values.
*   **Temp/Humidity/Pressure:** BME280 (I2C).
    *   *Note:* A precision sensor that communicates over the I2C bus (Address: 0x76).
*   **Water Level:** XKC-Y26-V Non-contact Liquid Level Sensor.
    *   *Note:* Powered by 5V for maximum sensitivity. Outputs a digital signal passed through a voltage divider for Pi safety.
*   **Irrigation Control:** 12V Solenoid Valve - Normally Closed (NC).
    *   *Note:* The system is designed for valves that stay CLOSED when unpowered. They are opened via the relay module using 12V DC.

---

## 3. One-Line Install Script

Run this single command from your Raspberry Pi terminal to install all necessary system dependencies, Python libraries, and hardware drivers:

```bash
sudo apt-get update && sudo apt-get install -y i2c-tools python3-pip python3-dev libgpiod-dev && pip3 install adafruit-circuitpython-bme280 adafruit-circuitpython-ads1x15 gpiozero python-dotenv firebase-admin smbus2 --break-system-packages
```

---

## 4. System Configuration Checklist

Before running the backend, ensure the Pi's hardware interfaces and memory are configured correctly.

*   [ ] **Step 1:** Run `sudo raspi-config` -> Interfacing Options -> **Enable I2C**.
*   [ ] **Step 2:** Run `ls /dev/i2c*` or `i2cdetect -y 1` in the terminal to verify the I2C bus is active and sees your connected BME280 and ADS1115 sensors.
*   [ ] **Step 3:** Verify the **2GB permanent swap file** is active by running `free -h` (check that 'Swap' shows ~2.0G total).

---

## 5. Pinout Reference Table (BCM Mapping)

All software implementation must reference the **BCM (Broadcom)** numbering used in the `SensorManager.py` backend.

| Hardware Component | Device Pin / Color | Raspberry Pi Pin (BCM / Physical) | Power Source & Wiring Logic |
| :--- | :--- | :--- | :--- |
| **Main Power** | Homesaya USB Jack | **Pi 4 USB-C Port** | From 8A XL4016 Buck Output |
| **I2C Bus (Sensors)** | SDA | **BCM 2** (Pin 3) | 3.3V from Pi (Pin 1) |
| | SCL | **BCM 3** (Pin 5) | Shared GND with Pi |
| **Soil Moisture (Z1)** | Sensor 1 Signal | **ADS1115 A0** | Capacitive v1.2 (Analog) |
| **Soil Moisture (Z2)** | Sensor 2 Signal | **ADS1115 A1** | Capacitive v1.2 (Analog) |
| **Soil Moisture (Z3)** | Sensor 3 Signal | **ADS1115 A2** | Capacitive v1.2 (Analog) |
| **Water Level (XKC)** | Yellow (Signal) | **BCM 5** (Pin 29) | Requires 1kΩ/2kΩ Voltage Divider |
| **Relay Module (5V)** | VCC | **5V** (Pin 2 or 4) | Powered by Pi 5V Rail |
| | IN1 (Pump) | **BCM 17** (Pin 11) | COM: Buck OUT+ / NO: Pump Red |
| | IN2 (Valve 1) | **BCM 27** (Pin 13) | COM: 12V+ (IN+) / NO: Valve 1+ |
| | IN3 (Valve 2) | **BCM 22** (Pin 15) | COM: 12V+ (IN+) / NO: Valve 2+ |
| | IN4 (Valve 3) | **BCM 23** (Pin 16) | COM: 12V+ (IN+) / NO: Valve 3+ |
| **User Interface** | Reset Button | **BCM 24** (Pin 18) | One side to Pin, one to GND |
| | Feedback LED | **BCM 18** (Pin 12) | Heartbeat Pulse / Rapid Blink |

---

## 6. Solenoid & Pump Control Logic

The system utilizes a **4-Channel 5V Relay Module (SRD-05VDC)** acting as a galvanic isolation barrier between the 3.3V Pi logic and the high-current loads.

*   **Normally Closed (NC) Safety:** All irrigation valves are NC. In the event of a power failure or software crash, the valves default to a closed state to prevent flooding.
*   **USB Pump Splicing:** The pump's USB cable is spliced at the VCC (Red) wire. The Buck Module's 5V (+) is connected to the Relay COM, and the pump's Red wire is connected to Relay NO (Normally Open).
*   **Common Ground:** All Ground (GND) wires from the 12V supply, 5V Buck Module, and Raspberry Pi GPIO are tied to a single **common ground plane** to ensure signal integrity.

---

## 7. Critical Voltage Protection (Input/Output)

Since the Raspberry Pi 4 GPIO is not 5V tolerant, the following safeguards are implemented:

*   **7.1 Level Shifting:** The XKC-Y26-V liquid sensor is powered by 5V for maximum sensitivity, but its output signal is passed through a **Voltage Divider (1kΩ/2kΩ)** to ensure the Pi only receives a safe 3.3V signal.
*   **7.2 Back-EMF Protection:** The 12V solenoid valves generate flyback voltage when deactivated. The use of a relay module with **opto-isolation** prevents these spikes from reaching the Pi's processor.
*   **7.3 Fail-Safe Irrigation:** Normally Closed (NC) solenoid valves are wired to Normally Open (NO) relay terminals. The valves receive 12V directly from the master adapter (bypassing the buck converter), ensuring they slam shut if the system loses logic power.
*   **7.4 Thermal Management & Enclosure Design:** 
    *   **Active Cooling:** A dedicated exhaust fan is integrated into the enclosure to manage heat from the XL4016 heatsinks and the Pi 4.
    *   **Airflow:** Positioned to pull hot air out, preventing "thermal throttling" and sensor instability.
    *   **Wiring:** 12V fans connect to XL4016 **IN+ / IN-** (full speed); 5V fans connect to **OUT+ / OUT-**.

---
## 8. Maintenance Note & Troubleshooting

The Smart Sprout system features a **Hardware-Aware Maintenance Mode**. If the app displays an orange **Wrench Icon** with a **"FAULT"** label, it means the Raspberry Pi has detected a hardware disconnect.

### Common Fault Triggers:
1.  **I2C Bus Error ([Errno 5]):** Usually indicates a loose SDA or SCL wire on the ADS1115 (Soil) or BME280 (Environment).
2.  **Missing Driver:** If the BME280 is connected but fails to initialize, ensure you have installed the driver specifically using the `adafruit-circuitpython-bme280` package with the `--break-system-packages` flag.
3.  **Address Conflict:** The system expects the **BME280 at 0x76** and the **ADS1115 at 0x48**. Use `i2cdetect -y 1` to verify these addresses are visible on the bus.

### Safety Hard-lock:
When a sensor is in "FAULT" state, the backend **automatically disables (Hard-locks)** all irrigation logic for that specific zone. This prevents the pump from running indefinitely due to a faulty "dry" sensor reading.

---

## 9. Versioning Note

> **Note:** Running the install commands multiple times is perfectly safe. The package managers (`apt` and `pip`) will automatically detect if the dependencies are already present and will not duplicate files or break your environment.
