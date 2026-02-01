"""Tests for ml/preprocess.py - windowing and normalization."""

import numpy as np
import pytest
import tempfile
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from ml.preprocess import (
    WindowConfig,
    normalize_data,
    create_windows,
    CHANNEL_NAMES,
    EEG_ACCGYRO_CHANNELS,
)


class TestNormalizeData:
    """Tests for z-score normalization."""

    def test_normalize_basic(self):
        """Test basic normalization with known values."""
        data = np.array([
            [0, 10],
            [2, 20],
            [4, 30],
            [6, 40],
            [8, 50],
        ], dtype=np.float32)

        normalized, means, stds = normalize_data(data)

        # Check means are close to 0
        assert np.allclose(normalized.mean(axis=0), 0, atol=1e-6)

        # Check stds are close to 1
        assert np.allclose(normalized.std(axis=0), 1, atol=0.1)

    def test_normalize_with_precomputed_stats(self):
        """Test normalization with pre-computed statistics."""
        data = np.array([[10, 20], [20, 40]], dtype=np.float32)
        means = np.array([15, 30])
        stds = np.array([5, 10])

        normalized, _, _ = normalize_data(data, means, stds)

        expected = np.array([[-1, -1], [1, 1]], dtype=np.float32)
        assert np.allclose(normalized, expected)

    def test_normalize_handles_nan(self):
        """Test that NaN values are replaced with 0."""
        data = np.array([[1, np.nan], [np.nan, 2]], dtype=np.float32)

        normalized, _, _ = normalize_data(data)

        # Should not contain NaN
        assert not np.any(np.isnan(normalized))

    def test_normalize_zero_std(self):
        """Test handling of zero standard deviation (constant channel)."""
        data = np.array([[5, 5], [5, 5], [5, 5]], dtype=np.float32)

        normalized, means, stds = normalize_data(data)

        # Should not have inf or nan
        assert not np.any(np.isnan(normalized))
        assert not np.any(np.isinf(normalized))


class TestCreateWindows:
    """Tests for window creation."""

    def test_basic_windowing(self):
        """Test basic window creation."""
        n_samples = 512
        n_channels = 30
        data = np.random.randn(n_samples, n_channels).astype(np.float32)
        labels = np.zeros(n_samples, dtype=np.int32)

        config = WindowConfig(window_size_samples=256, stride_samples=128)
        windows, window_labels, indices = create_windows(data, labels, config)

        # Should have 3 windows: [0-256], [128-384], [256-512]
        assert len(windows) == 3
        assert windows.shape == (3, 256, 30)
        assert len(window_labels) == 3
        assert len(indices) == 3

    def test_window_indices(self):
        """Test that window indices are correct."""
        data = np.arange(512).reshape(-1, 1).astype(np.float32)
        labels = np.zeros(512, dtype=np.int32)

        config = WindowConfig(window_size_samples=100, stride_samples=50)
        windows, _, indices = create_windows(data, labels, config)

        # First window should start at 0
        assert indices[0] == 0
        # Second window should start at 50
        assert indices[1] == 50

        # Verify window content matches indices
        for i, idx in enumerate(indices):
            expected = data[idx:idx + 100]
            assert np.allclose(windows[i], expected)

    def test_label_majority_vote(self):
        """Test that window labels use majority vote."""
        data = np.random.randn(256, 30).astype(np.float32)

        # First half relaxed, second half clenching
        labels = np.zeros(256, dtype=np.int32)
        labels[128:] = 1

        config = WindowConfig(
            window_size_samples=256,
            stride_samples=256,
            min_positive_ratio=0.5
        )
        windows, window_labels, _ = create_windows(data, labels, config)

        # With 50% positive and threshold at 0.5, should be positive
        assert window_labels[0] == 1

    def test_label_below_threshold(self):
        """Test label when below positive ratio threshold."""
        data = np.random.randn(256, 30).astype(np.float32)

        # 40% positive
        labels = np.zeros(256, dtype=np.int32)
        labels[:102] = 1  # 102/256 = 39.8%

        config = WindowConfig(
            window_size_samples=256,
            stride_samples=256,
            min_positive_ratio=0.5
        )
        windows, window_labels, _ = create_windows(data, labels, config)

        # Below threshold, should be negative
        assert window_labels[0] == 0

    def test_insufficient_data(self):
        """Test handling when not enough data for a window."""
        data = np.random.randn(100, 30).astype(np.float32)
        labels = np.zeros(100, dtype=np.int32)

        config = WindowConfig(window_size_samples=256, stride_samples=128)
        windows, window_labels, indices = create_windows(data, labels, config)

        # Should return empty arrays
        assert len(windows) == 0
        assert len(window_labels) == 0
        assert len(indices) == 0


class TestChannelOrder:
    """Tests for channel ordering."""

    def test_channel_names_order(self):
        """Verify channel names are in expected order (8 EEG + 6 ACCGYRO + 16 OPTICS)."""
        expected = [
            # 8 EEG channels
            "eeg_tp9", "eeg_af7", "eeg_af8", "eeg_tp10",
            "eeg_aux1", "eeg_aux2", "eeg_aux3", "eeg_aux4",
            # 6 ACCGYRO channels
            "acc_x", "acc_y", "acc_z",
            "gyro_x", "gyro_y", "gyro_z",
            # 16 OPTICS channels
            "optics_lo_nir", "optics_ro_nir", "optics_lo_ir", "optics_ro_ir",
            "optics_li_nir", "optics_ri_nir", "optics_li_ir", "optics_ri_ir",
            "optics_lo_red", "optics_ro_red", "optics_lo_amb", "optics_ro_amb",
            "optics_li_red", "optics_ri_red", "optics_li_amb", "optics_ri_amb",
        ]
        assert CHANNEL_NAMES == expected

    def test_channel_count(self):
        """Verify we have 30 channels total (8 EEG + 6 ACCGYRO + 16 OPTICS)."""
        assert len(CHANNEL_NAMES) == 30

    def test_eeg_accgyro_channels_order(self):
        """Verify EEG_ACCGYRO_CHANNELS is in expected order (8 EEG + 6 ACCGYRO, no OPTICS)."""
        expected = [
            # 8 EEG channels
            "eeg_tp9", "eeg_af7", "eeg_af8", "eeg_tp10",
            "eeg_aux1", "eeg_aux2", "eeg_aux3", "eeg_aux4",
            # 6 ACCGYRO channels
            "acc_x", "acc_y", "acc_z",
            "gyro_x", "gyro_y", "gyro_z",
        ]
        assert EEG_ACCGYRO_CHANNELS == expected

    def test_eeg_accgyro_channels_count(self):
        """Verify we have 14 channels in EEG_ACCGYRO_CHANNELS (no OPTICS)."""
        assert len(EEG_ACCGYRO_CHANNELS) == 14


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
