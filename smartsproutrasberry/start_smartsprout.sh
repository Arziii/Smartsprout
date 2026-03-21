#!/bin/bash
# start_smartsprout.sh
# ---------------------------------------------------------
# Immortal Bash Launcher for SmartSprout Kiosk
# ---------------------------------------------------------

# OpenGL Environment Overrides for Raspberry Pi 3/4
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_GL_VERSION_OVERRIDE=3.3

echo "Starting SmartSprout Kiosk System..."

# 1. Start Python Backend in the background
cd /home/smartsprout/Smartsprout/smartsproutrasberry
source venv/bin/activate
python3 main.py &
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
