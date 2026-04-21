"""
Smart Sprout — Local SQLite Persistence Layer
──────────────────────────────────────────────────────────
Provides offline-resilient storage for telemetry data.
Uses a "Store-and-Forward" pattern:
  1. Every Eco-Mode reading is saved here FIRST with synced=0.
  2. When Firebase push succeeds, rows are marked synced=1.
  3. On next online window, all unsynced rows are batch-uploaded.

Design Decisions:
  - WAL (Write-Ahead Logging) mode protects against SD card
    corruption on sudden power loss.
  - Only Eco-Mode (30-min) readings are stored — not every 3s.
    This keeps the DB tiny (~50KB for 7 days) and safe for SD cards.
  - Rows older than RETENTION_DAYS are auto-purged to prevent
    the SQLite file from growing indefinitely.
──────────────────────────────────────────────────────────
"""
import sqlite3
import time
import os

# ── Path: stored alongside the other config files on the Pi ──
_DB_PATH = os.path.join(os.path.dirname(__file__), 'telemetry.db')

# Keep 7 days of local history (matches the Flutter analytics window)
RETENTION_DAYS = 7


def _get_connection() -> sqlite3.Connection:
    """
    Opens a connection to the SQLite database.
    WAL mode is set on every connection for crash safety.
    """
    conn = sqlite3.connect(_DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")  # Balanced safety/speed for SD cards
    return conn


def init_db():
    """
    Creates the telemetry table if it does not already exist.
    Safe to call on every startup — uses CREATE TABLE IF NOT EXISTS.
    """
    try:
        with _get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS telemetry (
                    id          INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp   INTEGER NOT NULL,
                    moisture_b1 REAL    DEFAULT 0.0,
                    moisture_b2 REAL    DEFAULT 0.0,
                    moisture_b3 REAL    DEFAULT 0.0,
                    temperature REAL    DEFAULT 0.0,
                    humidity    REAL    DEFAULT 0.0,
                    synced      INTEGER DEFAULT 0
                )
            """)
            # Index on timestamp for fast range queries (7-day window)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_telemetry_timestamp
                ON telemetry (timestamp);
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_telemetry_synced
                ON telemetry (synced);
            """)
        print("[LOCAL_DB] SQLite database initialized ✓")
    except Exception as e:
        print(f"[LOCAL_DB_ERROR] Failed to init database: {e}")


def save_reading(telemetry: dict) -> int | None:
    """
    Saves a single telemetry snapshot to SQLite with synced=0.
    Returns the row ID on success, or None on failure.

    Args:
        telemetry: The same dict produced by collect_telemetry() in main.py.
    """
    try:
        soil = telemetry.get('soil_moisture', {})
        # Handle both dict and list formats for soil_moisture
        if isinstance(soil, dict):
            b1 = float(soil.get('bed1', 0.0))
            b2 = float(soil.get('bed2', 0.0))
            b3 = float(soil.get('bed3', 0.0))
        elif isinstance(soil, list) and len(soil) >= 3:
            b1, b2, b3 = float(soil[0]), float(soil[1]), float(soil[2])
        else:
            b1, b2, b3 = 0.0, 0.0, 0.0

        ts = int(telemetry.get('timestamp', time.time()))
        temp = float(telemetry.get('temperature', 0.0))
        hum = float(telemetry.get('humidity', 0.0))

        with _get_connection() as conn:
            cursor = conn.execute("""
                INSERT INTO telemetry
                    (timestamp, moisture_b1, moisture_b2, moisture_b3, temperature, humidity, synced)
                VALUES (?, ?, ?, ?, ?, ?, 0)
            """, (ts, b1, b2, b3, temp, hum))
            row_id = cursor.lastrowid

        print(f"[LOCAL_DB] Saved reading #{row_id} "
              f"(ts={ts}, b1={b1:.1f}%, b2={b2:.1f}%, b3={b3:.1f}%, "
              f"temp={temp:.1f}°C, hum={hum:.1f}%) [unsynced]")
        return row_id

    except Exception as e:
        print(f"[LOCAL_DB_ERROR] Failed to save reading: {e}")
        return None


def mark_synced(row_ids: list[int]):
    """
    Marks a list of row IDs as synced=1 after a successful Firebase push.

    Args:
        row_ids: List of integer primary keys from the telemetry table.
    """
    if not row_ids:
        return
    try:
        placeholders = ','.join('?' for _ in row_ids)
        with _get_connection() as conn:
            conn.execute(
                f"UPDATE telemetry SET synced=1 WHERE id IN ({placeholders})",
                row_ids
            )
        print(f"[LOCAL_DB] Marked {len(row_ids)} row(s) as synced ✓")
    except Exception as e:
        print(f"[LOCAL_DB_ERROR] Failed to mark rows as synced: {e}")


def get_unsynced_records(limit: int = 50) -> list[dict]:
    """
    Returns up to `limit` unsynced telemetry records, oldest-first.
    Used by the Recovery Engine to find and upload missed readings.

    Returns:
        List of dicts with keys: id, timestamp, soil_moisture (dict),
        temperature, humidity.
    """
    try:
        with _get_connection() as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT id, timestamp, moisture_b1, moisture_b2, moisture_b3,
                       temperature, humidity
                FROM   telemetry
                WHERE  synced = 0
                ORDER  BY timestamp ASC
                LIMIT  ?
            """, (limit,))
            rows = cursor.fetchall()

        records = []
        for row in rows:
            records.append({
                'id':        row['id'],
                'timestamp': row['timestamp'],
                'soil_moisture': {
                    'bed1': row['moisture_b1'],
                    'bed2': row['moisture_b2'],
                    'bed3': row['moisture_b3'],
                },
                'temperature': row['temperature'],
                'humidity':    row['humidity'],
            })

        if records:
            print(f"[LOCAL_DB] Found {len(records)} unsynced record(s) for recovery.")
        return records

    except Exception as e:
        print(f"[LOCAL_DB_ERROR] Failed to fetch unsynced records: {e}")
        return []


def purge_old_records():
    """
    Deletes records older than RETENTION_DAYS from the database.
    Should be called once on startup (and optionally daily) to keep the
    SQLite file small and protect the SD card from unnecessary storage growth.
    """
    try:
        cutoff = int(time.time()) - (RETENTION_DAYS * 86400)
        with _get_connection() as conn:
            cursor = conn.execute(
                "DELETE FROM telemetry WHERE timestamp < ?", (cutoff,)
            )
            deleted = cursor.rowcount
        if deleted > 0:
            print(f"[LOCAL_DB] Purged {deleted} old record(s) "
                  f"(older than {RETENTION_DAYS} days) ✓")
    except Exception as e:
        print(f"[LOCAL_DB_ERROR] Failed to purge old records: {e}")


def get_stats() -> dict:
    """
    Returns summary statistics for monitoring/debugging.
    """
    try:
        with _get_connection() as conn:
            total = conn.execute("SELECT COUNT(*) FROM telemetry").fetchone()[0]
            unsynced = conn.execute(
                "SELECT COUNT(*) FROM telemetry WHERE synced=0"
            ).fetchone()[0]
            size_bytes = os.path.getsize(_DB_PATH) if os.path.exists(_DB_PATH) else 0
        return {
            'total_records': total,
            'unsynced_records': unsynced,
            'db_size_kb': round(size_bytes / 1024, 1),
        }
    except Exception as e:
        print(f"[LOCAL_DB_ERROR] Failed to get stats: {e}")
        return {}
