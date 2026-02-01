"""Data augmentation for EEG time series."""
import numpy as np
from typing import Tuple


def jitter(window: np.ndarray, sigma: float = 0.05) -> np.ndarray:
    """Add Gaussian noise scaled to signal amplitude."""
    noise = np.random.normal(0, sigma, window.shape)
    return window + noise * np.std(window, axis=0, keepdims=True)


def scale_amplitude(window: np.ndarray, sigma: float = 0.1) -> np.ndarray:
    """Random amplitude scaling per channel."""
    scales = np.random.normal(1.0, sigma, (1, window.shape[1]))
    return window * scales


def time_shift(window: np.ndarray, max_shift: int = 25) -> np.ndarray:
    """Circular shift along time axis (~100ms at 256Hz)."""
    shift = np.random.randint(-max_shift, max_shift + 1)
    return np.roll(window, shift, axis=0)


def augment_window(window: np.ndarray) -> np.ndarray:
    """Apply random augmentation pipeline to a single window."""
    w = window.copy()
    if np.random.random() < 0.8:
        w = jitter(w, sigma=0.05)
    if np.random.random() < 0.8:
        w = scale_amplitude(w, sigma=0.1)
    if np.random.random() < 0.5:
        w = time_shift(w, max_shift=25)
    return w


def augment_dataset(
    windows: np.ndarray,
    labels: np.ndarray,
    multiplier: int = 10
) -> Tuple[np.ndarray, np.ndarray]:
    """Augment dataset by specified multiplier."""
    aug_windows = [windows]  # Include originals
    aug_labels = [labels]

    for _ in range(multiplier - 1):
        batch = np.array([augment_window(w) for w in windows])
        aug_windows.append(batch)
        aug_labels.append(labels)

    return np.concatenate(aug_windows), np.concatenate(aug_labels)
