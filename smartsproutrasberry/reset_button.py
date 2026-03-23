"""
reset_button.py — Physical Factory Reset Button Monitor
═══════════════════════════════════════════════════════════

Monitors a momentary push button on GPIO 24 (configurable via .env).
When held for 5 continuous seconds, performs a full factory reset:
  1. Resets device_config.json to defaults (SPROUT_A1B2 / 1234)
  2. Wipes calibration_offsets.json
  3. Reboots the Raspberry Pi

LED Feedback (GPIO 18):
  - While held (0-5s): LED blinks rapidly (100ms on/off)
  - At 5s threshold: LED goes solid ON → reset executes → reboot
  - On early release: LED turns OFF (cancel)

Wiring:
  - Button connects GPIO 24 to GND (uses internal pull-up resistor)
  - LED connects GPIO 18 to LED anode (with 220Ω resistor) → GND
  - When pressed: pin reads LOW
  - When released: pin reads HIGH (pulled up internally)

This script runs as a background daemon thread alongside main.py,
ensuring the reset button works even if the Flutter kiosk app crashes.
"""

import time
import threading
import config

# Try to import GPIO — will fail gracefully on non-Pi hardware
try:
    import RPi.GPIO as GPIO
    GPIO_AVAILABLE = True
except (ImportError, RuntimeError):
    GPIO_AVAILABLE = False
    print("[RESET_BUTTON] RPi.GPIO not available — hardware reset disabled.")


def _led_on():
    """Turn the feedback LED on."""
    try:
        GPIO.output(config.RESET_LED_PIN, GPIO.HIGH)
    except Exception:
        pass


def _led_off():
    """Turn the feedback LED off."""
    try:
        GPIO.output(config.RESET_LED_PIN, GPIO.LOW)
    except Exception:
        pass


def _perform_factory_reset():
    """Execute the full factory reset sequence."""
    import os
    # LED solid ON during reset
    _led_on()
    print("=" * 60)
    print("[FACTORY RESET] ⚠️  HARDWARE RESET TRIGGERED!")
    print("[FACTORY RESET] Resetting device_config.json to defaults...")
    config.factory_reset()
    print("[FACTORY RESET] Reset complete. Rebooting in 3 seconds...")
    print("=" * 60)
    time.sleep(3)
    os.system("sudo reboot")


def _monitor_button():
    """
    Continuously monitors the reset button GPIO pin.
    If held LOW for RESET_HOLD_SECONDS, triggers factory reset.
    LED blinks rapidly while held, goes solid on trigger.
    """
    pin = config.RESET_BUTTON_PIN
    led_pin = config.RESET_LED_PIN
    hold_time = config.RESET_HOLD_SECONDS

    GPIO.setmode(GPIO.BCM)
    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(led_pin, GPIO.OUT)
    GPIO.output(led_pin, GPIO.LOW)  # LED off initially

    print(f"[RESET_BUTTON] Monitoring GPIO {pin} (hold {hold_time}s to reset)")
    print(f"[RESET_BUTTON] LED feedback on GPIO {led_pin}")

    while True:
        try:
            # Wait for button press (falling edge = HIGH → LOW)
            GPIO.wait_for_edge(pin, GPIO.FALLING)
        except RuntimeError as e:
            print(f"[RESET_BUTTON] GPIO wait_for_edge error on GPIO {pin}: {e}. Retrying in 5s...")
            time.sleep(5)
            continue

        # Button pressed — start blinking LED and counting
        press_start = time.time()
        held_long_enough = False
        led_state = False

        while GPIO.input(pin) == GPIO.LOW:
            elapsed = time.time() - press_start

            # Rapid blink: toggle every 100ms
            led_state = not led_state
            if led_state:
                _led_on()
            else:
                _led_off()

            if elapsed >= hold_time:
                held_long_enough = True
                break
            time.sleep(0.1)

        if held_long_enough:
            _perform_factory_reset()
            break  # After reboot command, exit the loop
        else:
            # Button released early — cancel, LED off
            _led_off()

        time.sleep(0.3)  # Debounce



def start_reset_button_monitor():
    """
    Starts the reset button monitor as a daemon thread.
    Call this from main.py during startup.
    """
    if not GPIO_AVAILABLE:
        return

    thread = threading.Thread(target=_monitor_button, daemon=True)
    thread.start()
    print(f"[RESET_BUTTON] Hardware reset monitor started (GPIO {config.RESET_BUTTON_PIN}, LED GPIO {config.RESET_LED_PIN})")
