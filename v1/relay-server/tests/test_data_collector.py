"""
Tests for data_collector.py - Thread-safe OSC data collection to JSONL.
"""

import json
import threading
import time
from pathlib import Path

import pytest

# Add parent directory to path for imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from data_collector import DataCollector


class TestDataCollectorInit:
    """Tests for DataCollector initialization."""

    def test_init_creates_output_directory(self, temp_dir: Path):
        """Directory is created on init."""
        output_dir = temp_dir / "new_output"
        collector = DataCollector(output_dir=str(output_dir))

        assert output_dir.exists()
        assert output_dir.is_dir()

    def test_init_generates_session_id(self, temp_dir: Path):
        """Auto-generates timestamp-based session ID when not provided."""
        collector = DataCollector(output_dir=str(temp_dir))

        assert collector.session_id is not None
        # Session ID should be in YYYYMMDD_HHMMSS format
        assert len(collector.session_id) == 15
        assert "_" in collector.session_id

    def test_init_uses_provided_session_id(self, temp_dir: Path):
        """Uses provided session ID when specified."""
        custom_id = "test_session_123"
        collector = DataCollector(output_dir=str(temp_dir), session_id=custom_id)

        assert collector.session_id == custom_id

    def test_init_sets_output_file_path(self, temp_dir: Path):
        """Output file path is set correctly."""
        session_id = "20260201_120000"
        collector = DataCollector(output_dir=str(temp_dir), session_id=session_id)

        expected_path = temp_dir / f"osc_raw_{session_id}.jsonl"
        assert collector.output_file == expected_path


class TestDataCollectorStart:
    """Tests for starting data collection."""

    def test_start_creates_file(self, temp_dir: Path):
        """Output file is created when start() is called."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test")
        collector.start()

        assert collector.output_file.exists()

        collector.stop()


class TestDataCollectorRecordFormats:
    """Tests for record format correctness."""

    def test_record_eeg_format(self, temp_dir: Path):
        """EEG record has correct fields: ts, stream, tp9, af7, af8, tp10."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        collector.record_eeg(tp9=850.5, af7=820.3, af8=815.7, tp10=845.2)
        collector.stop()

        # Read the written record
        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert "ts" in record
        assert record["stream"] == "eeg"
        assert record["tp9"] == 850.5
        assert record["af7"] == 820.3
        assert record["af8"] == 815.7
        assert record["tp10"] == 845.2

    def test_record_acc_format(self, temp_dir: Path):
        """ACC record has correct fields: ts, stream, x, y, z."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        collector.record_acc(x=0.12, y=-0.98, z=0.05)
        collector.stop()

        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert "ts" in record
        assert record["stream"] == "acc"
        assert record["x"] == 0.12
        assert record["y"] == -0.98
        assert record["z"] == 0.05

    def test_record_gyro_format(self, temp_dir: Path):
        """GYRO record has correct fields: ts, stream, x, y, z."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        collector.record_gyro(x=1.5, y=-2.3, z=0.8)
        collector.stop()

        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert "ts" in record
        assert record["stream"] == "gyro"
        assert record["x"] == 1.5
        assert record["y"] == -2.3
        assert record["z"] == 0.8

    def test_record_jaw_clench_format(self, temp_dir: Path):
        """Jaw clench record has correct fields: ts, stream, detected."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        collector.record_jaw_clench()
        collector.stop()

        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert "ts" in record
        assert record["stream"] == "jaw_clench"
        assert record["detected"] is True


class TestDataCollectorBuffer:
    """Tests for buffer flushing behavior."""

    def test_buffer_flush_at_threshold(self, temp_dir: Path):
        """Buffer flushes when buffer_size is reached."""
        buffer_size = 5
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=buffer_size)
        collector.start()

        # Record exactly buffer_size records
        for i in range(buffer_size):
            collector.record_eeg(tp9=float(i), af7=float(i), af8=float(i), tp10=float(i))

        # File should now have data (flushed)
        with open(collector.output_file, "r") as f:
            lines = f.readlines()

        assert len(lines) == buffer_size

        collector.stop()

    def test_buffer_flush_writes_jsonl(self, temp_dir: Path):
        """Each line in output is valid JSON."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=3)
        collector.start()

        collector.record_eeg(tp9=1.0, af7=2.0, af8=3.0, tp10=4.0)
        collector.record_acc(x=0.1, y=0.2, z=0.3)
        collector.record_gyro(x=1.0, y=2.0, z=3.0)
        collector.stop()

        with open(collector.output_file, "r") as f:
            for line in f:
                # Should not raise
                record = json.loads(line.strip())
                assert isinstance(record, dict)


class TestDataCollectorStop:
    """Tests for stop() behavior."""

    def test_stop_flushes_remaining(self, temp_dir: Path):
        """Remaining buffer is written on stop."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=100)
        collector.start()

        # Add fewer records than buffer_size
        collector.record_eeg(tp9=1.0, af7=2.0, af8=3.0, tp10=4.0)
        collector.record_eeg(tp9=5.0, af7=6.0, af8=7.0, tp10=8.0)

        stats = collector.stop()

        with open(collector.output_file, "r") as f:
            lines = f.readlines()

        assert len(lines) == 2

    def test_stop_returns_stats(self, temp_dir: Path):
        """Stats dict with counts is returned on stop."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test_session")
        collector.start()

        collector.record_eeg(tp9=1.0, af7=2.0, af8=3.0, tp10=4.0)
        collector.record_acc(x=0.1, y=0.2, z=0.3)
        collector.record_gyro(x=1.0, y=2.0, z=3.0)
        collector.record_jaw_clench()

        stats = collector.stop()

        assert stats["session_id"] == "test_session"
        assert "output_file" in stats
        assert stats["total_samples"] == 4
        assert stats["stream_counts"]["eeg"] == 1
        assert stats["stream_counts"]["acc"] == 1
        assert stats["stream_counts"]["gyro"] == 1
        assert stats["stream_counts"]["jaw_clench"] == 1

    def test_empty_stop_no_error(self, temp_dir: Path):
        """Stop without records returns zero stats, no error."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test")
        collector.start()

        stats = collector.stop()

        assert stats["total_samples"] == 0
        assert stats["stream_counts"]["eeg"] == 0
        assert stats["stream_counts"]["acc"] == 0
        assert stats["stream_counts"]["gyro"] == 0
        assert stats["stream_counts"]["jaw_clench"] == 0


class TestDataCollectorThreadSafety:
    """Tests for thread-safe operation."""

    def test_thread_safety_concurrent(self, temp_dir: Path):
        """Multiple threads can record without data loss."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=10)
        collector.start()

        records_per_thread = 50
        num_threads = 4
        expected_total = records_per_thread * num_threads

        def record_data(thread_id: int):
            for i in range(records_per_thread):
                collector.record_eeg(
                    tp9=float(thread_id * 1000 + i),
                    af7=float(thread_id * 1000 + i),
                    af8=float(thread_id * 1000 + i),
                    tp10=float(thread_id * 1000 + i)
                )

        threads = [
            threading.Thread(target=record_data, args=(i,))
            for i in range(num_threads)
        ]

        for t in threads:
            t.start()

        for t in threads:
            t.join()

        stats = collector.stop()

        # All records should be captured
        assert stats["total_samples"] == expected_total
        assert stats["stream_counts"]["eeg"] == expected_total

        # Verify file has all records
        with open(collector.output_file, "r") as f:
            lines = f.readlines()
        assert len(lines) == expected_total


class TestDataCollectorStreamCounts:
    """Tests for per-stream counting."""

    def test_stream_counts_accurate(self, temp_dir: Path):
        """Per-stream counts match actual recorded data."""
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=100)
        collector.start()

        # Record various amounts of each type
        for _ in range(10):
            collector.record_eeg(tp9=1.0, af7=2.0, af8=3.0, tp10=4.0)

        for _ in range(5):
            collector.record_acc(x=0.1, y=0.2, z=0.3)

        for _ in range(3):
            collector.record_gyro(x=1.0, y=2.0, z=3.0)

        for _ in range(2):
            collector.record_jaw_clench()

        # Check counts before stop
        counts = collector.stream_counts
        assert counts["eeg"] == 10
        assert counts["acc"] == 5
        assert counts["gyro"] == 3
        assert counts["jaw_clench"] == 2

        # Verify total
        assert collector.sample_count == 20

        collector.stop()
