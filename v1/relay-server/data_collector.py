#!/usr/bin/env python3
"""
Data Collector Module for ML Training Data

Thread-safe collection of raw OSC data (EEG, ACC, GYRO, jaw_clench events)
to JSONL format for later conversion to V2-compatible parquet.
"""

import json
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional


class DataCollector:
    """Thread-safe raw OSC data collector with buffered writes."""

    def __init__(
        self,
        output_dir: str = "data/raw",
        buffer_size: int = 1000,
        session_id: Optional[str] = None
    ):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.buffer_size = buffer_size
        self.session_id = session_id or datetime.now().strftime("%Y%m%d_%H%M%S")

        # Output file
        self.output_file = self.output_dir / f"osc_raw_{self.session_id}.jsonl"

        # Thread-safe buffer
        self._buffer: list[dict] = []
        self._lock = threading.Lock()
        self._sample_count = 0
        self._file_handle = None

        # Stats per stream type
        self._stream_counts = {
            "eeg": 0,
            "acc": 0,
            "gyro": 0,
            "jaw_clench": 0
        }

    def start(self):
        """Open the output file for writing."""
        self._file_handle = open(self.output_file, "a")

    def stop(self) -> dict:
        """Flush remaining buffer and close file. Returns stats."""
        self._flush()
        if self._file_handle:
            self._file_handle.close()
            self._file_handle = None

        return {
            "session_id": self.session_id,
            "output_file": str(self.output_file),
            "total_samples": self._sample_count,
            "stream_counts": self._stream_counts.copy()
        }

    def record_eeg(self, tp9: float, af7: float, af8: float, tp10: float):
        """Record EEG sample (4 channels from Mind Monitor)."""
        self._record({
            "ts": time.time(),
            "stream": "eeg",
            "tp9": tp9,
            "af7": af7,
            "af8": af8,
            "tp10": tp10
        })
        self._stream_counts["eeg"] += 1

    def record_acc(self, x: float, y: float, z: float):
        """Record accelerometer sample."""
        self._record({
            "ts": time.time(),
            "stream": "acc",
            "x": x,
            "y": y,
            "z": z
        })
        self._stream_counts["acc"] += 1

    def record_gyro(self, x: float, y: float, z: float):
        """Record gyroscope sample."""
        self._record({
            "ts": time.time(),
            "stream": "gyro",
            "x": x,
            "y": y,
            "z": z
        })
        self._stream_counts["gyro"] += 1

    def record_jaw_clench(self):
        """Record jaw clench event (used as automatic label)."""
        self._record({
            "ts": time.time(),
            "stream": "jaw_clench",
            "detected": True
        })
        self._stream_counts["jaw_clench"] += 1

    def _record(self, data: dict):
        """Add record to buffer, flush if full."""
        with self._lock:
            self._buffer.append(data)
            self._sample_count += 1

            if len(self._buffer) >= self.buffer_size:
                self._flush_unlocked()

    def _flush(self):
        """Flush buffer to disk (thread-safe)."""
        with self._lock:
            self._flush_unlocked()

    def _flush_unlocked(self):
        """Flush buffer to disk (must hold lock)."""
        if not self._buffer or not self._file_handle:
            return

        for record in self._buffer:
            self._file_handle.write(json.dumps(record) + "\n")
        self._file_handle.flush()
        self._buffer.clear()

    @property
    def sample_count(self) -> int:
        """Get current sample count."""
        return self._sample_count

    @property
    def stream_counts(self) -> dict:
        """Get counts per stream type."""
        return self._stream_counts.copy()
