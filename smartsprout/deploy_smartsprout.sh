#!/bin/bash

# ==============================================================================
# deploy_smartsprout.sh
# Master Deployment Script for Smart Sprout Raspberry Pi Kiosk
# ==============================================================================

# Exit immediately on errors
set -e

echo "Starting Smart Sprout Kiosk Deployment..."

# Determine the absolute directory of this script (assumed to be project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="smartsprout"
BUNDLE_PATH="${PROJECT_ROOT}/build/linux/arm64/release/bundle/${APP_NAME}"

echo "Project root detected as: ${PROJECT_ROOT}"
echo "Compiled app bundle path: ${BUNDLE_PATH}"

# ------------------------------------------------------------------------------
# 1. Install Dependencies
# ------------------------------------------------------------------------------
echo "[1/5] Updating apt-get and installing 'unclutter' to hide mouse cursor..."
sudo apt-get update
sudo apt-get install -y unclutter

# ------------------------------------------------------------------------------
# 2. Hardware Touch Calibration
# ------------------------------------------------------------------------------
echo "[2/5] Configuring touch matrix in /usr/share/X11/xorg.conf.d/99-touch.conf..."
sudo mkdir -p /usr/share/X11/xorg.conf.d
sudo tee /usr/share/X11/xorg.conf.d/99-touch.conf > /dev/null << 'EOF'
Section "InputClass"
    Identifier "calibration"
    MatchProduct "10-0038 generic ft5x06 (79)"
    Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
EndSection
EOF

# ------------------------------------------------------------------------------
# 3. Compile the App
# ------------------------------------------------------------------------------
echo "[3/5] Navigating to Flutter project root and compiling release bundle..."
cd "${PROJECT_ROOT}"
flutter build linux --release

# ------------------------------------------------------------------------------
# 4. Configure Kiosk Autostart
# ------------------------------------------------------------------------------
echo "[4/5] Overwriting /etc/xdg/lxsession/LXDE-pi/autostart..."
AUTOSTART_FILE="/etc/xdg/lxsession/LXDE-pi/autostart"
sudo mkdir -p "$(dirname "$AUTOSTART_FILE")"
sudo tee "$AUTOSTART_FILE" > /dev/null << EOF
# Disabled standard desktop components for kiosk mode
#@lxpanel --profile LXDE-pi
#@xscreensaver -no-splash

# Keep desktop manager
@pcmanfm --desktop

# Hide the mouse cursor after 0.1 seconds of inactivity
@unclutter -idle 0.1 -root

# Rotate the display right
@xrandr --output DSI-1 --rotate right

# Launch the compiled Flutter Linux kiosk app
${BUNDLE_PATH}
EOF

# ------------------------------------------------------------------------------
# 5. Finalize
# ------------------------------------------------------------------------------
echo "[5/5] Deployment complete! The Raspberry Pi will reboot in 5 seconds..."
sleep 5
sudo reboot
