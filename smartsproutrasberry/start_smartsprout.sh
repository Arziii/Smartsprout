#!/bin/bash
# start_smartsprout.sh
# ---------------------------------------------------------
# Immortal Bash Launcher for SmartSprout Kiosk
# ---------------------------------------------------------

# OpenGL Environment Variables (Pi 4 Hardware Acceleration enabled)
# Removed LIBGL_ALWAYS_SOFTWARE=1 and Mesa override to allow smooth Premium UI.

echo "Starting SmartSprout Kiosk System..."

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
    
    echo "[LAUNCHER] Flutter App closed or crashed. Relaunching in 5 seconds..."
    sleep 5
done
