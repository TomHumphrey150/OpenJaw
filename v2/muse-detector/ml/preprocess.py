"""
Minimal preprocessing for ML training.

Philosophy: Let the model learn features, not us.

Only performs:
1. Windowing - Slice continuous data into fixed-size windows
2. Normalization - Z-score normalization per session
3. Label assignment - Binary label per window based on majority vote

Does NOT do:
- Hand-crafted features
- Frequency band extraction
- Statistical summaries
"""

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np

logger = logging.getLogger("ml.preprocess")


@dataclass
class WindowConfig:
    """Configuration for windowing."""
    window_size_samples: int = 256  # 1 second at 256 Hz
    stride_samples: int = 128  # 50% overlap
    min_positive_ratio: float = 0.5  # Fraction of samples that must be positive for positive label


@dataclass
class PreprocessedDataset:
    """Preprocessed dataset ready for training."""
    # Shape: (n_windows, window_size, n_channels)
    X: np.ndarray

    # Shape: (n_windows,) - binary labels
    y: np.ndarray

    # Metadata
    session_ids: List[str]  # Session ID for each window
    window_indices: np.ndarray  # Original indices for each window

    # Normalization parameters (for inference)
    channel_means: np.ndarray
    channel_stds: np.ndarray

    @property
    def n_windows(self) -> int:
        return len(self.y)

    @property
    def n_channels(self) -> int:
        return self.X.shape[2]

    @property
    def window_size(self) -> int:
        return self.X.shape[1]

    @property
    def positive_ratio(self) -> float:
        return np.mean(self.y)


# Channel order in preprocessed data (30 total channels)
# 8 EEG + 6 ACCGYRO + 16 OPTICS = 30 channels
CHANNEL_NAMES = [
    # 8 EEG channels (256 Hz)
    "eeg_tp9", "eeg_af7", "eeg_af8", "eeg_tp10",
    "eeg_aux1", "eeg_aux2", "eeg_aux3", "eeg_aux4",
    # 6 ACCGYRO channels (52 Hz, interpolated to 256 Hz)
    "acc_x", "acc_y", "acc_z",
    "gyro_x", "gyro_y", "gyro_z",
    # 16 OPTICS/PPG channels (64 Hz, interpolated to 256 Hz)
    "optics_lo_nir", "optics_ro_nir", "optics_lo_ir", "optics_ro_ir",
    "optics_li_nir", "optics_ri_nir", "optics_li_ir", "optics_ri_ir",
    "optics_lo_red", "optics_ro_red", "optics_lo_amb", "optics_ro_amb",
    "optics_li_red", "optics_ri_red", "optics_li_amb", "optics_ri_amb",
]

# EEG-only channels (for training without motion sensors)
# TP9/TP10 are near temporalis muscle - may capture jaw EMG as 20-40 Hz artifacts
EEG_CHANNELS = [
    "eeg_tp9", "eeg_af7", "eeg_af8", "eeg_tp10",
    "eeg_aux1", "eeg_aux2", "eeg_aux3", "eeg_aux4",
]

# Temple channels only - closest to temporalis (jaw clenching) muscle
# These are the most likely to pick up jaw EMG artifacts
TP_CHANNELS = ["eeg_tp9", "eeg_tp10"]

# EEG + ACCGYRO channels (no OPTICS) - 14 channels total
# OPTICS channels have tiny variance during training causing extreme normalized
# values during live inference, so we exclude them entirely.
EEG_ACCGYRO_CHANNELS = [
    # 8 EEG channels
    "eeg_tp9", "eeg_af7", "eeg_af8", "eeg_tp10",
    "eeg_aux1", "eeg_aux2", "eeg_aux3", "eeg_aux4",
    # 6 ACCGYRO channels
    "acc_x", "acc_y", "acc_z",
    "gyro_x", "gyro_y", "gyro_z",
]


def load_session(
    parquet_path: Path,
    channels: Optional[List[str]] = None
) -> Tuple[np.ndarray, np.ndarray, str]:
    """
    Load a single session from parquet file.

    Args:
        parquet_path: Path to parquet file
        channels: List of channel names to load. If None, loads all CHANNEL_NAMES.

    Returns:
        Tuple of (data, labels, session_id)
        - data: Shape (n_samples, n_channels)
        - labels: Shape (n_samples,) - per-sample labels
        - session_id: String identifier
    """
    try:
        import pandas as pd
    except ImportError:
        raise ImportError("pandas not installed. Install with: pip install pandas pyarrow")

    if channels is None:
        channels = CHANNEL_NAMES

    df = pd.read_parquet(parquet_path)

    # Extract channels in consistent order
    data = df[channels].values
    labels = df["label"].values
    session_id = df["session_id"].iloc[0]

    return data, labels, session_id


def normalize_data(
    data: np.ndarray,
    means: Optional[np.ndarray] = None,
    stds: Optional[np.ndarray] = None
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Z-score normalize data per channel.

    Args:
        data: Shape (n_samples, n_channels)
        means: Pre-computed means (for inference)
        stds: Pre-computed stds (for inference)

    Returns:
        Tuple of (normalized_data, means, stds)
    """
    if means is None:
        # Handle NaN values when computing stats
        means = np.nanmean(data, axis=0)
    if stds is None:
        stds = np.nanstd(data, axis=0)
        # Prevent division by zero
        stds = np.where(stds < 1e-8, 1.0, stds)

    normalized = (data - means) / stds

    # Replace NaN with 0 after normalization
    normalized = np.nan_to_num(normalized, nan=0.0)

    return normalized, means, stds


def create_windows(
    data: np.ndarray,
    labels: np.ndarray,
    config: WindowConfig
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Create overlapping windows from continuous data.

    Args:
        data: Shape (n_samples, n_channels)
        labels: Shape (n_samples,) - per-sample labels
        config: Windowing configuration

    Returns:
        Tuple of (windows, window_labels, window_indices)
        - windows: Shape (n_windows, window_size, n_channels)
        - window_labels: Shape (n_windows,) - majority vote labels
        - window_indices: Shape (n_windows,) - start index of each window
    """
    n_samples, n_channels = data.shape
    window_size = config.window_size_samples
    stride = config.stride_samples

    # Calculate number of windows
    n_windows = (n_samples - window_size) // stride + 1

    if n_windows <= 0:
        return np.empty((0, window_size, n_channels)), np.empty(0), np.empty(0)

    # Pre-allocate arrays
    windows = np.zeros((n_windows, window_size, n_channels), dtype=np.float32)
    window_labels = np.zeros(n_windows, dtype=np.int64)
    window_indices = np.zeros(n_windows, dtype=np.int64)

    for i in range(n_windows):
        start = i * stride
        end = start + window_size

        windows[i] = data[start:end]
        window_indices[i] = start

        # Assign label based on majority vote
        window_label_samples = labels[start:end]
        positive_ratio = np.mean(window_label_samples)
        window_labels[i] = 1 if positive_ratio >= config.min_positive_ratio else 0

    return windows, window_labels, window_indices


def preprocess_sessions(
    parquet_paths: List[Path],
    config: Optional[WindowConfig] = None,
    normalize: bool = True,
    channels: Optional[List[str]] = None
) -> PreprocessedDataset:
    """
    Load and preprocess multiple sessions.

    Args:
        parquet_paths: List of paths to parquet files
        config: Windowing configuration
        normalize: Whether to apply z-score normalization
        channels: List of channel names to use. If None, uses all CHANNEL_NAMES.

    Returns:
        PreprocessedDataset ready for training
    """
    if config is None:
        config = WindowConfig()

    if channels is None:
        channels = CHANNEL_NAMES

    all_windows = []
    all_labels = []
    all_session_ids = []
    all_indices = []

    # First pass: load all data to compute global normalization stats
    all_data = []
    session_data_list = []

    for path in parquet_paths:
        logger.info(f"Loading session: {path.name}")
        data, labels, session_id = load_session(path, channels=channels)
        all_data.append(data)
        session_data_list.append((data, labels, session_id))

    # Compute global normalization parameters
    if normalize and all_data:
        combined_data = np.vstack(all_data)
        _, global_means, global_stds = normalize_data(combined_data)
    else:
        global_means = np.zeros(len(channels))
        global_stds = np.ones(len(channels))

    # Second pass: normalize and create windows
    for data, labels, session_id in session_data_list:
        # Normalize using global stats
        if normalize:
            data_norm, _, _ = normalize_data(data, global_means, global_stds)
        else:
            data_norm = data

        # Create windows
        windows, window_labels, window_indices = create_windows(
            data_norm, labels, config
        )

        if len(windows) > 0:
            all_windows.append(windows)
            all_labels.append(window_labels)
            all_session_ids.extend([session_id] * len(windows))
            all_indices.append(window_indices)

            pos = np.sum(window_labels)
            neg = len(window_labels) - pos
            logger.info(
                f"  {session_id}: {len(windows)} windows "
                f"({pos} positive, {neg} negative)"
            )

    if not all_windows:
        raise ValueError("No windows created from input data")

    # Concatenate all windows
    X = np.vstack(all_windows)
    y = np.concatenate(all_labels)
    indices = np.concatenate(all_indices)

    dataset = PreprocessedDataset(
        X=X,
        y=y,
        session_ids=all_session_ids,
        window_indices=indices,
        channel_means=global_means,
        channel_stds=global_stds,
    )

    logger.info("")
    logger.info(f"Total windows: {dataset.n_windows}")
    logger.info(f"Positive ratio: {dataset.positive_ratio:.1%}")
    logger.info(f"Window shape: {dataset.X.shape}")

    return dataset


def train_val_split(
    dataset: PreprocessedDataset,
    val_ratio: float = 0.2,
    stratify_by_session: bool = True,
    random_seed: int = 42
) -> Tuple[PreprocessedDataset, PreprocessedDataset]:
    """
    Split dataset into training and validation sets.

    Args:
        dataset: Full preprocessed dataset
        val_ratio: Fraction of data for validation
        stratify_by_session: If True, keep sessions together (no leakage).
                            Falls back to random split if only 1 session.
        random_seed: Random seed for reproducibility

    Returns:
        Tuple of (train_dataset, val_dataset)
    """
    np.random.seed(random_seed)

    unique_sessions = list(set(dataset.session_ids))

    # Fall back to random split if only 1 session (can't stratify by session)
    if stratify_by_session and len(unique_sessions) > 1:
        # Split by session to avoid data leakage
        np.random.shuffle(unique_sessions)

        n_val_sessions = max(1, int(len(unique_sessions) * val_ratio))
        val_sessions = set(unique_sessions[:n_val_sessions])
        train_sessions = set(unique_sessions[n_val_sessions:])

        train_mask = np.array([s in train_sessions for s in dataset.session_ids])
        val_mask = np.array([s in val_sessions for s in dataset.session_ids])

        logger.info(f"Train sessions: {sorted(train_sessions)}")
        logger.info(f"Val sessions: {sorted(val_sessions)}")
    else:
        # Random split (used when only 1 session or stratify_by_session=False)
        if len(unique_sessions) == 1:
            logger.info(f"Single session detected - using random split within session")
        n_val = int(len(dataset.y) * val_ratio)
        indices = np.random.permutation(len(dataset.y))
        val_indices = indices[:n_val]
        train_indices = indices[n_val:]

        train_mask = np.zeros(len(dataset.y), dtype=bool)
        train_mask[train_indices] = True
        val_mask = ~train_mask

    # Create split datasets
    train_dataset = PreprocessedDataset(
        X=dataset.X[train_mask],
        y=dataset.y[train_mask],
        session_ids=[s for s, m in zip(dataset.session_ids, train_mask) if m],
        window_indices=dataset.window_indices[train_mask],
        channel_means=dataset.channel_means,
        channel_stds=dataset.channel_stds,
    )

    val_dataset = PreprocessedDataset(
        X=dataset.X[val_mask],
        y=dataset.y[val_mask],
        session_ids=[s for s, m in zip(dataset.session_ids, val_mask) if m],
        window_indices=dataset.window_indices[val_mask],
        channel_means=dataset.channel_means,
        channel_stds=dataset.channel_stds,
    )

    logger.info(f"Train: {train_dataset.n_windows} windows ({train_dataset.positive_ratio:.1%} positive)")
    logger.info(f"Val: {val_dataset.n_windows} windows ({val_dataset.positive_ratio:.1%} positive)")

    return train_dataset, val_dataset
