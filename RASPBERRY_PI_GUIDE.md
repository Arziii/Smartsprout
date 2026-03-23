# 🍓 Setup Guide: SmartSprout Kiosk on Raspberry Pi

This guide covers the deployment of the **Python Backend** and **Flutter UI** to your Raspberry Pi, specifically for the SmartSprout Garden Automation System.

---

## 📑 Table of Contents
- [How to Copy Files via VNC Viewer](#-how-to-copy-files-via-vnc-viewer)
- [Alternative: Rapid File Transfer (SCP)](#-alternative-rapid-file-transfer-scp)
- [Step 1: Install & Prepare the OS](#-step-1-install--prepare-the-os)
- [Step 2: Setup the Python Backend](#-step-2-setup-the-python-backend-smartsproutrasberry)
- [Step 3: Install Flutter SDK on the Pi](#-step-3-install-flutter-sdk-on-the-pi)
- [Step 4: Build & Launch the Kiosk UI](#-step-4-build--launch-the-kiosk-ui)
- [Step 5: Configure Kiosk Auto-Start](#-step-5-configure-kiosk-auto-start-boot-to-dashboard)
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
2.  Navigate to your project folder:
    ```powershell
    cd "D:\deisgn 2\Smartsprout"
    ```
3.  Run this command (replace `<IP>` with your Pi's actual IP address):
    ```powershell
    # Copy the whole project (needed for Kiosk UI)
    scp -r "D:\deisgn 2\Smartsprout" pi@<IP-ADDRESS>:/home/pi/
    ```
4.  Enter your Pi's password when prompted.

---

## 🛠️ Step 1: Install & Prepare the OS

1.  **Flash the OS**: Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash **Raspberry Pi OS (64-bit)**.
2.  **Enable SSH & VNC**: Go to **Menu** → **Preferences** → **Raspberry Pi Configuration** → **Interfaces**.
3.  **Update the System**:
    ```bash
    sudo apt update && sudo apt upgrade -y
    sudo apt install git python3-pip python3-venv -y
    ```

---

## 🛠️ Step 2: Setup the Python Backend (`smartsproutrasberry`)

Copy your `Smartsprout` folder to `/home/pi/`. Then, move the backend to a convenient location:

1.  **Reorganize Folders**:
    ```bash
    mv /home/pi/Smartsprout/smartsproutrasberry /home/pi/
    ```
2.  **Create a Virtual Environment**:
    ```bash
    cd /home/pi/smartsproutrasberry
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    ```
3.  **Configure Security (.env)**:
    Create a `.env` file from the example to store your unique device credentials:
    ```bash
    cp .env.example .env
    nano .env
    # Ensure DEVICE_ID and DEVICE_PIN are set correctly.
    ```
4.  **Install the Reliability Watchdog (Systemd)**:
    This ensures the backend auto-starts on boot and automatically recovers from crashes.
    ```bash
    sudo cp smartsprout.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable smartsprout
    sudo systemctl start smartsprout
    ```

---

## 🛠️ Step 3: Install Flutter SDK on the Pi

The Raspberry Pi needs specific development tools to build the visual dashboard:

1.  **Install Build Tools**:
    ```bash
    sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev -y
    ```
2.  **Download Flutter**:
    ```bash
    cd /home/pi
    git clone https://github.com/flutter/flutter.git -b stable
    echo 'export PATH="$PATH:/home/pi/flutter/bin"' >> ~/.bashrc
    source ~/.bashrc
    ```
3.  **Configure for Linux**:
    ```bash
    flutter config --enable-linux-desktop
    flutter doctor
    ```

---

## 🛠️ Step 4: Build & Launch the Kiosk UI

1.  **Build the Release version**:
    ```bash
    cd /home/pi/Smartsprout/smartsprout
    flutter build linux
    ```
2.  **Launch the Dashboard**:
    ```bash
    ./build/linux/arm64/release/bundle/smartsprout
    ```

---

## 🖥️ Step 5: Configure Kiosk Auto-Start (Boot to Dashboard)

To make the dashboard launch automatically when the Pi turns on:

1.  **Create Autostart shortcut**:
    ```bash
    mkdir -p ~/.config/autostart
    nano ~/.config/autostart/smartsprout.desktop
    ```
2.  **Make the launcher executable**:
    ```bash
    chmod +x /home/pi/Smartsprout/smartsproutrasberry/start_smartsprout.sh
    ```
3.  **Paste this configuration**:
    ```ini
    [Desktop Entry]
    Type=Application
    Name=SmartSprout Kiosk
    Exec=/home/pi/Smartsprout/smartsproutrasberry/start_smartsprout.sh
    X-GNOME-Autostart-enabled=true
    ```
3.  **Hide the Mouse Cursor** (Optional):
    ```bash
    sudo apt install unclutter
    # Add 'unclutter -idle 0.1 -root' to your startup commands
    ```

---

## 📺 Recommended Resources
*   [RealVNC Official: Transferring Files](https://help.realvnc.com/hc/en-us/articles/360002251297-Transferring-Files-between-Computers)
*   [YouTube: Setting up a Headless Raspberry Pi](https://www.youtube.com/watch?v=FqE99HjR6Y0)
*   [SmartSprout Zero-Trust Architecture](file:///d:/deisgn%202/Smartsprout/Smart%20Sprout%20Flutter.md)
