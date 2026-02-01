"""Tests for data augmentation functions."""
import numpy as np
import pytest

from ml.augment import (
    jitter,
    scale_amplitude,
    time_shift,
    augment_window,
    augment_dataset,
)


class TestJitter:
    """Tests for jitter augmentation."""

    def test_jitter_shape_preserved(self):
        """Jitter should not change array shape."""
        window = np.random.randn(256, 30)
        result = jitter(window, sigma=0.05)
        assert result.shape == window.shape

    def test_jitter_adds_noise(self):
        """Jitter should modify the data."""
        np.random.seed(42)
        window = np.random.randn(256, 30)
        result = jitter(window, sigma=0.05)
        assert not np.allclose(result, window)

    def test_jitter_zero_sigma_no_change(self):
        """Sigma=0 should result in no change."""
        window = np.random.randn(256, 30)
        result = jitter(window, sigma=0.0)
        np.testing.assert_array_almost_equal(result, window)


class TestScaleAmplitude:
    """Tests for amplitude scaling augmentation."""

    def test_scale_shape_preserved(self):
        """Scale should not change array shape."""
        window = np.random.randn(256, 30)
        result = scale_amplitude(window, sigma=0.1)
        assert result.shape == window.shape

    def test_scale_modifies_data(self):
        """Scale should modify the data."""
        np.random.seed(42)
        window = np.random.randn(256, 30)
        result = scale_amplitude(window, sigma=0.1)
        assert not np.allclose(result, window)

    def test_scale_zero_sigma_no_change(self):
        """Sigma=0 should result in no change (scale=1.0 for all)."""
        np.random.seed(42)
        window = np.random.randn(256, 30)
        result = scale_amplitude(window, sigma=0.0)
        np.testing.assert_array_almost_equal(result, window)


class TestTimeShift:
    """Tests for time shift augmentation."""

    def test_shift_shape_preserved(self):
        """Time shift should not change array shape."""
        window = np.random.randn(256, 30)
        result = time_shift(window, max_shift=25)
        assert result.shape == window.shape

    def test_shift_circular(self):
        """Time shift should be circular (no data loss)."""
        window = np.arange(256).reshape(-1, 1).repeat(30, axis=1).astype(float)
        result = time_shift(window, max_shift=25)
        # All values should still be present
        assert set(result[:, 0].astype(int)) == set(range(256))

    def test_shift_zero_no_change(self):
        """Max shift=0 should result in no change."""
        window = np.random.randn(256, 30)
        result = time_shift(window, max_shift=0)
        np.testing.assert_array_equal(result, window)


class TestAugmentWindow:
    """Tests for the combined augmentation pipeline."""

    def test_augment_window_shape_preserved(self):
        """Augmented window should have same shape."""
        window = np.random.randn(256, 30)
        result = augment_window(window)
        assert result.shape == window.shape

    def test_augment_window_does_not_modify_original(self):
        """Original window should not be modified."""
        window = np.random.randn(256, 30)
        original = window.copy()
        augment_window(window)
        np.testing.assert_array_equal(window, original)


class TestAugmentDataset:
    """Tests for dataset augmentation."""

    def test_augment_dataset_multiplies_count(self):
        """Dataset should be multiplied by the specified factor."""
        windows = np.random.randn(100, 256, 30)
        labels = np.random.randint(0, 2, 100)

        aug_windows, aug_labels = augment_dataset(windows, labels, multiplier=10)

        assert len(aug_windows) == 1000
        assert len(aug_labels) == 1000

    def test_augment_dataset_includes_originals(self):
        """Augmented dataset should include original samples."""
        np.random.seed(42)
        windows = np.random.randn(10, 256, 30)
        labels = np.array([0, 1, 0, 1, 0, 1, 0, 1, 0, 1])

        aug_windows, aug_labels = augment_dataset(windows, labels, multiplier=5)

        # First batch should be originals
        np.testing.assert_array_equal(aug_windows[:10], windows)
        np.testing.assert_array_equal(aug_labels[:10], labels)

    def test_augment_dataset_preserves_label_ratio(self):
        """Label ratio should be preserved after augmentation."""
        windows = np.random.randn(100, 256, 30)
        labels = np.array([1] * 30 + [0] * 70)  # 30% positive

        aug_windows, aug_labels = augment_dataset(windows, labels, multiplier=10)

        original_ratio = labels.mean()
        augmented_ratio = aug_labels.mean()

        np.testing.assert_almost_equal(original_ratio, augmented_ratio)

    def test_augment_dataset_multiplier_one_returns_original(self):
        """Multiplier=1 should return just the original data."""
        windows = np.random.randn(50, 256, 30)
        labels = np.random.randint(0, 2, 50)

        aug_windows, aug_labels = augment_dataset(windows, labels, multiplier=1)

        np.testing.assert_array_equal(aug_windows, windows)
        np.testing.assert_array_equal(aug_labels, labels)

    def test_augmented_data_is_different(self):
        """Augmented copies should be different from originals."""
        np.random.seed(42)
        windows = np.random.randn(10, 256, 30)
        labels = np.random.randint(0, 2, 10)

        aug_windows, aug_labels = augment_dataset(windows, labels, multiplier=3)

        # Second batch (indices 10-19) should be different from first (0-9)
        assert not np.allclose(aug_windows[:10], aug_windows[10:20])
