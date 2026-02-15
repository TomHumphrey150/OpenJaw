"""
Real-time inference engine for ML-based jaw clench detection.

Provides streaming inference with:
- Sliding window buffer for continuous data
- Normalization using trained model's statistics
- Debounce logic to prevent rapid-fire detections
"""

import json
import logging
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import torch

from .model import create_model
from .preprocess import CHANNEL_NAMES, EEG_CHANNELS, EEG_ACCGYRO_CHANNELS, TP_CHANNELS

logger = logging.getLogger("ml.inference")


@dataclass
class InferenceResult:
    """Result from a single inference step."""
    probability: float  # Probability of jaw clench (0-1)
    is_clenching: bool  # Whether we're above threshold
    is_detection: bool  # Whether this is a new detection (respects debounce)
    window_ready: bool  # Whether we had a full window to process


class TimestampedBuffer:
    """
    Buffer that stores samples with their timestamps.

    Used to accumulate streaming data while preserving timing information
    for proper interpolation across different sample rates.
    """

    def __init__(self, max_samples: int, n_channels: int):
        """
        Initialize the buffer.

        Args:
            max_samples: Maximum samples to keep (older samples are discarded)
            n_channels: Number of channels in the data
        """
        self.max_samples = max_samples
        self.n_channels = n_channels
        self._data = np.zeros((max_samples, n_channels), dtype=np.float32)
        self._timestamps = np.zeros(max_samples, dtype=np.float64)
        self._write_pos = 0
        self._total_samples = 0

    def add_samples(self, data: np.ndarray, timestamps: np.ndarray) -> None:
        """Add samples with their timestamps."""
        if data is None or len(data) == 0:
            return

        n_new = len(data)

        # If more samples than buffer, only keep the last max_samples
        if n_new >= self.max_samples:
            self._data[:] = data[-self.max_samples:]
            self._timestamps[:] = timestamps[-self.max_samples:]
            self._write_pos = self.max_samples
            self._total_samples += n_new
            return

        # Check if we need to shift the buffer
        if self._write_pos + n_new > self.max_samples:
            # Shift: keep the most recent samples
            keep_count = self.max_samples - n_new
            if self._write_pos > keep_count:
                self._data[:keep_count] = self._data[self._write_pos - keep_count:self._write_pos]
                self._timestamps[:keep_count] = self._timestamps[self._write_pos - keep_count:self._write_pos]
                self._write_pos = keep_count

        # Add new samples
        end_pos = self._write_pos + n_new
        self._data[self._write_pos:end_pos] = data
        self._timestamps[self._write_pos:end_pos] = timestamps
        self._write_pos = end_pos
        self._total_samples += n_new

    def get_data_in_range(self, start_ts: float, end_ts: float) -> Tuple[np.ndarray, np.ndarray]:
        """Get all data within a timestamp range."""
        if self._write_pos == 0:
            return np.array([]), np.array([])

        valid_ts = self._timestamps[:self._write_pos]
        valid_data = self._data[:self._write_pos]

        # Find samples in range (with some margin for interpolation)
        margin = (end_ts - start_ts) * 0.1  # 10% margin
        mask = (valid_ts >= start_ts - margin) & (valid_ts <= end_ts + margin)

        return valid_data[mask], valid_ts[mask]

    def get_all_data(self) -> Tuple[np.ndarray, np.ndarray]:
        """Get all buffered data and timestamps."""
        return self._data[:self._write_pos].copy(), self._timestamps[:self._write_pos].copy()

    @property
    def samples_collected(self) -> int:
        """Number of samples currently in buffer."""
        return self._write_pos

    @property
    def total_samples_received(self) -> int:
        """Total samples received (including discarded)."""
        return self._total_samples

    def reset(self) -> None:
        """Clear the buffer."""
        self._data.fill(0)
        self._timestamps.fill(0)
        self._write_pos = 0
        self._total_samples = 0


class SlidingWindowBuffer:
    """
    Buffer for accumulating samples until we have a full window.

    Handles the mismatch between streaming chunk sizes and
    the fixed window size needed for inference.
    """

    def __init__(self, window_size: int = 256, n_channels: int = 30):
        """
        Initialize the buffer.

        Args:
            window_size: Number of samples per inference window
            n_channels: Number of input channels
        """
        self.window_size = window_size
        self.n_channels = n_channels
        self._buffer = np.zeros((window_size * 2, n_channels), dtype=np.float32)
        self._write_pos = 0

    def add_samples(self, samples: np.ndarray) -> None:
        """
        Add new samples to the buffer.

        Args:
            samples: Shape (n_samples, n_channels)
        """
        n_new = len(samples)

        # If chunk is larger than buffer, only keep the last buffer-sized portion
        if n_new >= len(self._buffer):
            self._buffer[:] = samples[-len(self._buffer):]
            self._write_pos = len(self._buffer)
            return

        # Handle buffer wraparound
        if self._write_pos + n_new >= len(self._buffer):
            # Shift buffer: keep last window_size samples
            keep_start = self._write_pos - self.window_size
            if keep_start > 0:
                self._buffer[:self.window_size] = self._buffer[keep_start:self._write_pos]
                self._write_pos = self.window_size

        # Check again after shift - if still doesn't fit, we need more aggressive shift
        if self._write_pos + n_new >= len(self._buffer):
            # Keep only enough to fit new samples
            keep_count = len(self._buffer) - n_new
            if keep_count > 0 and self._write_pos > 0:
                self._buffer[:keep_count] = self._buffer[self._write_pos - keep_count:self._write_pos]
                self._write_pos = keep_count
            else:
                self._write_pos = 0

        # Add new samples
        end_pos = self._write_pos + n_new
        self._buffer[self._write_pos:end_pos] = samples
        self._write_pos = end_pos

    def get_window(self) -> Optional[np.ndarray]:
        """
        Get the most recent window of samples.

        Returns:
            Window of shape (window_size, n_channels) or None if not enough data
        """
        if self._write_pos < self.window_size:
            return None

        start = self._write_pos - self.window_size
        return self._buffer[start:self._write_pos].copy()

    @property
    def samples_collected(self) -> int:
        """Number of samples currently in buffer."""
        return self._write_pos

    @property
    def is_ready(self) -> bool:
        """Whether we have enough samples for a full window."""
        return self._write_pos >= self.window_size

    def reset(self) -> None:
        """Clear the buffer."""
        self._buffer.fill(0)
        self._write_pos = 0


class MLInferenceEngine:
    """
    Real-time ML inference engine for jaw clench detection.

    Replaces threshold-based detection with neural network inference.

    Uses separate timestamped buffers for each stream (EEG, ACCGYRO, OPTICS)
    to properly handle different sample rates and ensure correct interpolation.

    Usage:
        engine = MLInferenceEngine("data/models/model.pt")

        # Stream EEG + accelerometer data
        for eeg_chunk, accgyro_chunk in data_stream:
            result = engine.process(eeg_chunk, accgyro_chunk)
            if result.is_detection:
                print("Jaw clench detected!")
    """

    def __init__(
        self,
        model_path: str,
        detection_threshold: float = 0.5,
        debounce_seconds: float = 2.0,
        device: Optional[str] = None
    ):
        """
        Initialize the inference engine.

        Args:
            model_path: Path to trained model checkpoint (.pt file)
            detection_threshold: Probability threshold for detection
            debounce_seconds: Minimum time between detections
            device: PyTorch device ("cpu", "cuda", "mps", or None for auto)
        """
        self.model_path = Path(model_path)
        self.detection_threshold = detection_threshold
        self.debounce_seconds = debounce_seconds

        # Auto-detect device
        if device is None:
            if torch.cuda.is_available():
                self.device = torch.device("cuda")
            elif torch.backends.mps.is_available():
                self.device = torch.device("mps")
            else:
                self.device = torch.device("cpu")
        else:
            self.device = torch.device(device)

        # Load model and config
        self._load_model()

        # Create separate timestamped buffers for each stream
        # Keep enough samples for ~2 windows worth of data
        # Note: OPTICS channels are excluded due to tiny variance during training
        # causing extreme normalized values during live inference
        buffer_samples = self.window_size * 4
        self._eeg_buffer = TimestampedBuffer(buffer_samples, n_channels=8)
        self._accgyro_buffer = TimestampedBuffer(buffer_samples // 4, n_channels=6)  # ~52 Hz vs 256 Hz

        # Debounce state
        self._last_detection_time: Optional[float] = None
        self._debug_counter = 0

        logger.info(f"MLInferenceEngine initialized on {self.device}")
        logger.info(f"  Model: {self.model_path.name}")
        logger.info(f"  Threshold: {self.detection_threshold}")
        logger.info(f"  Debounce: {self.debounce_seconds}s")

    def _load_model(self) -> None:
        """Load model from checkpoint."""
        if not self.model_path.exists():
            raise FileNotFoundError(f"Model not found: {self.model_path}")

        logger.info(f"Loading model from: {self.model_path}")

        checkpoint = torch.load(self.model_path, map_location=self.device, weights_only=False)

        # Extract config
        config = checkpoint.get("config", {})
        self.window_size = config.get("window_size", 256)
        self.n_channels = config.get("n_channels", 10)
        model_type = config.get("model_type", "cnn")

        # Load channel names from checkpoint (defaults to all channels for backwards compat)
        self.channel_names = checkpoint.get("channel_names", CHANNEL_NAMES)

        # Detect channel mode
        self.tp_only = len(self.channel_names) == len(TP_CHANNELS) and all(
            ch in TP_CHANNELS for ch in self.channel_names
        )
        self.eeg_only = not self.tp_only and len(self.channel_names) == len(EEG_CHANNELS) and all(
            ch in EEG_CHANNELS for ch in self.channel_names
        )

        # Normalization parameters
        self.channel_means = np.array(checkpoint.get("channel_means", [0] * 10))
        self.channel_stds = np.array(checkpoint.get("channel_stds", [1] * 10))

        # Create and load model
        self.model = create_model(
            model_type=model_type,
            n_channels=self.n_channels,
            window_size=self.window_size
        )
        self.model.load_state_dict(checkpoint["model_state_dict"])
        self.model = self.model.to(self.device)
        self.model.eval()

        # Log loaded config
        best_metrics = checkpoint.get("best_val_metrics", {})
        logger.info(f"  Model type: {model_type}")
        logger.info(f"  Window size: {self.window_size}")
        logger.info(f"  Channels: {len(self.channel_names)} ({self.channel_names[0]}...{self.channel_names[-1]})")
        if self.tp_only:
            logger.info(f"  TP-only mode: True (using only temple sensors TP9/TP10)")
        elif self.eeg_only:
            logger.info(f"  EEG-only mode: True (motion sensors excluded)")
        logger.info(f"  Trained val accuracy: {best_metrics.get('accuracy', 'N/A')}")
        logger.info(f"  Trained val F1: {best_metrics.get('f1', 'N/A')}")

    def _normalize(self, data: np.ndarray) -> np.ndarray:
        """Apply z-score normalization using trained statistics.

        IMPORTANT: Must match preprocess.py normalization exactly!
        Training uses std directly (with 1e-8 floor), so inference must too.
        """
        # Use same logic as preprocess.py: only replace truly zero stds
        safe_stds = np.where(self.channel_stds < 1e-8, 1.0, self.channel_stds)

        normalized = (data - self.channel_means) / safe_stds

        return np.nan_to_num(normalized, nan=0.0).astype(np.float32)

    def _interpolate_to_timestamps(
        self,
        data: np.ndarray,
        data_ts: np.ndarray,
        target_ts: np.ndarray,
        n_channels: int
    ) -> np.ndarray:
        """
        Interpolate data to match target timestamps.

        Uses edge values (not zeros) for extrapolation to avoid
        creating artificial zeros that break normalization.
        """
        if data is None or len(data) < 2:
            # No data available - return zeros (will be handled by normalization clipping)
            return np.zeros((len(target_ts), n_channels), dtype=np.float32)

        actual_channels = data.shape[1] if data.ndim > 1 else 1
        interpolated = np.zeros((len(target_ts), n_channels), dtype=np.float32)

        for i in range(min(actual_channels, n_channels)):
            channel_data = data[:, i] if data.ndim > 1 else data
            # Use edge values for extrapolation instead of zeros
            interpolated[:, i] = np.interp(
                target_ts,
                data_ts,
                channel_data,
                left=channel_data[0],   # Use first value for extrapolation
                right=channel_data[-1]  # Use last value for extrapolation
            )

        return interpolated

    def process(
        self,
        eeg_data: np.ndarray,
        eeg_timestamps: np.ndarray,
        accgyro_data: Optional[np.ndarray] = None,
        accgyro_timestamps: Optional[np.ndarray] = None,
        optics_data: Optional[np.ndarray] = None,
        optics_timestamps: Optional[np.ndarray] = None
    ) -> InferenceResult:
        """
        Process a chunk of sensor data and run inference.

        Args:
            eeg_data: EEG samples, shape (n_samples, 8) - all EEG channels
            eeg_timestamps: Timestamps for EEG samples
            accgyro_data: Optional accelerometer/gyro, shape (n_samples, 6)
            accgyro_timestamps: Timestamps for ACCGYRO samples
            optics_data: Ignored - OPTICS channels excluded due to variance issues
            optics_timestamps: Ignored

        Returns:
            InferenceResult with probability and detection status
        """
        if eeg_data is None or len(eeg_data) == 0:
            return InferenceResult(
                probability=0.0,
                is_clenching=False,
                is_detection=False,
                window_ready=False
            )

        # Add data to timestamped buffers
        # Ensure EEG has 8 channels
        n_eeg_ch = eeg_data.shape[1] if eeg_data.ndim > 1 else 1
        if n_eeg_ch < 8:
            eeg_8ch = np.zeros((len(eeg_data), 8), dtype=np.float32)
            eeg_8ch[:, :n_eeg_ch] = eeg_data
        else:
            eeg_8ch = eeg_data[:, :8].astype(np.float32)

        self._eeg_buffer.add_samples(eeg_8ch, eeg_timestamps)

        if accgyro_data is not None and accgyro_timestamps is not None:
            self._accgyro_buffer.add_samples(accgyro_data.astype(np.float32), accgyro_timestamps)

        # Note: optics_data is intentionally ignored - OPTICS channels excluded

        # Check if we have enough EEG samples for a window
        if self._eeg_buffer.samples_collected < self.window_size:
            return InferenceResult(
                probability=0.0,
                is_clenching=False,
                is_detection=False,
                window_ready=False
            )

        # Get the EEG window and its timestamps
        eeg_all, eeg_ts_all = self._eeg_buffer.get_all_data()

        # Get the last window_size samples
        window_eeg = eeg_all[-self.window_size:]
        window_ts = eeg_ts_all[-self.window_size:]

        # Get ACCGYRO data from buffer (OPTICS excluded)
        accgyro_all, accgyro_ts_all = self._accgyro_buffer.get_all_data()

        # Interpolate ACCGYRO to match EEG timestamps
        if len(accgyro_all) >= 2:
            accgyro_interp = self._interpolate_to_timestamps(
                accgyro_all, accgyro_ts_all, window_ts, n_channels=6
            )
        else:
            accgyro_interp = np.zeros((self.window_size, 6), dtype=np.float32)

        # Combine channels based on model's expected input
        if self.tp_only:
            # TP-only mode: use only TP9 (index 0) and TP10 (index 3)
            window = window_eeg[:, [0, 3]]  # tp9, tp10
        elif self.eeg_only:
            # EEG-only mode: use only EEG channels (8 channels)
            window = window_eeg
        else:
            # Full mode: 8 EEG + 6 ACCGYRO = 14 channels (no OPTICS)
            window = np.hstack([window_eeg, accgyro_interp])

        # Normalize
        window_norm = self._normalize(window)

        # Debug logging
        self._debug_counter += 1
        if self._debug_counter <= 5 or self._debug_counter % 50 == 0:
            logger.debug(f"[Inference #{self._debug_counter}] Raw window stats: min={window.min():.2f}, max={window.max():.2f}, mean={window.mean():.2f}")
            logger.debug(f"[Inference #{self._debug_counter}] Normalized stats: min={window_norm.min():.2f}, max={window_norm.max():.2f}, mean={window_norm.mean():.2f}")

            # Check for degenerate data
            n_ch = window.shape[1]
            zero_channels = (np.abs(window).sum(axis=0) < 1e-6).sum()
            if zero_channels > 0:
                logger.warning(f"[Inference #{self._debug_counter}] WARNING: {zero_channels}/{n_ch} channels are all zeros!")

            clipped_high = (window_norm >= 9.9).sum()
            clipped_low = (window_norm <= -9.9).sum()
            if clipped_high > 0 or clipped_low > 0:
                logger.debug(f"[Inference #{self._debug_counter}] Clipped values: {clipped_high} high, {clipped_low} low (out of {window_norm.size})")
            if self._debug_counter == 1:
                channel_means = window.mean(axis=0)
                logger.debug(f"[Inference #1] Per-channel raw means (first 10): {channel_means[:min(10, n_ch)]}")
                logger.debug(f"[Inference #1] Training means (first 10): {self.channel_means[:min(10, n_ch)]}")
                # Show per-channel comparison for all channels
                for i in range(n_ch):
                    if abs(channel_means[i] - self.channel_means[i]) > abs(self.channel_means[i]) * 0.5:
                        ch_name = self.channel_names[i] if i < len(self.channel_names) else f"ch{i}"
                        logger.debug(f"[Inference #1] Channel {i} ({ch_name}): raw={channel_means[i]:.2f}, training={self.channel_means[i]:.2f} - MISMATCH")

        # Run inference
        with torch.no_grad():
            x = torch.tensor(window_norm, dtype=torch.float32).unsqueeze(0)
            x = x.to(self.device)

            # Get raw logits for debugging
            logits = self.model(x)
            probability = torch.sigmoid(logits).squeeze(-1).item()

            # Log raw logits to diagnose always-zero probability
            if self._debug_counter <= 5 or self._debug_counter % 50 == 0:
                logit_val = logits.item()
                logger.debug(f"[Inference #{self._debug_counter}] Raw logit={logit_val:.4f}, sigmoid(logit)={probability:.6f}")

        # Check threshold
        is_clenching = probability >= self.detection_threshold

        # Apply debounce
        is_detection = False
        if is_clenching:
            current_time = time.time()
            if self._last_detection_time is None:
                is_detection = True
                self._last_detection_time = current_time
            elif (current_time - self._last_detection_time) >= self.debounce_seconds:
                is_detection = True
                self._last_detection_time = current_time

        return InferenceResult(
            probability=probability,
            is_clenching=is_clenching,
            is_detection=is_detection,
            window_ready=True
        )

    def reset(self) -> None:
        """Reset buffer and debounce state."""
        self._eeg_buffer.reset()
        self._accgyro_buffer.reset()
        self._last_detection_time = None
        self._debug_counter = 0

    @property
    def is_ready(self) -> bool:
        """Whether the buffer has enough data for inference."""
        return self._eeg_buffer.samples_collected >= self.window_size


def load_inference_engine(
    model_path: str,
    threshold: float = 0.5,
    debounce: float = 2.0
) -> MLInferenceEngine:
    """
    Convenience function to load an inference engine.

    Args:
        model_path: Path to trained model
        threshold: Detection threshold (0-1)
        debounce: Debounce seconds

    Returns:
        Initialized MLInferenceEngine
    """
    return MLInferenceEngine(
        model_path=model_path,
        detection_threshold=threshold,
        debounce_seconds=debounce
    )
