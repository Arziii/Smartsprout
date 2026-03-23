import firebase_admin
from firebase_admin import credentials, firestore
import config
import os
import sys

print('Starting script...')

if not os.path.exists(config.FIREBASE_CREDENTIALS_PATH):
    print(f'Missing credentials at {config.FIREBASE_CREDENTIALS_PATH}')
    sys.exit(1)

print('Initializing firebase...')
cred = credentials.Certificate(config.FIREBASE_CREDENTIALS_PATH)
firebase_admin.initialize_app(cred)

print('Connecting to firestore...')
db = firestore.client()

print(f'Fetching doc_ref for {config.DEVICE_ID}...')
doc_ref = db.collection('devices').document(config.DEVICE_ID)

print('Setting data...')
doc_ref.set({'hashed_pin': '1234', 'name': 'Test Device'}, merge=True)

print('Done!')
