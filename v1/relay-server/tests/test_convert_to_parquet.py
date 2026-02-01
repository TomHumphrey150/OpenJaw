"""
Tests for convert_to_parquet.py - JSONL to Parquet conversion.
"""

import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

# Add parent directory to path for imports
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from convert_to_parquet import (
    load_jsonl,
    separate_streams,
    interpolate_to_timestamps,
    generate_labels,
    convert_file,
)


class TestLoadJsonl:
    """Tests for load_jsonl function."""

    def test_load_jsonl_reads_all(self, sample_jsonl_file: Path):
        """All lines are loaded from JSONL file."""
        records = load_jsonl(sample_jsonl_file)

        # Should have 10 EEG + 2 ACC + 2 GYRO + 1 jaw_clench = 15 records
        assert len(records) == 15

    def test_load_jsonl_empty_file(self, empty_jsonl_file: Path):
        """Empty file returns empty list."""
        records = load_jsonl(empty_jsonl_file)

        assert records == []

    def test_load_jsonl_preserves_data(self, temp_dir: Path):
        """Loaded records preserve original data."""
        expected = {"ts": 1700000000.0, "stream": "test", "value": 123.456}

        jsonl_path = temp_dir / "test.jsonl"
        with open(jsonl_path, "w") as f:
            f.write(json.dumps(expected) + "\n")

        records = load_jsonl(jsonl_path)

        assert len(records) == 1
        assert records[0] == expected


class TestSeparateStreams:
    """Tests for separate_streams function."""

    def test_separate_streams_eeg(self, sample_jsonl_file: Path):
        """EEG records are correctly separated."""
        records = load_jsonl(sample_jsonl_file)
        streams = separate_streams(records)

        assert "eeg" in streams
        assert len(streams["eeg"]) == 10
        assert all(col in streams["eeg"].columns for col in ["ts", "stream", "tp9", "af7", "af8", "tp10"])

    def test_separate_streams_acc(self, sample_jsonl_file: Path):
        """ACC records are correctly separated."""
        records = load_jsonl(sample_jsonl_file)
        streams = separate_streams(records)

        assert "acc" in streams
        assert len(streams["acc"]) == 2
        assert all(col in streams["acc"].columns for col in ["ts", "stream", "x", "y", "z"])

    def test_separate_streams_gyro(self, sample_jsonl_file: Path):
        """GYRO records are correctly separated."""
        records = load_jsonl(sample_jsonl_file)
        streams = separate_streams(records)

        assert "gyro" in streams
        assert len(streams["gyro"]) == 2
        assert all(col in streams["gyro"].columns for col in ["ts", "stream", "x", "y", "z"])

    def test_separate_streams_jaw_clench(self, sample_jsonl_file: Path):
        """Jaw clench records are correctly separated."""
        records = load_jsonl(sample_jsonl_file)
        streams = separate_streams(records)

        assert "jaw_clench" in streams
        assert len(streams["jaw_clench"]) == 1
        assert "detected" in streams["jaw_clench"].columns

    def test_separate_streams_sorted(self, temp_dir: Path):
        """Records are sorted by timestamp."""
        # Create records out of order
        records = [
            {"ts": 1700000002.0, "stream": "eeg", "tp9": 3, "af7": 3, "af8": 3, "tp10": 3},
            {"ts": 1700000000.0, "stream": "eeg", "tp9": 1, "af7": 1, "af8": 1, "tp10": 1},
            {"ts": 1700000001.0, "stream": "eeg", "tp9": 2, "af7": 2, "af8": 2, "tp10": 2},
        ]

        streams = separate_streams(records)

        # Should be sorted by timestamp
        assert streams["eeg"]["ts"].tolist() == [1700000000.0, 1700000001.0, 1700000002.0]
        assert streams["eeg"]["tp9"].tolist() == [1, 2, 3]


class TestInterpolation:
    """Tests for interpolate_to_timestamps function."""

    def test_interpolate_basic(self):
        """Linear interpolation works correctly."""
        source_df = pd.DataFrame({
            "ts": [0.0, 1.0, 2.0],
            "x": [0.0, 10.0, 20.0],
            "y": [100.0, 100.0, 100.0]
        })
        target_ts = np.array([0.0, 0.5, 1.0, 1.5, 2.0])

        result = interpolate_to_timestamps(source_df, target_ts, ["x", "y"])

        assert len(result) == 5
        np.testing.assert_array_almost_equal(result["x"].values, [0.0, 5.0, 10.0, 15.0, 20.0])
        np.testing.assert_array_almost_equal(result["y"].values, [100.0, 100.0, 100.0, 100.0, 100.0])

    def test_interpolate_nan_outside(self):
        """NaN is returned for timestamps outside source range."""
        source_df = pd.DataFrame({
            "ts": [1.0, 2.0],
            "x": [10.0, 20.0]
        })
        target_ts = np.array([0.5, 1.0, 2.0, 2.5])

        result = interpolate_to_timestamps(source_df, target_ts, ["x"])

        assert np.isnan(result["x"].values[0])  # Before range
        assert result["x"].values[1] == 10.0    # At start
        assert result["x"].values[2] == 20.0    # At end
        assert np.isnan(result["x"].values[3])  # After range

    def test_interpolate_empty_source(self):
        """Empty source returns NaN-filled DataFrame."""
        source_df = pd.DataFrame(columns=["ts", "x", "y"])
        target_ts = np.array([0.0, 1.0, 2.0])

        result = interpolate_to_timestamps(source_df, target_ts, ["x", "y"])

        assert len(result) == 3
        assert all(np.isnan(result["x"].values))
        assert all(np.isnan(result["y"].values))

    def test_interpolate_none_source(self):
        """None source returns NaN-filled DataFrame."""
        target_ts = np.array([0.0, 1.0, 2.0])

        result = interpolate_to_timestamps(None, target_ts, ["x", "y"])

        assert len(result) == 3
        assert all(np.isnan(result["x"].values))
        assert all(np.isnan(result["y"].values))


class TestGenerateLabels:
    """Tests for generate_labels function."""

    def test_generate_labels_no_events(self):
        """All zeros when no jaw_clench events."""
        eeg_ts = np.array([0.0, 0.1, 0.2, 0.3, 0.4])
        jaw_clench_df = None

        labels = generate_labels(eeg_ts, jaw_clench_df)

        np.testing.assert_array_equal(labels, [0, 0, 0, 0, 0])

    def test_generate_labels_empty_df(self):
        """All zeros when jaw_clench DataFrame is empty."""
        eeg_ts = np.array([0.0, 0.1, 0.2, 0.3, 0.4])
        jaw_clench_df = pd.DataFrame(columns=["ts", "detected"])

        labels = generate_labels(eeg_ts, jaw_clench_df)

        np.testing.assert_array_equal(labels, [0, 0, 0, 0, 0])

    def test_generate_labels_single_event(self):
        """Window after event is labeled 1."""
        # EEG at 100ms intervals
        eeg_ts = np.array([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7])

        # Jaw clench at 0.2s with 0.3s window
        jaw_clench_df = pd.DataFrame({"ts": [0.2], "detected": [True]})

        labels = generate_labels(eeg_ts, jaw_clench_df, label_window_seconds=0.3)

        # Labels should be 1 for samples from 0.2 to 0.5 (exclusive)
        # 0.2, 0.3, 0.4 should be labeled (0.5 is >= 0.2 + 0.3)
        expected = [0, 0, 1, 1, 1, 0, 0, 0]
        np.testing.assert_array_equal(labels, expected)

    def test_generate_labels_window_size(self):
        """Custom window size is respected."""
        eeg_ts = np.array([0.0, 0.1, 0.2, 0.3, 0.4])

        jaw_clench_df = pd.DataFrame({"ts": [0.1], "detected": [True]})

        # Small window: only 0.1s (labels 0.1 only, since 0.2 >= 0.1 + 0.1)
        labels_small = generate_labels(eeg_ts, jaw_clench_df, label_window_seconds=0.1)
        assert labels_small.sum() == 1  # Only the exact timestamp

        # Larger window: 0.25s (labels 0.1, 0.2, 0.3 since they are >= 0.1 and < 0.35)
        labels_large = generate_labels(eeg_ts, jaw_clench_df, label_window_seconds=0.25)
        assert labels_large.sum() == 3  # 0.1, 0.2, 0.3

    def test_generate_labels_multiple_events(self):
        """Multiple events each create their own window."""
        eeg_ts = np.array([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9])

        jaw_clench_df = pd.DataFrame({
            "ts": [0.1, 0.6],
            "detected": [True, True]
        })

        labels = generate_labels(eeg_ts, jaw_clench_df, label_window_seconds=0.15)

        # First event at 0.1: labels 0.1, 0.2 (indices 1, 2) since 0.1 <= ts < 0.25
        # Second event at 0.6: labels 0.6, 0.7 (indices 6, 7) since 0.6 <= ts < 0.75
        expected = [0, 1, 1, 0, 0, 0, 1, 1, 0, 0]
        np.testing.assert_array_equal(labels, expected)


class TestConvertFile:
    """Tests for convert_file function."""

    def test_convert_file_output_schema(self, sample_jsonl_file: Path, temp_dir: Path):
        """All expected columns are present in output."""
        output_dir = temp_dir / "output"

        result = convert_file(sample_jsonl_file, output_dir)

        assert "error" not in result

        # Read the parquet file
        output_path = Path(result["output_file"])
        df = pd.read_parquet(output_path)

        expected_columns = [
            "timestamp",
            "eeg_tp9", "eeg_af7", "eeg_af8", "eeg_tp10",
            "acc_x", "acc_y", "acc_z",
            "gyro_x", "gyro_y", "gyro_z",
            "label",
            "session_id"
        ]

        for col in expected_columns:
            assert col in df.columns, f"Missing column: {col}"

    def test_convert_file_session_id(self, sample_jsonl_file: Path, temp_dir: Path):
        """Session ID is extracted from filename."""
        output_dir = temp_dir / "output"

        result = convert_file(sample_jsonl_file, output_dir)

        # Filename is osc_raw_20260201_120000.jsonl
        assert result["session_id"] == "20260201_120000"

        # Read parquet and verify session_id column
        df = pd.read_parquet(result["output_file"])
        assert all(df["session_id"] == "20260201_120000")

    def test_convert_file_custom_session_id(self, sample_jsonl_file: Path, temp_dir: Path):
        """Custom session ID overrides filename extraction."""
        output_dir = temp_dir / "output"

        result = convert_file(sample_jsonl_file, output_dir, session_id="custom_session")

        assert result["session_id"] == "custom_session"

        df = pd.read_parquet(result["output_file"])
        assert all(df["session_id"] == "custom_session")

    def test_convert_file_no_eeg_error(self, no_eeg_jsonl_file: Path, temp_dir: Path):
        """Returns error dict when no EEG data."""
        output_dir = temp_dir / "output"

        result = convert_file(no_eeg_jsonl_file, output_dir)

        assert "error" in result
        assert "No EEG data" in result["error"]

    def test_convert_file_empty_error(self, empty_jsonl_file: Path, temp_dir: Path):
        """Returns error dict for empty file."""
        output_dir = temp_dir / "output"

        result = convert_file(empty_jsonl_file, output_dir)

        assert "error" in result

    def test_convert_file_stats(self, sample_jsonl_file: Path, temp_dir: Path):
        """Conversion returns accurate statistics."""
        output_dir = temp_dir / "output"

        result = convert_file(sample_jsonl_file, output_dir, label_window_seconds=0.5)

        assert result["eeg_samples"] == 10
        assert result["acc_samples"] == 2
        assert result["gyro_samples"] == 2
        assert result["jaw_clench_events"] == 1
        assert result["total_samples"] == 10  # Same as EEG (base timeline)
        assert result["label_window_seconds"] == 0.5
        assert "duration_seconds" in result

    def test_convert_file_eeg_only(self, eeg_only_jsonl_file: Path, temp_dir: Path):
        """Conversion works with EEG-only data (ACC/GYRO will be NaN)."""
        output_dir = temp_dir / "output"

        result = convert_file(eeg_only_jsonl_file, output_dir)

        assert "error" not in result
        assert result["acc_samples"] == 0
        assert result["gyro_samples"] == 0
        assert result["jaw_clench_events"] == 0
        assert result["positive_labels"] == 0

        # Verify parquet has NaN for ACC/GYRO
        df = pd.read_parquet(result["output_file"])
        assert df["acc_x"].isna().all()
        assert df["gyro_x"].isna().all()
        assert (df["label"] == 0).all()
