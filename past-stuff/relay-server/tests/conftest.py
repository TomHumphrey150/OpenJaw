"""
Shared fixtures for relay-server tests.
"""

import json
import tempfile
import time
from pathlib import Path
from typing import Generator

import pytest


@pytest.fixture
def temp_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for test output."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def sample_eeg_record() -> dict:
    """Sample EEG record."""
    return {
        "ts": time.time(),
        "stream": "eeg",
        "tp9": 850.5,
        "af7": 820.3,
        "af8": 815.7,
        "tp10": 845.2
    }


@pytest.fixture
def sample_acc_record() -> dict:
    """Sample accelerometer record."""
    return {
        "ts": time.time(),
        "stream": "acc",
        "x": 0.12,
        "y": -0.98,
        "z": 0.05
    }


@pytest.fixture
def sample_gyro_record() -> dict:
    """Sample gyroscope record."""
    return {
        "ts": time.time(),
        "stream": "gyro",
        "x": 1.5,
        "y": -2.3,
        "z": 0.8
    }


@pytest.fixture
def sample_jaw_clench_record() -> dict:
    """Sample jaw clench record."""
    return {
        "ts": time.time(),
        "stream": "jaw_clench",
        "detected": True
    }


@pytest.fixture
def sample_jsonl_file(temp_dir: Path) -> Path:
    """Create a sample JSONL file with mixed stream data."""
    base_ts = 1700000000.0
    records = []

    # Add EEG records (256 Hz simulation - 10 samples)
    for i in range(10):
        records.append({
            "ts": base_ts + i * 0.00390625,  # ~256 Hz
            "stream": "eeg",
            "tp9": 850.0 + i,
            "af7": 820.0 + i,
            "af8": 815.0 + i,
            "tp10": 845.0 + i
        })

    # Add ACC records (52 Hz simulation - 2 samples)
    for i in range(2):
        records.append({
            "ts": base_ts + i * 0.019,  # ~52 Hz
            "stream": "acc",
            "x": 0.1 * i,
            "y": -0.98 + 0.01 * i,
            "z": 0.05 * i
        })

    # Add GYRO records (52 Hz simulation - 2 samples)
    for i in range(2):
        records.append({
            "ts": base_ts + i * 0.019,  # ~52 Hz
            "stream": "gyro",
            "x": 1.0 + 0.1 * i,
            "y": -2.0 + 0.1 * i,
            "z": 0.5 + 0.1 * i
        })

    # Add a jaw clench event in the middle
    records.append({
        "ts": base_ts + 0.02,
        "stream": "jaw_clench",
        "detected": True
    })

    # Write to file
    jsonl_path = temp_dir / "osc_raw_20260201_120000.jsonl"
    with open(jsonl_path, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")

    return jsonl_path


@pytest.fixture
def empty_jsonl_file(temp_dir: Path) -> Path:
    """Create an empty JSONL file."""
    jsonl_path = temp_dir / "empty.jsonl"
    jsonl_path.touch()
    return jsonl_path


@pytest.fixture
def eeg_only_jsonl_file(temp_dir: Path) -> Path:
    """Create a JSONL file with only EEG data."""
    base_ts = 1700000000.0
    records = []

    for i in range(5):
        records.append({
            "ts": base_ts + i * 0.00390625,
            "stream": "eeg",
            "tp9": 850.0 + i,
            "af7": 820.0 + i,
            "af8": 815.0 + i,
            "tp10": 845.0 + i
        })

    jsonl_path = temp_dir / "osc_raw_eeg_only.jsonl"
    with open(jsonl_path, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")

    return jsonl_path


@pytest.fixture
def no_eeg_jsonl_file(temp_dir: Path) -> Path:
    """Create a JSONL file with no EEG data (should fail conversion)."""
    base_ts = 1700000000.0
    records = [
        {"ts": base_ts, "stream": "acc", "x": 0.1, "y": -0.98, "z": 0.05},
        {"ts": base_ts + 0.019, "stream": "gyro", "x": 1.0, "y": -2.0, "z": 0.5},
    ]

    jsonl_path = temp_dir / "no_eeg.jsonl"
    with open(jsonl_path, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")

    return jsonl_path
