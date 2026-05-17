#!/bin/bash
# start_smartsprout.sh
# ---------------------------------------------------------
# Immortal Bash Launcher for SmartSprout Kiosk
# ---------------------------------------------------------

# OpenGL Environment Variables (Pi 4 Hardware Acceleration enabled)
# Removed LIBGL_ALWAYS_SOFTWARE=1 and Mesa override to allow smooth Premium UI.

echo "Starting SmartSprout Kiosk System..."

# ── Sudoers guard: Wi-Fi connect/forget require this rule ──────────────────
SUDOERS_FILE="/etc/sudoers.d/smartsprout_nmcli"
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "⚠️  WARNING: $SUDOERS_FILE is missing."
    echo "   Wi-Fi connect/forget will fail with 'insufficient privileges'."
    echo "   Fix: sudo cp smartsproutrasberry/smartsprout_nmcli_sudoers $SUDOERS_FILE && sudo chmod 0440 $SUDOERS_FILE"
    echo "   Then: sudo systemctl restart smartsprout_backend"
    echo "        sudo chmod 0440 $SUDOERS_FILE"
fi

# 1. Start Python Backend in the background
cd /home/smartsprout/Smartsprout/smartsproutrasberry
source venv/bin/activate
python3 -u main.py > /tmp/smartsprout.log 2>&1 &
BACKEND_PID=$!

echo "Python Backend running on PID: $BACKEND_PID"

# 2. Start Flutter UI in an immortal while loop
cd /home/smartsprout/Smartsprout/smartsprout

while true; do
    echo "[LAUNCHER] Starting Flutter Dashboard..."
    ./build/linux/arm64/release/bundle/smartsprout
    
    echo "[LAUNCHER] Flutter App closed or crashed. Relaunching in 2 seconds..."
    sleep 2
done
