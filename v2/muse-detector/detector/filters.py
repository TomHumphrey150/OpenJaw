"""Butterworth filter design for EMG signal processing."""

from scipy.signal import butter
import numpy as np


def design_bandpass_filter(
    low_hz: float,
    high_hz: float,
    sample_rate: float,
    order: int = 4
) -> np.ndarray:
    """
    Design a bandpass Butterworth filter for EMG extraction.

    Args:
        low_hz: Lower cutoff frequency in Hz (e.g., 20 Hz)
        high_hz: Upper cutoff frequency in Hz (e.g., 100 Hz)
        sample_rate: Sample rate in Hz (e.g., 256 Hz for Muse)
        order: Filter order (default: 4)

    Returns:
        Second-order sections (sos) array for use with sosfilt
    """
    nyquist = 0.5 * sample_rate
    low_normalized = low_hz / nyquist
    high_normalized = high_hz / nyquist

    # Clamp to valid range (0, 1) exclusive
    low_normalized = max(0.001, min(low_normalized, 0.999))
    high_normalized = max(low_normalized + 0.001, min(high_normalized, 0.999))

    sos = butter(order, [low_normalized, high_normalized], btype='band', output='sos')
    return sos


def design_lowpass_filter(
    cutoff_hz: float,
    sample_rate: float,
    order: int = 4
) -> np.ndarray:
    """
    Design a lowpass Butterworth filter for envelope extraction.

    Args:
        cutoff_hz: Cutoff frequency in Hz (e.g., 5 Hz for envelope)
        sample_rate: Sample rate in Hz (e.g., 256 Hz for Muse)
        order: Filter order (default: 4)

    Returns:
        Second-order sections (sos) array for use with sosfilt
    """
    nyquist = 0.5 * sample_rate
    normalized_cutoff = cutoff_hz / nyquist

    # Clamp to valid range (0, 1) exclusive
    normalized_cutoff = max(0.001, min(normalized_cutoff, 0.999))

    sos = butter(order, normalized_cutoff, btype='low', output='sos')
    return sos
