This document serves as the permanent reference for configuring the **Raspberry Pi 4** and wiring the specific sensor array and protective power architecture for the Smart Sprout system.

---

## 📑 Table of Contents
1. [Centralized Power Distribution](#1-centralized-power-distribution)
2. [Physical Sensor Specifications](#2-physical-sensor-specifications)
3. [One-Line Install Script](#3-one-line-install-script)
4. [System Configuration Checklist](#4-system-configuration-checklist)
5. [Pinout Reference Table (BCM Mapping)](#5-pinout-reference-table-bcm-mapping)
6. [Solenoid & Pump Control Logic (Split-Rail Architecture)](#6-solenoid--pump-control-logic-split-rail-architecture)
7. [Hardware Fault Mitigation & Protective Wiring](#7-hardware-fault-mitigation--protective-wiring)
8. [Maintenance Note & Troubleshooting](#8-maintenance-note--troubleshooting)
9. [Scaling & Security (Unit 10+)](#9-scaling--security-unit-10)

---

## 1. Centralized Power Distribution

To prevent I2C `[Errno 5]` errors and system instability, the project utilizes a **High-Current Single-Source Power Strategy** with an **XL4016 DC-DC Buck Module (8A)**.

*   **Master Input:** 12V 8A DC Power Adapter (Powers the 12V Solenoid Rail and the Buck Module) using **18AWG copper wiring** for rail stability.
*   **PC-Style Power Management:** A physical power-gating mechanism (latching switch) is wired between the 12V source and the XL4016. This mimics a PC power supply, ensuring the system remains off after plugging it in until a manual power-on intervention occurs.
*   **Logic Power:** The XL4016 steps 12V down to **5.1V**. This is delivered via a **Homesaya USB Female Jack** (2-wire) to the Raspberry Pi 4 to meet its 3.0A peak demand.
*   **Peripheral Power:** The Buck Module’s secondary output terminals provide dedicated 5V power to the **5V Submersible Pump** and **Relay VCC**, isolating motor current from the Pi’s internal power rail.

---

## 2. Physical Sensor Specifications

*   **Soil Moisture:** Capacitive v1.2 (Analog 1.2V-2.5V). Requires the **ADS1115 I2C ADC** to convert analog signals to digital values for the Pi.
*   **Temp/Humidity/Pressure:** BME280 (I2C). A precision sensor that communicates over the I2C bus (Address: 0x76).
*   **Water Level:** XKC-Y26-V Non-contact Liquid Level Sensor. Powered by 5V. Outputs a digital signal passed through a 10kΩ/20kΩ voltage divider. **System uses Fail-Safe Active-High logic (Black Mode wire to GND).** Because the voltage divider acts as a physical pull-down to Ground, a disconnected sensor sits at 0V (LOW). Active-High ensures a disconnected sensor safely reports as "LOW" (Empty), protecting the pumps.
*   **Irrigation Control:** 12V Solenoid Valves - Normally Closed (NC). Valves stay CLOSED when unpowered and open via the relay module using 12V DC.
*   **Water Pump:** 5V Submersible Pump.

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
*   [ ] **Step 4:** Using a multimeter, manually tune the XL4016 brass screw until the output is exactly 5.1V before plugging in the Raspberry Pi.

---

## 5. Pinout Reference Table (BCM Mapping)

All software implementation must reference the **BCM (Broadcom)** numbering used in the `SensorManager.py` backend.

| Hardware Component | Device Pin / Color | Raspberry Pi Pin (BCM / Physical) | Power Source & Wiring Logic |
| :--- | :--- | :--- | :--- |
| **Main Power** | Homesaya USB Jack | **Pi 4 USB-C Port** | From 8A XL4016 Buck Output |
| **I2C Bus (BME & ADS)** | SDA | **BCM 2** (Pin 3) | 3.3V from Pi (Pin 1) |
| | SCL | **BCM 3** (Pin 5) | Shared GND with Pi |
| **ADS1115 ADC** | VDD / GND | **3.3V / GND** | Powers the ADC |
| | ADDR | **GND** | Sets I2C to 0x48 |
| **Soil Moisture (Z1)** | Sensor 1 Signal | **ADS1115 A0** | Capacitive v1.2 (Analog) |
| **Soil Moisture (Z2)** | Sensor 2 Signal | **ADS1115 A1** | Capacitive v1.2 (Analog) |
| **Soil Moisture (Z3)** | Sensor 3 Signal | **ADS1115 A2** | Capacitive v1.2 (Analog) |
| **Water Level (XKC)** | Yellow (Signal) | **BCM 5** (Pin 29) | Active-High (Black to GND) / Hardware Pull-Down |
| **Relay Module (5V)** | VCC | **5V** (Pin 2 or 4) | Powered by Pi 5V Rail |
| | IN1 (Pump) | **BCM 17** (Pin 11) | COM: Buck OUT+ / NO: Pump Red |
| | IN2 (Valve 1) | **BCM 27** (Pin 13) | COM: 12V+ (IN+) / NO: Valve 1+ |
| | IN3 (Valve 2) | **BCM 22** (Pin 15) | COM: 12V+ (IN+) / NO: Valve 2+ |
| | IN4 (Valve 3) | **BCM 23** (Pin 16) | COM: 12V+ (IN+) / NO: Valve 3+ |
| **User Interface** | Reset Button | **BCM 24** (Pin 18) | One side to Pin, one to GND |
| | Feedback LED | **BCM 18** (Pin 12) | Heartbeat Pulse / Rapid Blink |

---

## 6. Solenoid & Pump Control Logic (Split-Rail Architecture)

Because the system controls a 5V Low-Voltage Pump and 12V High-Voltage Valves, the 4-channel relay module must be wired using a **"Split-Rail"** design to prevent 12V power from destroying the 5V components.

*   **Relay 1 (The 5V Pump Rail):**
    *   **COM (Common):** Wire this to the 5V Output (+) of the XL4016 Buck Converter.
    *   **NO (Normally Open):** Wire this to the Positive (+) wire of the 5V Pump.
*   **Relays 2, 3, & 4 (The 12V Solenoid Rail):**
    *   **COM (Common):** Wire these directly to the 12V Output (+) of the main power adapter. (You can daisy-chain a single 12V wire across the COM ports of Relays 2, 3, and 4).
    *   **NO (Normally Open):** Wire these to the Positive (+) wires of Valve 1, Valve 2, and Valve 3.
*   **The "Common Ground" Rule:** For the system to function safely, the Main 12V GND, the XL4016 5V GND, the Pi GND, the Pump GND, and all Valve GNDs must be physically connected together to share a single ground reference.

> [!IMPORTANT]
> **Hardware-Software Synchronization Note:**
> To prevent confusion during wiring:
> 1. **Terminal Selection:** Always use the **NO (Normally Open)** terminal on the relay. This ensures that if the Raspberry Pi loses power or the relay is de-energized, the circuit is broken and the water stops.
> 2. **Valve Type:** We use **NC (Normally Closed)** valves. These require power to open.
> 3. **Active-Low Logic:** The software treats the relay module as **Active-Low**.
>    * GPIO **HIGH (3.3V)** = Relay De-energized = Circuit Open = **Valve CLOSED**.
>    * GPIO **LOW (0V)** = Relay Energized = Circuit Closed = **Valve OPEN**.

---

## 7. Hardware Fault Mitigation & Protective Wiring

To ensure industrial-grade uptime and protect the Raspberry Pi from erratic power fluctuations and electrical hazards inherent to inductive loads, the following four electrical shields are mandatory for this "Split-Rail" configuration.

### Protective Bill of Materials (BOM)

| Component | Specification | Qty | Location / Target Device |
| :--- | :--- | :--- | :--- |
| **Inline Fuse** | 7.5A Automotive Type | 1 pc | Main 12V Input DC Line |
| **Inline Fuse** | 5A Automotive Type | 1 pc | 5.1V Buck Converter Output Line |
| **Flyback Diode** | 1N4007 Rectifier Diode | 4 pcs | 1x (5V Pump), 3x (12V Valves) |
| **Bulk Capacitor** | 1000µF Electrolytic | 1 pc | 5.1V Power Rail (Buck Converter Output) |
| **Resistor** | 10kΩ | 1 pc | Water Sensor Signal Line |
| **Resistor** | 20kΩ | 1 pc | Water Sensor Signal to Ground |

### 7.1 Overcurrent Protection (Fuses)
Fusing prevents catastrophic thermal runaway and limits damage during short-circuit events within the power rail.

*   **Wiring & Sizing:** 
    *   Install a **7.5A inline fuse** on the main **12V input** positive line, before it reaches the relays and Buck Converter. This protects the entire system against total catastrophic shorts.
    *   Install a **5A inline fuse** on the **5.1V Buck Converter output** positive line. This specifically protects the Raspberry Pi and the 5.1V logic rail in the event the 5V submersible pump jams and draws excessive current.

### 7.2 Back-EMF Suppression (Flyback Diodes)
When the mechanical relays turn off the inductive motor loads (pump or valves), collapsing magnetic fields generate destructive, high-voltage inductive spikes that travel backward through the wiring.

*   **Wiring:** Install four **1N4007 Diodes** wired in parallel directly across the terminals (positive and negative wires) of the 1 pump and the 3 normally-closed solenoid valves.
*   **Crucial Polarity:** Diodes must be explicitly wired in **"Reverse Bias"** to catch these spikes. 
    *   Connect the **Cathode (Silver Stripe)** side of the diode to the **Positive (+)** wire of the pump/valve.
    *   Connect the **Anode (Solid Black)** side of the diode to the **Ground (-)** wire. 

### 7.3 Brownout Prevention (Bulk Capacitor)
When the 5V pump kicks on, the electric motor intrinsically demands a massive transient "inrush current." Without buffering, this sharp power draw momentarily drops the 5.1V line voltage below operational thresholds, causing the Raspberry Pi to instantly crash.

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

---
## 8. Maintenance Note & Troubleshooting

The Smart Sprout system features a **Hardware-Aware Maintenance Mode**. If the app displays an orange **Wrench Icon** with a **"FAULT"** label, it means the Raspberry Pi has detected a hardware disconnect.

### Common Fault Triggers:
1.  **I2C Bus Error ([Errno 5]):** Usually indicates a loose SDA or SCL wire, or that the system experienced a power-drop (ensure your 1000µF capacitor is installed securely).
2.  **Missing Driver:** If the BME280 is connected but fails to initialize, ensure you have installed the driver specifically using the `adafruit-circuitpython-bme280` package with the `--break-system-packages` flag.
3.  **Address Conflict:** The system expects the **BME280 at 0x76** and the **ADS1115 at 0x48**. Use `i2cdetect -y 1` to verify these addresses are visible on the bus.

### Safety Hard-lock:
When a sensor is in "FAULT" state, the backend **automatically disables (Hard-locks)** all irrigation logic for that specific zone. This prevents the pump from running indefinitely due to a faulty "dry" sensor reading.

---

## 9. Scaling & Security (Unit 10+)

The hardware architecture is designed for **Commercial Scale**. To deploy multiple units, follow these physical security protocols:

### 1. The One-Line Flash
When preparing a new unit, the same `main.py` code is used. The only difference is the `.env` file containing the `DEVICE_ID`. Each Pi is a "Cloned Appliance" that points to a different row in the Firebase database.

### 2. Tamper-Proofing the Hardware
*   **Encrypted SD Partition**: Use LUKS to ensure that even if the SD card is stolen, the code cannot be read on a PC.
*   **Physical Kiosk Hardening**: Disable USB ports and external peripherals (like keyboards) so that the user is stuck "inside" the Smart Sprout UI and cannot break the system.

### 3. Binary Shielding
All Python code is compiled into a **Binary Executable** before deployment. This prevents the user from seeing your logic or modifying the watering thresholds manually.

---
