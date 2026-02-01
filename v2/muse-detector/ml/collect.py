"""
Data collection with spacebar labeling for ML training.

Hold spacebar when clenching/grinding, release when relaxed.
Captures all Muse streams (EEG, ACCGYRO) and saves labeled data to parquet.

Usage:
    collector = DataCollector(session_id="test_001")
    await collector.run(duration=300)  # 5 minutes
"""

import asyncio
import logging
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import List, Optional

import numpy as np

logger = logging.getLogger("ml.collect")


@dataclass
class LabeledSample:
    """A single timestamped sample with label.

    Captures ALL Muse S channels:
    - 8 EEG channels (TP9, AF7, AF8, TP10, AUX1-4)
    - 6 ACCGYRO channels (ACC X/Y/Z, GYRO X/Y/Z)
    - Up to 16 OPTICS channels (PPG sensors)
    """
    timestamp: float  # LSL timestamp

    # EEG channels (8 total - raw values)
    eeg_tp9: float
    eeg_af7: float
    eeg_af8: float
    eeg_tp10: float
    eeg_aux1: float
    eeg_aux2: float
    eeg_aux3: float
    eeg_aux4: float

    # Accelerometer/Gyroscope (6 total - raw values)
    acc_x: float
    acc_y: float
    acc_z: float
    gyro_x: float
    gyro_y: float
    gyro_z: float

    # Optics/PPG (16 total - may be NaN if not all available)
    optics_lo_nir: float
    optics_ro_nir: float
    optics_lo_ir: float
    optics_ro_ir: float
    optics_li_nir: float
    optics_ri_nir: float
    optics_li_ir: float
    optics_ri_ir: float
    optics_lo_red: float
    optics_ro_red: float
    optics_lo_amb: float
    optics_ro_amb: float
    optics_li_red: float
    optics_ri_red: float
    optics_li_amb: float
    optics_ri_amb: float

    # Label: 0=relaxed, 1=clenching
    label: int

    session_id: str


@dataclass
class CollectionStats:
    """Statistics from a data collection session."""
    session_id: str
    duration_seconds: float
    total_samples: int
    positive_samples: int  # label=1
    negative_samples: int  # label=0
    positive_ratio: float
    eeg_sample_rate: float
    output_file: str


class KeyboardMonitor:
    """
    Monitor spacebar state for labeling.

    Uses pynput for cross-platform keyboard monitoring.
    """

    def __init__(self):
        self._spacebar_pressed = False
        self._stop_requested = False
        self._listener = None

    @property
    def is_clenching(self) -> bool:
        """Returns True if spacebar is currently held."""
        return self._spacebar_pressed

    @property
    def stop_requested(self) -> bool:
        """Returns True if ESC was pressed."""
        return self._stop_requested

    def start(self) -> None:
        """Start keyboard monitoring."""
        try:
            from pynput import keyboard
        except ImportError:
            raise ImportError(
                "pynput not installed. Install with: pip install pynput"
            )

        self._stop_requested = False

        def on_press(key):
            if key == keyboard.Key.space:
                self._spacebar_pressed = True
            if key == keyboard.Key.esc:
                self._stop_requested = True

        def on_release(key):
            if key == keyboard.Key.space:
                self._spacebar_pressed = False

        self._listener = keyboard.Listener(
            on_press=on_press,
            on_release=on_release
        )
        self._listener.start()
        logger.info("Keyboard monitoring started (spacebar for labeling, ESC to stop)")

    def stop(self) -> None:
        """Stop keyboard monitoring."""
        if self._listener:
            self._listener.stop()
            self._listener = None
            logger.debug("Keyboard monitoring stopped")


class DataCollector:
    """
    Collects labeled multi-stream Muse data for ML training.

    Hold spacebar during jaw clenching/grinding activities.
    Data is saved to parquet files in data/raw/.
    """

    def __init__(
        self,
        session_id: str,
        output_dir: str = "data/raw",
        stream_name_prefix: str = "Muse"
    ):
        """
        Initialize the data collector.

        Args:
            session_id: Unique identifier for this collection session
            output_dir: Directory to save parquet files
            stream_name_prefix: Prefix for LSL stream names
        """
        self.session_id = session_id
        self.output_dir = Path(output_dir)
        self.stream_name_prefix = stream_name_prefix

        self._samples: List[dict] = []
        self._keyboard = KeyboardMonitor()

        # Ensure output directory exists
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def _interpolate_stream(
        self,
        data: np.ndarray,
        data_ts: np.ndarray,
        target_ts: np.ndarray,
        n_channels: int
    ) -> np.ndarray:
        """
        Interpolate a stream to match target timestamps.

        Used to align ACCGYRO (52 Hz) and OPTICS (64 Hz) to EEG (256 Hz).

        Args:
            data: Shape (n_samples, n_channels)
            data_ts: Shape (n_samples,)
            target_ts: Shape (n_target_samples,) - target timestamps
            n_channels: Expected number of channels

        Returns:
            Interpolated data, shape (n_target_samples, n_channels)
        """
        if data is None or len(data) < 2:
            # Return NaN array if no data
            return np.full((len(target_ts), n_channels), np.nan)

        # Handle case where data has fewer channels than expected
        actual_channels = data.shape[1] if data.ndim > 1 else 1
        interpolated = np.full((len(target_ts), n_channels), np.nan)

        for i in range(min(actual_channels, n_channels)):
            interpolated[:, i] = np.interp(
                target_ts,
                data_ts,
                data[:, i] if data.ndim > 1 else data,
                left=np.nan,
                right=np.nan
            )

        return interpolated

    async def run(self, duration: float = 300.0) -> CollectionStats:
        """
        Run data collection for specified duration.

        Args:
            duration: Collection duration in seconds

        Returns:
            CollectionStats with session summary
        """
        from .streams import MultiStreamReceiver

        logger.info(f"Starting data collection session: {self.session_id}")
        logger.info(f"Duration: {duration} seconds")
        logger.info("")
        logger.info("=" * 60)
        logger.info("INSTRUCTIONS:")
        logger.info("  - HOLD SPACEBAR when clenching or grinding your jaw")
        logger.info("  - RELEASE SPACEBAR when jaw is relaxed")
        logger.info("  - Press ESC to stop early and save data")
        logger.info("=" * 60)
        logger.info("")

        # Start keyboard monitoring
        self._keyboard.start()

        start_time = time.time()
        last_label_state = None
        last_progress_second = -1
        eeg_sfreq = 256.0  # Default, will be updated
        stopped_early = False

        receiver = None
        try:
            receiver = MultiStreamReceiver(
                stream_name_prefix=self.stream_name_prefix,
                require_accgyro=True,
                include_optics=True  # Capture ALL Muse data including PPG
            )

            await receiver.connect()
            eeg_sfreq = receiver.eeg_sample_rate

            logger.info("Connected. Collecting data...")
            logger.info("(Hold SPACEBAR when clenching, press ESC to stop)")
            logger.info("")

            try:
                async for chunk in receiver.stream():
                    elapsed = time.time() - start_time
                    remaining = duration - elapsed

                    # Check for ESC key
                    if self._keyboard.stop_requested:
                        logger.info("")
                        logger.info("ESC pressed - stopping collection...")
                        stopped_early = True
                        break

                    # Check if duration reached
                    if elapsed >= duration:
                        break

                    # Get current label
                    label = 1 if self._keyboard.is_clenching else 0

                    # Log label changes
                    if label != last_label_state:
                        state_str = "CLENCHING" if label == 1 else "RELAXED"
                        logger.info(f"[{elapsed:.1f}s] Label: {state_str}")
                        last_label_state = label

                    # Process EEG data
                    if chunk.eeg is None:
                        continue

                    eeg_data = chunk.eeg  # Shape: (n_samples, n_channels)
                    eeg_ts = chunk.eeg_timestamps
                    n_eeg_ch = eeg_data.shape[1]

                    # Interpolate ACCGYRO (52 Hz) to EEG timestamps (256 Hz)
                    accgyro_interp = self._interpolate_stream(
                        chunk.accgyro,
                        chunk.accgyro_timestamps,
                        eeg_ts,
                        n_channels=6
                    )

                    # Interpolate OPTICS (64 Hz) to EEG timestamps (256 Hz)
                    optics_interp = self._interpolate_stream(
                        chunk.optics,
                        chunk.optics_timestamps,
                        eeg_ts,
                        n_channels=16
                    )

                    # Store each sample with ALL channels
                    for i in range(len(eeg_data)):
                        sample = {
                            "timestamp": eeg_ts[i],
                            # 8 EEG channels
                            "eeg_tp9": eeg_data[i, 0] if n_eeg_ch > 0 else np.nan,
                            "eeg_af7": eeg_data[i, 1] if n_eeg_ch > 1 else np.nan,
                            "eeg_af8": eeg_data[i, 2] if n_eeg_ch > 2 else np.nan,
                            "eeg_tp10": eeg_data[i, 3] if n_eeg_ch > 3 else np.nan,
                            "eeg_aux1": eeg_data[i, 4] if n_eeg_ch > 4 else np.nan,
                            "eeg_aux2": eeg_data[i, 5] if n_eeg_ch > 5 else np.nan,
                            "eeg_aux3": eeg_data[i, 6] if n_eeg_ch > 6 else np.nan,
                            "eeg_aux4": eeg_data[i, 7] if n_eeg_ch > 7 else np.nan,
                            # 6 ACCGYRO channels
                            "acc_x": accgyro_interp[i, 0],
                            "acc_y": accgyro_interp[i, 1],
                            "acc_z": accgyro_interp[i, 2],
                            "gyro_x": accgyro_interp[i, 3],
                            "gyro_y": accgyro_interp[i, 4],
                            "gyro_z": accgyro_interp[i, 5],
                            # 16 OPTICS channels (PPG)
                            "optics_lo_nir": optics_interp[i, 0],
                            "optics_ro_nir": optics_interp[i, 1],
                            "optics_lo_ir": optics_interp[i, 2],
                            "optics_ro_ir": optics_interp[i, 3],
                            "optics_li_nir": optics_interp[i, 4],
                            "optics_ri_nir": optics_interp[i, 5],
                            "optics_li_ir": optics_interp[i, 6],
                            "optics_ri_ir": optics_interp[i, 7],
                            "optics_lo_red": optics_interp[i, 8],
                            "optics_ro_red": optics_interp[i, 9],
                            "optics_lo_amb": optics_interp[i, 10],
                            "optics_ro_amb": optics_interp[i, 11],
                            "optics_li_red": optics_interp[i, 12],
                            "optics_ri_red": optics_interp[i, 13],
                            "optics_li_amb": optics_interp[i, 14],
                            "optics_ri_amb": optics_interp[i, 15],
                            # Label and session
                            "label": label,
                            "session_id": self.session_id,
                        }
                        self._samples.append(sample)

                    # Progress indicator every 10 seconds with countdown
                    current_second = int(elapsed)
                    if current_second % 10 == 0 and current_second != last_progress_second and current_second > 0:
                        last_progress_second = current_second
                        positive = sum(1 for s in self._samples if s["label"] == 1)
                        total = len(self._samples)
                        ratio = positive / total if total > 0 else 0
                        remaining_mins = int(remaining) // 60
                        remaining_secs = int(remaining) % 60
                        logger.info(
                            f"[{remaining_mins}:{remaining_secs:02d} remaining] "
                            f"{total:,} samples ({ratio:.1%} positive)"
                        )

            except KeyboardInterrupt:
                logger.info("")
                logger.info("Ctrl+C pressed - stopping collection and saving data...")
                stopped_early = True

            if receiver:
                await receiver.disconnect()

        finally:
            self._keyboard.stop()

        # Save data if we have any samples
        if not self._samples:
            raise ValueError("No samples collected")

        # Save to parquet
        actual_duration = time.time() - start_time
        stats = self._save_parquet(eeg_sfreq, actual_duration)

        if stopped_early:
            logger.info("(Collection stopped early but data was saved)")

        return stats

    def _save_parquet(self, eeg_sfreq: float, duration: float) -> CollectionStats:
        """Save collected samples to parquet file."""
        try:
            import pandas as pd
        except ImportError:
            raise ImportError(
                "pandas not installed. Install with: pip install pandas pyarrow"
            )

        if not self._samples:
            raise ValueError("No samples collected")

        # Create DataFrame
        df = pd.DataFrame(self._samples)

        # Generate output filename
        date_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = self.output_dir / f"{self.session_id}_{date_str}.parquet"

        # Save to parquet
        df.to_parquet(output_file, index=False, compression="snappy")

        # Calculate statistics
        total = len(df)
        positive = (df["label"] == 1).sum()
        negative = total - positive
        ratio = positive / total if total > 0 else 0

        stats = CollectionStats(
            session_id=self.session_id,
            duration_seconds=duration,
            total_samples=total,
            positive_samples=int(positive),
            negative_samples=int(negative),
            positive_ratio=ratio,
            eeg_sample_rate=eeg_sfreq,
            output_file=str(output_file),
        )

        logger.info("")
        logger.info("=" * 60)
        logger.info("COLLECTION COMPLETE")
        logger.info(f"  Session: {stats.session_id}")
        logger.info(f"  Duration: {stats.duration_seconds:.1f}s")
        logger.info(f"  Total samples: {stats.total_samples:,}")
        logger.info(f"  Positive (clenching): {stats.positive_samples:,} ({stats.positive_ratio:.1%})")
        logger.info(f"  Negative (relaxed): {stats.negative_samples:,}")
        logger.info(f"  Output: {stats.output_file}")
        logger.info("=" * 60)

        return stats
