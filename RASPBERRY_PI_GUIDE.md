# 🍓 Setup Guide: SmartSprout Kiosk on Raspberry Pi

This guide covers the complete deployment of the **Python Backend** (`main.py` / `auth_bouncer.py`) and **Flutter Kiosk UI** to your Raspberry Pi 4 for the SmartSprout Garden Automation System.

> **Key Architecture Note:** On the Raspberry Pi, the Flutter Kiosk UI reads live sensor data directly from `/tmp/smartsprout_telemetry.json` written by `main.py` — no Firebase, no internet, no API quota cost.

---

## 📑 Table of Contents
- [How to Copy Files via VNC Viewer](#-how-to-copy-files-via-vnc-viewer)
- [Alternative: Rapid File Transfer (SCP)](#-alternative-rapid-file-transfer-scp)
- [Step 1: Install & Prepare the OS](#-step-1-install--prepare-the-os)
- [Step 2: Setup the Python Backend](#-step-2-setup-the-python-backend-smartsproutrasberry)
- [Step 3: Install Flutter SDK on the Pi](#-step-3-install-flutter-sdk-on-the-pi)
- [Step 4: Build & Launch the Kiosk UI](#-step-4-build--launch-the-kiosk-ui)
- [Step 5: Configure Kiosk Auto-Start](#-step-5-configure-kiosk-auto-start-boot-to-dashboard)
- [Hardware Pin Mapping](#-hardware-pin-mapping)
- [Kiosk Data Architecture](#-kiosk-data-architecture)
- [Scaling to Multiple Units](#-scaling-to-multiple-units)
- [Production Security](#-production-deployment--security-unit-10)
- [Recommended Resources](#-recommended-resources)

---

## 📂 How to Copy Files via VNC Viewer

If you are using **RealVNC Viewer** (the default for Raspberry Pi) to remotely control your Pi's desktop, copying files from your Windows PC is built-in.

### 1. Using the VNC Toolbar (Easiest)
1.  **Open the VNC Viewer session** to your Raspberry Pi.
2.  **Move your mouse to the top-middle** of the VNC Viewer window (on your computer side) to reveal the **Toolbar**.
3.  Click the **File Transfer** icon (it looks like two arrows ⇄ or a folder icon).
4.  Click **"Send Files..."** and select the folder or file from your Windows PC (e.g., your `smartsproutrasberry` folder).
5.  On the Raspberry Pi, a dialog will appear showing the transfer progress. By default, files are saved to the **Desktop** or your **Home (`/home/pi`)** folder.

### 2. Troubleshooting VNC Transfers
If the transfer button doesn't work or you don't see it:
*   **Check VNC Server Settings**: On the Raspberry Pi taskbar, click the VNC icon (near the clock) → Menu (≡) → **Options** → **File Transfer**. Ensure it is **Enabled**.
*   **Lite OS Limit**: If you installed "Raspberry Pi OS Lite" (no desktop), the VNC file transfer GUI will not work. You should use the **SCP method** below.

---

## ⚡ Alternative: Rapid File Transfer (SCP)

For large folders, using the command line is significantly faster than VNC's file transfer:

1.  Open **PowerShell** or **Command Prompt** on your Windows PC.
2.  Run these commands (replace `<IP>` with your Pi's actual IP address):
    ```powershell
    # Copy the backend (Python)
    scp -r "D:\deisgn2\Smartsprout\smartsproutrasberry" smartsprout@192.168.1.7:/home/smartsprout/Smartsprout/

    # Copy the UI (Flutter lib only — faster than full project)
    scp -r "D:\deisgn2\Smartsprout\smartsprout\lib" smartsprout@192.168.1.7:/home/smartsprout/Smartsprout/smartsprout/
    ```
3.  Enter your Pi's password when prompted.

---

## 🛠️ Step 1: Install & Prepare the OS

1.  **Flash the OS**: Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash **Raspberry Pi OS (64-bit, Bookworm)**.
2.  **Power Supply Note**: The Raspberry Pi 4 is powered via an **XL4016 High-Current Buck Module (8A)** stepped down from a **12V 8A** master supply. Calibrate the buck converter to exactly **5.1V via the Homesaya USB Jack** before connecting the Pi.
3.  **Enable SSH & VNC**: Go to **Menu** → **Preferences** → **Raspberry Pi Configuration** → **Interfaces**.
4.  **Update the System**:
    ```bash
    sudo apt update && sudo apt upgrade -y
    sudo apt install git python3-pip python3-venv i2c-tools -y
    ```
5.  **Enable I2C Hardware Interface**:
    ```bash
    sudo raspi-config
    # → Interfacing Options → I2C → Enable
    ```
6.  **Verify Sensors on I2C Bus**:
    ```bash
    i2cdetect -y 1
    # Expected: 0x48 (ADS1115), 0x76 (BME280)
    ```
7.  **Enable 2GB Swap** (prevents memory pressure during Flutter build):
    ```bash
    free -h  # Check swap — should show ~2.0G
    ```

---

## 🛠️ Step 2: Setup the Python Backend (`smartsproutrasberry`)

1.  **Place project files**:
    ```bash
    # Files should be at:
    /home/smartsprout/Smartsprout/smartsproutrasberry/
    ```
2.  **Create a Virtual Environment**:
    ```bash
    cd /home/smartsprout/Smartsprout/smartsproutrasberry
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    ```
    Or use the one-line install:
    ```bash
    sudo apt-get install -y python3-dev libgpiod-dev && \
    pip3 install adafruit-circuitpython-bme280 adafruit-circuitpython-ads1x15 \
    gpiozero python-dotenv firebase-admin smbus2 --break-system-packages
    ```
3.  **Configure Security (`.env`)**:
    ```bash
    cp .env.example .env
    nano .env
    # Set DEVICE_ID=SPROUT_A1B2 (or your unique ID)
    # Set FIREBASE_CREDENTIALS_PATH=./firebase-adminsdk.json
    ```
4.  **Configure Password (`device_config.json`)**:
    - On **first boot**, `auth_bouncer.py` automatically migrates any plaintext or SHA-256 password to PBKDF2-HMAC-SHA256.
    - Watch for: `[AUTH_BOUNCER] ✅ PIN silently upgraded from SHA-256 to PBKDF2-HMAC-SHA256.`
5.  **Verify Telemetry Cache** (after backend starts):
    ```bash
    # main.py writes this file every 3 seconds.
    # The Flutter Kiosk UI reads it directly — NO Firebase needed on-device.
    cat /tmp/smartsprout_telemetry.json
    ```
6.  **Install the Reliability Watchdog (Systemd)**:
    ```bash
    sudo cp smartsprout.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable smartsprout
    sudo systemctl start smartsprout
    sudo systemctl status smartsprout  # Verify it is active (running)
    ```
7.  **Setup Zero-Trust Wi-Fi Access (Sudoers)**:
    To allow the Pi UI to switch Wi-Fi networks without requiring a root password prompt, create a sudo drop-in:
    ```bash
    echo "smartsprout ALL=(ALL) NOPASSWD: /usr/bin/nmcli dev wifi connect *, /usr/bin/nmcli connection delete *" | sudo tee /etc/sudoers.d/smartsprout_nmcli
    sudo chmod 0440 /etc/sudoers.d/smartsprout_nmcli
    ```

---

## 🛠️ Step 3: Install Flutter SDK on the Pi

The Raspberry Pi needs specific development tools to compile the visual Kiosk dashboard:

1.  **Install Build Tools**:
    ```bash
    sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev -y
    ```
2.  **Download Flutter**:
    ```bash
    cd /home/smartsprout
    git clone https://github.com/flutter/flutter.git -b stable
    echo 'export PATH="$PATH:/home/smartsprout/flutter/bin"' >> ~/.bashrc
    source ~/.bashrc
    ```
3.  **Configure for Linux Desktop**:
    ```bash
    flutter config --enable-linux-desktop
    flutter doctor  # All items must pass except Android/iOS (not needed)
    ```

---

## 🛠️ Step 4: Build & Launch the Kiosk UI

1.  **Get dependencies**:
    ```bash
    cd /home/smartsprout/Smartsprout/smartsprout
    flutter pub get
    ```
2.  **Build the Release version**:
    ```bash
    flutter build linux --release
    ```
3.  **Launch the Dashboard**:
    ```bash
    ./build/linux/arm64/release/bundle/smartsprout
    ```

> **Important:** Start `main.py` (the Python backend) **before** launching the Flutter UI. The Kiosk reads `/tmp/smartsprout_telemetry.json` — if `main.py` is not running, it will show "offline" status until the file appears.

---

## 🖥️ Step 5: Configure Kiosk Auto-Start (Boot to Dashboard)

To make both the backend and dashboard launch automatically when the Pi turns on:

1.  **Ensure the systemd service** (from Step 2) is enabled — this handles `main.py` auto-start.
2.  **Create Autostart shortcut for Flutter UI**:
    ```bash
    mkdir -p ~/.config/autostart
    nano ~/.config/autostart/smartsprout.desktop
    ```
3.  **Paste this configuration**:
    ```ini
    [Desktop Entry]
    Type=Application
    Name=SmartSprout Kiosk
    Exec=/home/smartsprout/Smartsprout/smartsproutrasberry/start_smartsprout.sh
    X-GNOME-Autostart-enabled=true
    ```
4.  **Make the launcher executable**:
    ```bash
    chmod +x /home/smartsprout/Smartsprout/smartsproutrasberry/start_smartsprout.sh
    ```
5.  **Hide the Mouse Cursor** (Optional — cleaner kiosk look):
    ```bash
    sudo apt install unclutter
    # Add 'unclutter -idle 0.1 -root &' to start_smartsprout.sh
    ```

---

## 🔌 Hardware Pin Mapping (BCM Reference)

Full wiring reference for `main.py`, `sensors.py`, and `pump_watchdog.py`. See [HARDWARE_SETUP.md](./HARDWARE_SETUP.md) for protective wiring (fuses, flyback diodes, capacitors).

| Hardware Component | Device Pin / Color | GPIO (BCM / Physical) | Power Source & Wiring Logic |
| :--- | :--- | :--- | :--- |
| **Main Power** | Homesaya USB Jack | **Pi 4 USB-C Port** | 8A XL4016 Buck Output (5.1V) |
| **I2C SDA** | SDA | **BCM 2** (Pin 3) | 3.3V from Pi (Pin 1) |
| **I2C SCL** | SCL | **BCM 3** (Pin 5) | Shared GND with Pi |
| **ADS1115 ADC** | VDD / GND | **3.3V / GND** | Powers ADC chip (I2C addr: 0x48) |
| | ADDR | **GND** | Sets address to 0x48 |
| **Soil Moisture Z1** | Signal | **ADS1115 A0** | Capacitive v1.2 (1.2V–2.5V Analog) |
| **Soil Moisture Z2** | Signal | **ADS1115 A1** | Capacitive v1.2 (1.2V–2.5V Analog) |
| **Soil Moisture Z3** | Signal | **ADS1115 A2** | Capacitive v1.2 (1.2V–2.5V Analog) |
| **BME280** | SDA / SCL | **BCM 2 / BCM 3** | I2C addr: 0x76 (Temp/Hum/Pressure) |
| **Water Level (XKC)** | Yellow (Signal) | **BCM 5** (Pin 29) | Active-Low / Pull-Up / 1kΩ/2kΩ Divider |
| **Relay VCC** | VCC | **5V** (Pin 2 or 4) | Pi 5V Rail |
| **Relay IN1 — Pump** | IN1 | **BCM 17** (Pin 11) | COM: XL4016 5V OUT+ / NO: Pump (+) |
| **Relay IN2 — Valve 1** | IN2 | **BCM 27** (Pin 13) | COM: 12V+ / NO: Valve 1+ |
| **Relay IN3 — Valve 2** | IN3 | **BCM 22** (Pin 15) | COM: 12V+ / NO: Valve 2+ |
| **Relay IN4 — Valve 3** | IN4 | **BCM 23** (Pin 16) | COM: 12V+ / NO: Valve 3+ |
| **Reset Button** | Signal | **BCM 24** (Pin 18) | One side to GPIO, one to GND |
| **Status LED** | Anode (+) | **BCM 18** (Pin 12) | Long leg → GPIO / Short leg → GND |

> **Active-Low Relay Logic:** GPIO LOW (0V) = Relay ON = Valve OPEN. GPIO HIGH (3.3V) = Relay OFF = Valve CLOSED.

---

## 🌿 Kiosk Data Architecture

Understanding how the Pi kiosk works **without Firebase**:

```
┌─────────────────────────────────────────────────────────────┐
│                   Raspberry Pi (Localhost)                   │
│                                                             │
│  main.py ──────────► /tmp/smartsprout_telemetry.json       │
│  (sensors read       (overwritten every 3 seconds)          │
│   every 3s)                                                 │
│                              ▲                              │
│  Flutter Kiosk               │ reads directly               │
│  (data_service.dart) ────────┘ (no HTTP, no Firebase)       │
│    First read = immediate on app open                       │
│    Subsequent = every 3 seconds                             │
└─────────────────────────────────────────────────────────────┘
```

**Commands** (pump on/off, calibration writes) are sent from the Kiosk to Firestore via REST API — so the Python backend can pick them up from the cloud command queue. But **reading sensor data is always local**.

---

## 🚀 Scaling to Multiple Units (Unit 2, Unit 3, etc.)

If you are deploying this system for multiple customers, you do **not** need to change the Python code logic. Each unit is differentiated only by its `.env` file.

### 1. The One-Line Config
For every new Raspberry Pi, modify only the `.env` file:
```bash
# In /home/smartsprout/smartsproutrasberry/.env
DEVICE_ID="SPROUT_002"   # Change this for every hardware unit
```

### 2. Firebase Registration
1.  Open your **Firebase Console** → **Firestore Database**.
2.  In the `devices` collection, click **Add Document**.
3.  Set the **Document ID** to match your new `DEVICE_ID` (e.g., `SPROUT_002`).
4.  Add the following fields:
    *   `device_name`: `"New Garden"` (String)
    *   `status`: `"offline"` (String)

### 3. Verification
Once the Pi 2 starts, it will automatically begin sending data to the `SPROUT_002` document. The same Flutter app you built for Pi 1 will now be able to log into Pi 2 using its unique credentials.

---

## 🔐 Production Deployment & Security (Unit 10+)

When transitioning from the prototype to a commercial product, follow this security checklist:

### 1. Protect the Source Code
*   **Compile to Binary**: Use tools like `PyInstaller` or `Cython` to convert your `.py` files into a single binary executable.
*   **Why?** Users will not be able to read or edit your code; the logic is hidden in machine language.

### 2. Physical & OS Hardening
*   **Disable SSH/VNC**: Remove all remote access protocols on the customer unit.
*   **Kernel Lockdown**: Disable keyboard shortcuts (Ctrl+C, Alt+F4) during boot to prevent users from exiting your Smart Sprout Kiosk.
*   **SD Card Encryption**: Use LUKS to encrypt the storage, so even if the SD card is removed, the data cannot be read.

### 3. Zero-Touch Scaling
*   **Uniform Firmware**: One Python binary and one Flutter app build for all 100 units.
*   **Environment Variables**: Only the `.env` file changes (the Device ID).
*   **Firebase Registry**: All units managed as unique documents in a single Firebase project.

---

## 📺 Recommended Resources
*   [RealVNC Official: Transferring Files](https://help.realvnc.com/hc/en-us/articles/360002251297-Transferring-Files-between-Computers)
*   [YouTube: Setting up a Headless Raspberry Pi](https://www.youtube.com/watch?v=FqE99HjR6Y0)
*   [SmartSprout Hardware Setup](./HARDWARE_SETUP.md)
*   [SmartSprout Full Architecture](./Smart%20Sprout%20Flutter.md)
