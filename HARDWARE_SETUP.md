# Smart Sprout Hardware & System Setup

This document serves as the permanent reference for configuring the Raspberry Pi 3 Model B and wiring the specific sensor array for the Smart Sprout system.

---

## 📑 Table of Contents
1. [Physical Sensor Specifications](#1-physical-sensor-specifications)
2. [One-Line Install Script](#2-one-line-install-script)
3. [System Configuration Checklist](#3-system-configuration-checklist)
4. [Pinout Reference Table](#4-pinout-reference-table)
5. [Maintenance Note](#5-maintenance-note)

---

## 1. Physical Sensor Specifications

*   **Soil Moisture:** Capacitive v1.2 (Analog 1.2V-2.5V).
    *   *Note:* The Raspberry Pi doesn't have built-in analog pins. These sensors require the **ADS1115 I2C ADC** to convert analog signals to digital values.
*   **Temp/Humidity:** DHT22.
    *   *Note:* Communicates over a single digital GPIO pin (Default: GPIO 4).
*   **Water Level:** XKC-Y26-V.
    *   *Note:* A non-contact digital liquid level sensor that outputs a simple High/Low digital signal.

---

## 2. One-Line Install Script

Run this single command from your Raspberry Pi terminal to install all necessary system dependencies, Python libraries, and hardware drivers:

```bash
sudo apt-get update && sudo apt-get install -y i2c-tools python3-pip python3-dev libgpiod-dev && pip3 install adafruit-circuitpython-bme280 adafruit-circuitpython-ads1x15 gpiozero python-dotenv firebase-admin
```

---

## 3. System Configuration Checklist

Before running the backend, ensure the Pi's hardware interfaces and memory are configured correctly.

*   [ ] **Step 1:** Run `sudo raspi-config` -> Interfacing Options -> **Enable I2C**.
*   [ ] **Step 2:** Run `ls /dev/i2c*` or `i2cdetect -y 1` in the terminal to verify the I2C bus is active and sees your connected BME280/ADS1115 sensors.
*   [ ] **Step 3:** Verify the **2GB permanent swap file** is active by running `free -h` (check that 'Swap' shows ~2.0G total).

---

## 4. Pinout Reference Table

Wire the sensors to the Raspberry Pi GPIO pins exactly as described below.

| Hardware Component | Device Pin / Wire Color | Raspberry Pi Pin (BCM / Physical) |
| :--- | :--- | :--- |
| **I2C Bus (ADS1115 & BME280)** | `SDA` | **BCM 2** (Pin 3) |
| | `SCL` | **BCM 3** (Pin 5) |
| | `VCC` | **3.3V** (Pin 1 or 17) |
| | `GND` | **GND** (Pin 6 or 9) |
| **Water Level (XKC-Y26-V)** | `Brown` (VCC) | **5V** (Pin 2 or 4) |
| | `Blue` (GND) | **GND** (Pin 6 or 9) |
| | `Yellow` (OUT signal) | **BCM 5** (Pin 29) *(Previous Trigger Pin)* |
| Relay Module (Active-Low)| GPIO 17 (Pump IN1) | **BCM 17** (Pin 11) |
|                          | GPIO 27 (Valve1 IN2) | **BCM 27** (Pin 13) |
|                          | GPIO 22 (Valve2 IN3) | **BCM 22** (Pin 15) |
|                          | GPIO 23 (Valve3 IN4) | **BCM 23** (Pin 16) |
| Factory Reset Button     | GPIO 24 (Pull-Up, GND press)| **BCM 24** (Pin 18) |
|                          | Hold 5s to factory reset    | |
| Reset Feedback LED       | GPIO 18 (Output)            | **BCM 18** (Pin 12) |
|                          | Blinks during hold, solid   | |
|                          | on trigger, off on cancel   | |

*(Note: The `Black` wire on the XKC-Y26-V is the mode selection pin and is typically left disconnected or tied to Ground for normal operation.)*

---

## 5. Maintenance Note

> **Note:** Running the install commands multiple times is perfectly safe. The package managers (`apt` and `pip`) will automatically detect if the dependencies are already present and will not duplicate files or break your environment.
