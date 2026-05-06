This document serves as the permanent reference for configuring the **Raspberry Pi 4** and wiring the specific sensor array and protective power architecture for the Smart Sprout system.

---

## 📑 Table of Contents
1. [Centralized Power Distribution](#1-centralized-power-distribution)
2. [Physical Sensor Specifications](#2-physical-sensor-specifications)
3. [One-Line Install Script](#3-one-line-install-script)
4. [System Configuration Checklist](#4-system-configuration-checklist)
5. [Pinout Reference Table (BCM Mapping)](#5-pinout-reference-table-bcm-mapping)
6. [3-Pump Independent Control Logic](#6-3-pump-independent-control-logic)
7. [Hardware Fault Mitigation & Protective Wiring](#7-hardware-fault-mitigation--protective-wiring)
8. [Password Reset Methods](#8-password-reset-methods)
9. [Maintenance Note & Troubleshooting](#9-maintenance-note--troubleshooting)
10. [Scaling & Security (Unit 10+)](#10-scaling--security-unit-10)

---

## 1. Centralized Power Distribution

To prevent I2C `[Errno 5]` errors and system instability, the project utilizes a **High-Current Single-Source Power Strategy** with an **XL4016 DC-DC Buck Module (8A)**.

*   **Master Input:** 12V 8A DC Power Adapter (Powers the Buck Module and any future 12V peripherals) using **18AWG copper wiring** for rail stability.
*   **PC-Style Power Management:** A physical power-gating mechanism (latching switch) is wired between the 12V source and the XL4016. This mimics a PC power supply, ensuring the system remains off after plugging it in until a manual power-on intervention occurs.
*   **Logic Power:** The XL4016 steps 12V down to **5.1V**. This is delivered via a **Homesaya USB Female Jack** (2-wire) to the Raspberry Pi 4 to meet its 3.0A peak demand.
*   **Peripheral Power:** The Buck Module's secondary output terminals provide dedicated 5V power to the **5V Submersible Pumps** and **Relay VCC**, isolating motor current from the Pi's internal power rail.

---

## 2. Physical Sensor Specifications

*   **Soil Moisture:** Capacitive v1.2 (Analog 1.2V-2.5V). Requires the **ADS1115 I2C ADC** to convert analog signals to digital values for the Pi.
*   **Temp/Humidity:** DHT22 Module (Digital, GPIO). A 3-pin breakout board with a built-in 10kΩ pull-up resistor. Communicates via a single-wire protocol on GPIO BCM 4. Replaces the legacy BMP280/BME280 I2C sensor — pressure telemetry has been removed from the system.
*   **Water Level:** XKC-Y26-V Non-contact Liquid Level Sensor. Powered by 5V. Outputs a digital signal passed through a 10kΩ/20kΩ voltage divider. **System uses Fail-Safe Active-High logic (Black Mode wire to GND).** The voltage divider acts as a physical pull-down to Ground, and software `PUD_DOWN` (~50kΩ) provides a secondary safety net. When the sensor is disconnected, the pin is pulled to LOW ("Empty"), protecting the pumps from running dry.
*   **Irrigation Control:** 3x Independent 5V Submersible Pumps — one per zone. Each pump is controlled by its own dedicated relay channel. The legacy 1-pump/3-valve (solenoid) architecture has been replaced with this independent pump configuration for simplified wiring and fault isolation.

### DHT22 Module Wiring (3-Pin)

The DHT22 **module** (3-pin breakout board, not the bare 4-pin chip) has a built-in 10kΩ pull-up resistor. No external resistor or software pull-up is needed.

| Module Pin | Label | Connect To | Pi Physical Pin | Notes |
|:----------:|-------|------------|:---------------:|-------|
| **1** | `VCC` / `+` | **5V** | Pin 2 or Pin 4 | Power supply (5V tolerant) |
| **2** | `DATA` / `OUT` / `S` | **GPIO BCM 4** | **Pin 7** | Signal — pull-up is on the module PCB |
| **3** | `GND` / `–` | **GND** | Pin 6, 9, 14, etc. | Ground |

```
   DHT22 Module          Raspberry Pi
   ┌──────────┐
   │  VCC (+) │ ────────► 5V   (Pin 2)
   │ DATA (S) │ ────────► BCM4 (Pin 7)
   │  GND (–) │ ────────► GND  (Pin 6)
   └──────────┘
```

> [!TIP]
> The module version is the small blue or white PCB with 3 pins already soldered. If your board has **4 pins** and no PCB, that's the bare chip — you'd need an external 10kΩ pull-up resistor between VCC and DATA.

---

## 3. One-Line Install Script

Run this single command from your Raspberry Pi terminal to install all necessary system dependencies, Python libraries, and hardware drivers:

```bash
sudo apt-get update && sudo apt-get install -y i2c-tools python3-pip python3-dev libgpiod-dev libgpiod2 && pip3 install adafruit-circuitpython-dht adafruit-blinka adafruit-circuitpython-ads1x15 gpiozero python-dotenv firebase-admin smbus2 --break-system-packages
```

> [!NOTE]
> The `libgpiod2` package is required by the `adafruit-circuitpython-dht` library for GPIO character device access on modern Raspberry Pi OS kernels.

---

## 4. System Configuration Checklist

Before running the backend, ensure the Pi's hardware interfaces and memory are configured correctly.

*   [ ] **Step 1:** Run `sudo raspi-config` -> Interfacing Options -> **Enable I2C**.
*   [ ] **Step 2:** Run `ls /dev/i2c*` or `i2cdetect -y 1` in the terminal to verify the I2C bus is active and sees your connected ADS1115 sensor.
*   [ ] **Step 3:** Verify the **2GB permanent swap file** is active by running `free -h` (check that 'Swap' shows ~2.0G total).
*   [ ] **Step 4:** Using a multimeter, manually tune the XL4016 brass screw until the output is exactly 5.1V before plugging in the Raspberry Pi.
*   [ ] **Step 5:** Wire DHT22 module: VCC→5V (Pin 2), DATA→BCM 4 (Pin 7), GND→GND (Pin 6).
*   [ ] **Step 6:** Wire 3 pumps to relay channels on BCM 17 (Pin 11), BCM 27 (Pin 13), BCM 22 (Pin 15).

---

## 5. Pinout Reference Table (BCM Mapping)

All software implementation must reference the **BCM (Broadcom)** numbering used in the `SensorManager.py` backend.

| Hardware Component | Device Pin / Color | Raspberry Pi Pin (BCM / Physical) | Power Source & Wiring Logic |
| :--- | :--- | :--- | :--- |
| **Main Power** | Homesaya USB Jack | **Pi 4 USB-C Port** | From 8A XL4016 Buck Output |
| **I2C Bus (ADS1115)** | SDA | **BCM 2** (Pin 3) | 3.3V from Pi (Pin 1) |
| | SCL | **BCM 3** (Pin 5) | Shared GND with Pi |
| **ADS1115 ADC** | VDD / GND | **3.3V / GND** | Powers the ADC |
| | ADDR | **GND** | Sets I2C to 0x48 |
| **DHT22 Module** | VCC (+) | **5V** (Pin 2) | Powers the sensor module |
| | DATA (S) | **BCM 4** (Pin 7) | Signal — module has built-in 10kΩ pull-up |
| | GND (–) | **GND** (Pin 6) | Shared GND with Pi |
| **Soil Moisture (Z1)** | Sensor 1 Signal | **ADS1115 A0** | Capacitive v1.2 (Analog) |
| **Soil Moisture (Z2)** | Sensor 2 Signal | **ADS1115 A1** | Capacitive v1.2 (Analog) |
| **Soil Moisture (Z3)** | Sensor 3 Signal | **ADS1115 A2** | Capacitive v1.2 (Analog) |
| **Water Level (XKC)** | Yellow (Signal) | **BCM 6** (Pin 31) | Active-High (Black to GND) / Hardware Pull-Down + Software PUD_DOWN |
| **Relay Module (5V)** | VCC | **5V** (Pin 2 or 4) | Powered by Pi 5V Rail |
| | IN1 (Pump 1 — Zone 1) | **BCM 17** (Pin 11) | COM: Buck OUT+ / NO: Pump 1 Red |
| | IN2 (Pump 2 — Zone 2) | **BCM 27** (Pin 13) | COM: Buck OUT+ / NO: Pump 2 Red |
| | IN3 (Pump 3 — Zone 3) | **BCM 22** (Pin 15) | COM: Buck OUT+ / NO: Pump 3 Red |
| | IN4 *(unused)* | **BCM 23** (Pin 16) | *Freed — previously Valve 3* |
| **User Interface** | Reset Button | **BCM 24** (Pin 18) | One side to Pin, one to GND |
| | Feedback LED | **BCM 18** (Pin 12) | Heartbeat Pulse / Rapid Blink |

---

## 6. 3-Pump Independent Control Logic

The system uses **3 independent 5V submersible pumps**, each on its own relay channel. This replaces the legacy architecture where a single shared pump fed 3 solenoid valves through a water distribution manifold.

### Why Independent Pumps?

*   **Fault Isolation:** A failed pump only affects its zone — the other two continue operating.
*   **Simplified Wiring:** No solenoid valves, no 12V rail, no manifold.
*   **Independent Timing:** Each pump can run for different durations without sharing flow.

### Relay Wiring

All 3 relay channels use the **5V Buck Converter output** (no 12V rail needed anymore).

| Relay | GPIO BCM | Pump | Wiring |
|:-----:|:--------:|:----:|--------|
| CH1 | BCM 17 (Pin 11) | Pump 1 (Zone 1) | COM: Buck 5V+ / NO: Pump 1 Red |
| CH2 | BCM 27 (Pin 13) | Pump 2 (Zone 2) | COM: Buck 5V+ / NO: Pump 2 Red |
| CH3 | BCM 22 (Pin 15) | Pump 3 (Zone 3) | COM: Buck 5V+ / NO: Pump 3 Red |
| CH4 | BCM 23 (Pin 16) | *(unused)* | *(leave disconnected)* |

*   **The "Common Ground" Rule:** The XL4016 5V GND, the Pi GND, and all Pump GNDs must be physically connected together to share a single ground reference.

> [!IMPORTANT]
> **Active-Low Logic:**
> The relay module operates as **Active-Low**:
> * GPIO **HIGH (3.3V)** = Relay De-energized = Circuit Open = **Pump OFF**.
> * GPIO **LOW (0V)** = Relay Energized = Circuit Closed = **Pump ON**.
>
> **Independence:** Activating Zone 1's pump does NOT affect Zones 2 or 3. Each pump is fully decoupled.

---

## 7. Hardware Fault Mitigation & Protective Wiring

To ensure industrial-grade uptime and protect the Raspberry Pi from erratic power fluctuations and electrical hazards inherent to motor loads, the following electrical shields are mandatory.

### Protective Bill of Materials (BOM)

| Component | Specification | Qty | Location / Target Device |
| :--- | :--- | :--- | :--- |
| **Inline Fuse** | 7.5A Automotive Type | 1 pc | Main 12V Input DC Line |
| **Inline Fuse** | 5A Automotive Type | 1 pc | 5.1V Buck Converter Output Line |
| **Flyback Diode** | 1N4007 Rectifier Diode | 3 pcs | 1x per Pump (3 total) |
| **Bulk Capacitor** | 1000µF Electrolytic | 1 pc | 5.1V Power Rail (Buck Converter Output) |
| **Resistor** | 10kΩ | 1 pc | Water Sensor Signal Line |
| **Resistor** | 20kΩ | 1 pc | Water Sensor Signal to Ground |

### 7.1 Overcurrent Protection (Fuses)
Fusing prevents catastrophic thermal runaway and limits damage during short-circuit events within the power rail.

*   **Wiring & Sizing:** 
    *   Install a **7.5A inline fuse** on the main **12V input** positive line, before it reaches the Buck Converter. This protects the entire system against total catastrophic shorts.
    *   Install a **5A inline fuse** on the **5.1V Buck Converter output** positive line. This specifically protects the Raspberry Pi and the 5.1V logic rail in the event a pump jams and draws excessive current.

### 7.2 Back-EMF Suppression (Flyback Diodes)
When the mechanical relays turn off the motor loads, collapsing magnetic fields generate destructive, high-voltage inductive spikes that travel backward through the wiring.

*   **Wiring:** Install three **1N4007 Diodes** wired in parallel directly across the terminals (positive and negative wires) of each of the 3 submersible pumps.
*   **Crucial Polarity:** Diodes must be explicitly wired in **"Reverse Bias"** to catch these spikes. 
    *   Connect the **Cathode (Silver Stripe)** side of the diode to the **Positive (+)** wire of the pump.
    *   Connect the **Anode (Solid Black)** side of the diode to the **Ground (-)** wire. 

### 7.3 Brownout Prevention (Bulk Capacitor)
When a pump kicks on, the electric motor intrinsically demands a massive transient "inrush current." Without buffering, this sharp power draw momentarily drops the 5.1V line voltage below operational thresholds, causing the Raspberry Pi to instantly crash.

*   **Wiring:** Install a **1000µF electrolytic capacitor** spanning across the **5.1V Output** and **Ground** terminals of the Buck Converter to act as a local battery buffer.
*   **Crucial Polarity:** The capacitor is polarized. Connect its **Long Leg** to the **Positive 5.1V Output** and its **Short Leg (with the white/grey minus stripe)** to **Ground**. 
    > **Warning:** Reversing the polarity will cause the capacitor to physically burst!

### 7.4 Logic Level Shifting (Voltage Divider)
The XKC-Y26-V liquid level sensor requires 5V to scan through container walls effectively, meaning its digital logic output is also 5V. However, the Raspberry Pi's GPIO pins are strictly 3.3V tolerant; exposing them to an unmitigated 5V signal will permanently destroy the CPU.

*   **Wiring:** Construct a voltage divider using a **10kΩ** and **20kΩ** resistor on the **Yellow signal wire** coming from the XKC sensor.
    *   Place the **10kΩ resistor** in series between the yellow signal wire and the destination **Raspberry Pi GPIO pin**.
    *   Place the **20kΩ resistor** between the GPIO pin side of the 10kΩ resistor and the shared logic **Ground**. 
    *   This precisely safely steps the 5V signal down to ~3.3V before it hits the Raspberry Pi.

> [!TIP]
> **Why Active-High? (Fail-Safe Strategy)**
> Because the 20kΩ resistor anchors the GPIO pin to Ground, it inherently prevents the Raspberry Pi from detecting a "floating" disconnected wire. If the sensor is unplugged, the pin is physically tied to 0V. By wiring the sensor in **Active-High** Mode (connecting its Black wire to **GND**), 0V logically becomes "Tank Empty." This guarantees that if the sensor wire falls out or the sensor dies, the Pi stops the pumps instead of incorrectly assuming the tank is full.
>
> **Dual-Layer Biasing:** In addition to the hardware pull-down (voltage divider), the software enables `GPIO.PUD_DOWN` (~50kΩ internal pull-down). This acts as a secondary safety net for scenarios where the entire sensor circuit (including the voltage divider resistors) is physically removed. The weak 50kΩ pull-down does not affect the sensor's 3.2V output (drops to ~3.0V, still above the 1.8V HIGH threshold).

---

## 8. Password Reset Methods

The Smart Sprout system provides two independent methods to reset the device password to the factory default (`1234`):

### Method 1: Hardware Reset Button (GPIO 24)
A physical momentary push button on **GPIO BCM 24** (Pin 18). **Hold for 5 continuous seconds** to trigger a full factory reset:
1. Resets `device_config.json` to defaults (device ID: `SPROUT_A1B2`, password: `1234`)
2. Wipes `calibration_offsets.json`
3. Reboots the Raspberry Pi

**LED Feedback (GPIO 18):**
*   While held (0-5s): LED blinks rapidly (100ms on/off)
*   At 5s threshold: LED goes solid ON → reset executes → reboot
*   On early release: LED turns OFF (cancel)

> [!CAUTION]
> The hardware button performs a **full factory reset** — it wipes both the password AND calibration data. Use Method 2 if you only need to reset the password.

### Method 2: Software Reset via Kiosk Settings (Linux Only)
Available in the Flutter kiosk UI under **Settings → Hardware Controls → Reset Password**.

*   Resets the password to `1234` (re-hashed with PBKDF2-HMAC-SHA256)
*   **Does NOT wipe calibration data** or change the device ID
*   Requires confirmation dialog before executing
*   Sends `RESET_PASSWORD` command through Firebase → Pi backend

This method is only available on the Linux kiosk (not the mobile app), providing a safe software-only password recovery without disrupting sensor calibration.

---

## 9. Maintenance Note & Troubleshooting

The Smart Sprout system features a **Hardware-Aware Maintenance Mode**. If the app displays an orange **Wrench Icon** with a **"FAULT"** label, it means the Raspberry Pi has detected a hardware disconnect.

### Common Fault Triggers:
1.  **I2C Bus Error ([Errno 5]):** Usually indicates a loose SDA or SCL wire, or that the system experienced a power-drop (ensure your 1000µF capacitor is installed securely).
2.  **DHT22 Checksum Error:** The DHT22 sensor occasionally returns `None` due to timing-sensitive single-wire protocol issues. The software retries automatically and reports `-1.0` (fault sentinel) until a valid read is obtained. If readings consistently fail, check the wiring to BCM 4.
3.  **Address Conflict:** The system expects the **ADS1115 at 0x48**. Use `i2cdetect -y 1` to verify this address is visible on the bus.

### Safety Hard-lock:
When a sensor is in "FAULT" state, the backend **automatically disables (Hard-locks)** all irrigation logic for that specific zone. This prevents the pump from running indefinitely due to a faulty "dry" sensor reading.

### ADS1115 ADC Crosstalk (Ghost Readings):
The ADS1115's internal multiplexer shares a single sample-and-hold capacitor across all channels. When switching from a connected sensor to a disconnected channel, the capacitor retains charge from the previous reading, causing "ghost" values on empty inputs. The software mitigates this by performing a **dummy settling read** before each real measurement, allowing the capacitor to discharge to the actual channel voltage. If ghost readings persist, tie unused ADS1115 inputs to GND via a 10kΩ resistor.

### DHT22 Environment Display:
The dashboard displays temperature and humidity in a unified **Environment** card:
*   Normal: `28.5°C / 62%`
*   Fault: `--°C / --%` (shown when sensor returns invalid data)

---

## 10. Scaling & Security (Unit 10+)

The hardware architecture is designed for **Commercial Scale**. To deploy multiple units, follow these physical security protocols:

### 1. The One-Line Flash
When preparing a new unit, the same `main.py` code is used. The only difference is the `.env` file containing the `DEVICE_ID`. Each Pi is a "Cloned Appliance" that points to a different row in the Firebase database.

### 2. Tamper-Proofing the Hardware
*   **Encrypted SD Partition**: Use LUKS to ensure that even if the SD card is stolen, the code cannot be read on a PC.
*   **Physical Kiosk Hardening**: Disable USB ports and external peripherals (like keyboards) so that the user is stuck "inside" the Smart Sprout UI and cannot break the system.

### 3. Binary Shielding
All Python code is compiled into a **Binary Executable** before deployment. This prevents the user from seeing your logic or modifying the watering thresholds manually.

---
