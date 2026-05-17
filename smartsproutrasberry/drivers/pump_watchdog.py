"""
pump_watchdog.py — Safety Pump Timeout Watchdog
═══════════════════════════════════════════════════════════

Monitors all relay GPIO pins (3 independent pumps). If any relay stays
active (LOW) for more than PUMP_TIMEOUT_SECONDS (default: 120s),
this watchdog forces it HIGH (off) at the hardware level.

This runs as a background daemon thread and operates independently
of Firebase, providing a hardware-level safety net against flooding
due to internet loss or software bugs.
"""

import time
import threading
import config

try:
    import RPi.GPIO as GPIO
    GPIO_AVAILABLE = True
except (ImportError, RuntimeError):
    GPIO_AVAILABLE = False
    print("[PUMP_WATCHDOG] RPi.GPIO not available — pump watchdog disabled.")

# Track how long each relay has been continuously ON
_relay_on_since = {}


def _monitor_relays():
    """Continuously checks all relay pins for timeout violations."""
    timeout = config.PUMP_TIMEOUT_SECONDS
    all_pins = config.ALL_RELAY_PINS  # [17, 27, 22] — 3 independent pump relays

    print(f"[PUMP_WATCHDOG] Monitoring {len(all_pins)} relay pins (timeout: {timeout}s)")

    while True:
        for pin in all_pins:
            try:
                # Active-LOW relay: GPIO.LOW means relay is ON
                is_active = GPIO.input(pin) == GPIO.LOW
            except Exception:
                continue

            if is_active:
                if pin not in _relay_on_since:
                    _relay_on_since[pin] = time.time()
                else:
                    elapsed = time.time() - _relay_on_since[pin]
                    if elapsed >= timeout:
                        # SAFETY SHUTOFF
                        print("=" * 60)
                        print(f"[PUMP_WATCHDOG] ⚠️  SAFETY SHUTOFF — GPIO {pin} ON for {elapsed:.0f}s!")
                        print(f"[PUMP_WATCHDOG] Forcing GPIO {pin} HIGH (off)")
                        print("=" * 60)
                        GPIO.output(pin, GPIO.HIGH)
                        _relay_on_since.pop(pin, None)
            else:
                # Relay is off — reset the timer
                _relay_on_since.pop(pin, None)

        time.sleep(1)  # Check every second


def start_pump_watchdog():
    """
    Starts the pump safety watchdog as a daemon thread.
    Call this from main.py during startup.
    """
    if not GPIO_AVAILABLE:
        return

    thread = threading.Thread(target=_monitor_relays, daemon=True)
    thread.start()
    print(f"[PUMP_WATCHDOG] Safety watchdog started (timeout: {config.PUMP_TIMEOUT_SECONDS}s)")
