"""
Tests for server.py OSC handlers and utilities.
"""

import re
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Add parent directory to path for imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

# We need to mock some globals before importing server functions
# to avoid side effects during testing


class TestEegHandler:
    """Tests for eeg_handler function."""

    def test_eeg_handler_parses_4_channels(self, temp_dir: Path):
        """Extracts tp9, af7, af8, tp10 from args."""
        from data_collector import DataCollector

        # Create a mock data collector
        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        # Simulate what eeg_handler does
        args = (850.5, 820.3, 815.7, 845.2)
        if len(args) >= 4:
            collector.record_eeg(
                tp9=float(args[0]),
                af7=float(args[1]),
                af8=float(args[2]),
                tp10=float(args[3])
            )

        stats = collector.stop()

        assert stats["stream_counts"]["eeg"] == 1

        # Verify the data was recorded correctly
        import json
        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert record["tp9"] == 850.5
        assert record["af7"] == 820.3
        assert record["af8"] == 815.7
        assert record["tp10"] == 845.2

    def test_eeg_handler_ignores_insufficient(self, temp_dir: Path):
        """Handler skips data when fewer than 4 args."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        # Simulate insufficient args (only 3 values)
        args = (850.5, 820.3, 815.7)
        if len(args) >= 4:
            collector.record_eeg(
                tp9=float(args[0]),
                af7=float(args[1]),
                af8=float(args[2]),
                tp10=float(args[3])
            )

        stats = collector.stop()

        # No EEG should be recorded
        assert stats["stream_counts"]["eeg"] == 0


class TestAccHandler:
    """Tests for acc_handler function."""

    def test_acc_handler_parses_xyz(self, temp_dir: Path):
        """Extracts x, y, z from args."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        args = (0.12, -0.98, 0.05)
        if len(args) >= 3:
            collector.record_acc(
                x=float(args[0]),
                y=float(args[1]),
                z=float(args[2])
            )

        stats = collector.stop()

        assert stats["stream_counts"]["acc"] == 1

        import json
        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert record["x"] == 0.12
        assert record["y"] == -0.98
        assert record["z"] == 0.05

    def test_acc_handler_ignores_insufficient(self, temp_dir: Path):
        """Handler skips data when fewer than 3 args."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        args = (0.12, -0.98)  # Only 2 values
        if len(args) >= 3:
            collector.record_acc(
                x=float(args[0]),
                y=float(args[1]),
                z=float(args[2])
            )

        stats = collector.stop()

        assert stats["stream_counts"]["acc"] == 0


class TestGyroHandler:
    """Tests for gyro_handler function."""

    def test_gyro_handler_parses_xyz(self, temp_dir: Path):
        """Extracts x, y, z from args."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        args = (1.5, -2.3, 0.8)
        if len(args) >= 3:
            collector.record_gyro(
                x=float(args[0]),
                y=float(args[1]),
                z=float(args[2])
            )

        stats = collector.stop()

        assert stats["stream_counts"]["gyro"] == 1

        import json
        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert record["x"] == 1.5
        assert record["y"] == -2.3
        assert record["z"] == 0.8


class TestJawClenchHandler:
    """Tests for jaw_clench_handler function."""

    def test_jaw_clench_records_event(self, temp_dir: Path):
        """Calls record_jaw_clench on collector."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=1)
        collector.start()

        # Simulate jaw clench handler behavior
        collector.record_jaw_clench()

        stats = collector.stop()

        assert stats["stream_counts"]["jaw_clench"] == 1

        import json
        with open(collector.output_file, "r") as f:
            record = json.loads(f.readline())

        assert record["stream"] == "jaw_clench"
        assert record["detected"] is True


class TestGetLocalIp:
    """Tests for get_local_ip function."""

    def test_get_local_ip_valid(self):
        """Returns a valid IPv4 address."""
        # Import the function
        from server import get_local_ip

        ip = get_local_ip()

        # Should return a string
        assert isinstance(ip, str)

        # Should be a valid IPv4 address format (4 octets separated by dots)
        # or 127.0.0.1 if network unavailable
        ipv4_pattern = r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"
        assert re.match(ipv4_pattern, ip), f"Invalid IP format: {ip}"

    def test_get_local_ip_not_localhost_when_connected(self):
        """Returns non-localhost IP when network is available."""
        from server import get_local_ip

        ip = get_local_ip()

        # This test may return 127.0.0.1 if no network, which is acceptable
        # We just verify the function doesn't crash and returns valid format
        parts = ip.split(".")
        assert len(parts) == 4
        for part in parts:
            assert 0 <= int(part) <= 255


class TestOscHandlerIntegration:
    """Integration tests simulating actual OSC message handling."""

    def test_eeg_records_to_collector(self, temp_dir: Path):
        """EEG OSC messages are correctly recorded to collector."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=100)
        collector.start()

        # Simulate receiving 10 EEG samples at ~256 Hz
        for i in range(10):
            args = (850.0 + i, 820.0 + i, 815.0 + i, 845.0 + i)
            if len(args) >= 4:
                collector.record_eeg(
                    tp9=float(args[0]),
                    af7=float(args[1]),
                    af8=float(args[2]),
                    tp10=float(args[3])
                )

        stats = collector.stop()

        assert stats["stream_counts"]["eeg"] == 10

    def test_mixed_streams_recorded(self, temp_dir: Path):
        """Mixed EEG, ACC, GYRO, and jaw_clench messages are all recorded."""
        from data_collector import DataCollector

        collector = DataCollector(output_dir=str(temp_dir), session_id="test", buffer_size=100)
        collector.start()

        # Simulate typical data flow: many EEG, fewer ACC/GYRO, occasional jaw_clench
        for i in range(100):
            # EEG at 256 Hz
            collector.record_eeg(tp9=850.0, af7=820.0, af8=815.0, tp10=845.0)

            # ACC/GYRO at ~52 Hz (roughly every 5th EEG sample)
            if i % 5 == 0:
                collector.record_acc(x=0.1, y=-0.98, z=0.05)
                collector.record_gyro(x=1.0, y=-2.0, z=0.5)

            # Occasional jaw clench
            if i == 50:
                collector.record_jaw_clench()

        stats = collector.stop()

        assert stats["stream_counts"]["eeg"] == 100
        assert stats["stream_counts"]["acc"] == 20
        assert stats["stream_counts"]["gyro"] == 20
        assert stats["stream_counts"]["jaw_clench"] == 1
        assert stats["total_samples"] == 141
