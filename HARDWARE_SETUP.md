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
*   **Temp/Humidity/Pressure:** BME280 (I2C).
    *   *Note:* A precision sensor that communicates over the I2C bus (Address: 0x76 or 0x77).
*   **Water Level:** XKC-Y26-V Non-contact Liquid Level Sensor.
    *   *Note:* A non-contact digital liquid level sensor that outputs a simple High/Low digital signal. It is typically mounted to the outside of the tank.

---

## 2. One-Line Install Script

Run this single command from your Raspberry Pi terminal to install all necessary system dependencies, Python libraries, and hardware drivers:

```bash
sudo apt-get update && sudo apt-get install -y i2c-tools python3-pip python3-dev libgpiod-dev && pip3 install adafruit-circuitpython-bme280 adafruit-circuitpython-ads1x15 gpiozero python-dotenv firebase-admin smbus2
```

---

## 3. System Configuration Checklist

Before running the backend, ensure the Pi's hardware interfaces and memory are configured correctly.

*   [ ] **Step 1:** Run `sudo raspi-config` -> Interfacing Options -> **Enable I2C**.
*   [ ] **Step 2:** Run `ls /dev/i2c*` or `i2cdetect -y 1` in the terminal to verify the I2C bus is active and sees your connected BME280 and ADS1115 sensors.
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
| **Analog Inputs (ADS1115)** | `A0` | **Soil Sensor Zone 1** (Analog Out) |
| | `A1` | **Soil Sensor Zone 2** (Analog Out) |
| | `A2` | **Soil Sensor Zone 3** (Analog Out) |
| **Water Level (XKC-Y26-V)** | `Brown` (VCC) | **5V** (Pin 2/4) or **3.3V** (Pin 1/17) (See Note below!) |
| | `Blue` (GND) | **GND** (Pin 6 or 9) |
| | `Yellow` (OUT signal) | **BCM 5** (Pin 29) (Needs Voltage Divider if powered by 5V!) |
| | `Black` (Mode Select) | **GND** (Pin 6 or 9) to configure as Active-High logic |
| Relay Module (Active-Low)| GPIO 17 (Pump IN1) | **BCM 17** (Pin 11) |
|                          | GPIO 27 (Valve1 IN2) | **BCM 27** (Pin 13) |
|                          | GPIO 22 (Valve2 IN3) | **BCM 22** (Pin 15) |
|                          | GPIO 23 (Valve3 IN4) | **BCM 23** (Pin 16) |
| Factory Reset Button     | GPIO 24 (Pull-Up, GND press)| **BCM 24** (Pin 18) |
|                          | Hold 5s to factory reset    | |
| Reset Feedback LED       | GPIO 18 (Output)            | **BCM 18** (Pin 12) |
|                          | Blinks during hold, solid   | |
|                          | on trigger, off on cancel   | |

*(Note: The "V" variant of the sensor outputs a High signal equal to its input voltage. **If you power the Brown wire with 5V, the Yellow wire will output 5V, which WILL fry your Raspberry Pi's 3.3V GPIO!** Do not connect it directly if powered to 5V; use a voltage divider (e.g., 2kΩ and 1kΩ resistors) to step it down to 3.3V. Alternatively, try powering the Brown wire directly from the Pi's **3.3V** pin—many users report the sensor works perfectly at 3.3V, making the Yellow signal 100% safe for the Pi.)*

---

## 5. Voltage & Power Safety Reference

To maintain system stability and avoid damaging the Raspberry Pi hardware, follow these electrical safety guidelines:

### Input Power Specifications
*   **Raspberry Pi 3B:** Requires **5.1V DC** via the Micro-USB port. Recommended current is **2.5A** minimum to avoid "Under-voltage detected" warnings during relay switching.
*   **Water Pump & Solenoids:** Requires a separate **12V DC power supply**. Do **NOT** attempt to power these directly from the Raspberry Pi pins.
*   **Relay Module:** Powered by the Pi's **5V pin** (Pin 2 or 4). The signal pins are controlled via 3.3V logic.

### IO Logic Levels (CRITICAL)
*   **Input Pins:** All GPIO pins on the Raspberry Pi are **3.3V ONLY**. Connecting 5V signals directly to these pins will cause permanent hardware damage.
*   **I2C Bus:** The SDA/SCL lines are internally pulled up on the Pi to 3.3V. Ensure your sensors (ADS1115/BME280) are powered by the **3.3V pin** (Pin 1 or 17).
*   **Soil Moisture Sensors:** Typically powered by **3.3V**. The capacitive v1.2 output signal (1.2V - 2.5V) is safe for the ADS1115.

---

## 6. Maintenance Note

> **Note:** Running the install commands multiple times is perfectly safe. The package managers (`apt` and `pip`) will automatically detect if the dependencies are already present and will not duplicate files or break your environment.
