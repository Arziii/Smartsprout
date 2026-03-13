import json
import paho.mqtt.client as mqtt
import time

broker = "broker.hivemq.com"
port = 1883
topic = "smartsprout/settings/cmd"

client = mqtt.Client(client_id="test_publisher_1234", clean_session=True)
client.connect(broker, port)

# Test adjust_offset +1 for zone 1
payload = {
    "command": "adjust_offset",
    "zone": 1,
    "adjustment": 1
}
client.publish(topic, json.dumps(payload))
print(f"Published adjust_offset to {topic}")

time.sleep(1)

# Test dry_calibrate
payload2 = {
    "command": "dry_calibrate"
}
client.publish(topic, json.dumps(payload2))
print("Published dry_calibrate")

time.sleep(1)

client.disconnect()
