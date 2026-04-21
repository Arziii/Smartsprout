import RPi.GPIO as GPIO
import time

def diagnose_pin(pin=5):
    print(f"--- Diagnosing BCM Pin {pin} ---")
    GPIO.setmode(GPIO.BCM)
    
    # Test 1: Pull UP
    print("\nTest 1: applying internal PULL-UP (3.3V)...")
    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    time.sleep(0.5)  # give plenty of time for capacitance to charge
    up_val = GPIO.input(pin)
    print(f"Result: {up_val} (Expected: 1 if floating)")
    
    # Test 2: Pull DOWN
    print("\nTest 2: applying internal PULL-DOWN (0.0V)...")
    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
    time.sleep(0.5)
    down_val = GPIO.input(pin)
    print(f"Result: {down_val} (Expected: 0 if floating)")

    print("\n--- DIAGNOSIS ---")
    if up_val == 1 and down_val == 0:
        print("Diagnosis: Pin is floating (Disconnected). Software disconnection guard SHOULD catch this.")
    elif up_val == 0 and down_val == 0:
        print("Diagnosis: Pin is STRONGLY GROUNDED! Something physical is forcing the pin to 0V.")
        print("Possible causes: Bad solder joint shorted to Ground, or a strong (e.g. 10k) hardware pull-down resistor on your custom board.")
    elif up_val == 1 and down_val == 1:
        print("Diagnosis: Pin is STRONGLY HIGH! Something physical is forcing the pin to 3.3V or 5V.")
    else:
        print(f"Diagnosis: Unstable / Flapping values ({up_val}, {down_val}). Severe electrical noise.")
        
    GPIO.cleanup()

if __name__ == "__main__":
    try:
        diagnose_pin()
    except Exception as e:
        print(f"Failed to run diagnosis: {e}")
