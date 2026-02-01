"""
Jaw clench detection via EMG extraction from Muse EEG channels.

Signal processing pipeline:
1. Bandpass filter (20-100 Hz) to extract EMG from temporalis muscle
2. Full-wave rectification
3. Envelope extraction (5 Hz lowpass)
4. MVC-based threshold (percentage of maximum voluntary contraction)
5. Debounce logic (minimum interval between detections)

Calibration uses Maximum Voluntary Contraction (MVC) approach:
- Phase 1: User relaxes jaw (establishes noise floor)
- Phase 2: User clenches hard (establishes maximum)
- Threshold = relaxed_baseline + mvc_threshold_percent × (max - baseline)
"""

import logging
import time
from collections import deque
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Tuple

import numpy as np
from scipy.signal import sosfilt

from .filters import design_bandpass_filter, design_lowpass_filter

logger = logging.getLogger(__name__)


class CalibrationPhase(Enum):
    """Calibration phases for MVC-based detection."""
    NOT_STARTED = "not_started"
    RELAXED = "relaxed"        # Phase 1: Relaxed jaw baseline
    CLENCH = "clench"          # Phase 2: Maximum voluntary clench
    COMPLETE = "complete"


@dataclass
class DetectionResult:
    """Result from processing a sample chunk."""
    envelope: np.ndarray
    is_clenching: bool
    threshold: Optional[float]
    calibrating: bool
    calibration_phase: Optional[str] = None  # "relaxed", "clench", or None


class JawClenchDetector:
    """
    Real-time jaw clench detector using EMG extraction from TP9/TP10 channels.

    Uses MVC (Maximum Voluntary Contraction) calibration:
    1. User relaxes jaw for a few seconds (noise floor)
    2. User clenches hard for a few seconds (maximum)
    3. Threshold is set as percentage of the range between relaxed and max
    """

    def __init__(
        self,
        sample_rate: float = 256.0,
        mvc_threshold_percent: float = 0.35,
        relaxed_calibration_seconds: float = 3.0,
        clench_calibration_seconds: float = 3.0,
        debounce_seconds: float = 2.0,
        bandpass_low_hz: float = 20.0,
        bandpass_high_hz: float = 100.0,
        envelope_cutoff_hz: float = 5.0,
        filter_order: int = 4
    ):
        """
        Initialize the jaw clench detector.

        Args:
            sample_rate: EEG sample rate in Hz (Muse = 256 Hz)
            mvc_threshold_percent: Threshold as percentage of MVC (0.0-1.0)
                                   0.35 = detect at 35% of max clench strength
            relaxed_calibration_seconds: Duration of relaxed jaw calibration
            clench_calibration_seconds: Duration of max clench calibration
            debounce_seconds: Minimum interval between detections
            bandpass_low_hz: Lower cutoff for EMG bandpass filter
            bandpass_high_hz: Upper cutoff for EMG bandpass filter
            envelope_cutoff_hz: Cutoff for envelope lowpass filter
            filter_order: Butterworth filter order
        """
        self.sample_rate = sample_rate
        self.mvc_threshold_percent = mvc_threshold_percent
        self.relaxed_calibration_seconds = relaxed_calibration_seconds
        self.clench_calibration_seconds = clench_calibration_seconds
        self.debounce_seconds = debounce_seconds

        # Design filters
        self.sos_bandpass = design_bandpass_filter(
            bandpass_low_hz, bandpass_high_hz, sample_rate, filter_order
        )
        self.sos_envelope = design_lowpass_filter(
            envelope_cutoff_hz, sample_rate, filter_order
        )

        # Calibration state - MVC approach
        relaxed_samples = int(relaxed_calibration_seconds * sample_rate)
        clench_samples = int(clench_calibration_seconds * sample_rate)
        self.relaxed_buffer: deque = deque(maxlen=relaxed_samples)
        self.clench_buffer: deque = deque(maxlen=clench_samples)

        self.relaxed_baseline: Optional[float] = None  # Mean during relaxed
        self.mvc_value: Optional[float] = None         # Max during clench
        self._calibration_phase = CalibrationPhase.NOT_STARTED
        self._threshold: Optional[float] = None

        # Debounce state
        self._last_detection_time: Optional[float] = None

        # Filter state (for continuous filtering across chunks)
        self._bandpass_zi: Optional[np.ndarray] = None
        self._envelope_zi: Optional[np.ndarray] = None

        logger.info(
            f"JawClenchDetector initialized: "
            f"mvc_threshold={mvc_threshold_percent:.0%}, "
            f"relaxed_cal={relaxed_calibration_seconds}s, "
            f"clench_cal={clench_calibration_seconds}s, "
            f"debounce={debounce_seconds}s"
        )

    @property
    def is_calibrated(self) -> bool:
        """Check if calibration is complete."""
        return self._calibration_phase == CalibrationPhase.COMPLETE

    @property
    def calibration_phase(self) -> CalibrationPhase:
        """Get current calibration phase."""
        return self._calibration_phase

    @property
    def calibration_progress(self) -> float:
        """Get calibration progress as a fraction (0.0 to 1.0)."""
        if self._calibration_phase == CalibrationPhase.COMPLETE:
            return 1.0
        elif self._calibration_phase == CalibrationPhase.RELAXED:
            # First half: relaxed phase
            progress = len(self.relaxed_buffer) / self.relaxed_buffer.maxlen
            return progress * 0.5
        elif self._calibration_phase == CalibrationPhase.CLENCH:
            # Second half: clench phase
            progress = len(self.clench_buffer) / self.clench_buffer.maxlen
            return 0.5 + (progress * 0.5)
        return 0.0

    def start_calibration(self) -> None:
        """Start the calibration process (relaxed phase)."""
        self.relaxed_buffer.clear()
        self.clench_buffer.clear()
        self.relaxed_baseline = None
        self.mvc_value = None
        self._threshold = None
        self._calibration_phase = CalibrationPhase.RELAXED
        self._last_detection_time = None
        logger.info("CALIBRATION STARTED - Phase 1: Keep jaw RELAXED")

    def start_clench_phase(self) -> None:
        """Transition from relaxed to clench calibration phase."""
        if self._calibration_phase != CalibrationPhase.RELAXED:
            logger.warning("Cannot start clench phase - not in relaxed phase")
            return

        # Compute relaxed baseline from collected data
        relaxed_data = np.array(self.relaxed_buffer)
        self.relaxed_baseline = float(np.mean(relaxed_data))

        self._calibration_phase = CalibrationPhase.CLENCH
        logger.info(
            f"CALIBRATION Phase 2: CLENCH JAW HARD! "
            f"(relaxed baseline={self.relaxed_baseline:.2f})"
        )

    def reset_calibration(self) -> None:
        """Reset calibration state to start fresh."""
        self.relaxed_buffer.clear()
        self.clench_buffer.clear()
        self.relaxed_baseline = None
        self.mvc_value = None
        self._threshold = None
        self._calibration_phase = CalibrationPhase.NOT_STARTED
        self._last_detection_time = None
        logger.info("Calibration reset")

    def _compute_envelope(self, raw_eeg: np.ndarray) -> np.ndarray:
        """Apply signal processing pipeline to extract EMG envelope."""
        # Apply bandpass filter for EMG extraction
        emg = sosfilt(self.sos_bandpass, raw_eeg)

        # Full-wave rectification
        rectified = np.abs(emg)

        # Envelope extraction via lowpass filter
        envelope = sosfilt(self.sos_envelope, rectified)

        return envelope

    def process(self, raw_eeg: np.ndarray) -> DetectionResult:
        """
        Process raw EEG data from TP9 or TP10 channel.

        Args:
            raw_eeg: 1D array of raw EEG samples

        Returns:
            DetectionResult with envelope, detection status, and calibration state
        """
        if len(raw_eeg) == 0:
            return DetectionResult(
                envelope=np.array([]),
                is_clenching=False,
                threshold=None,
                calibrating=self._calibration_phase != CalibrationPhase.COMPLETE,
                calibration_phase=self._calibration_phase.value if self._calibration_phase != CalibrationPhase.COMPLETE else None
            )

        envelope = self._compute_envelope(raw_eeg)

        # Handle different calibration phases
        if self._calibration_phase == CalibrationPhase.NOT_STARTED:
            # Auto-start calibration on first data
            self.start_calibration()

        if self._calibration_phase == CalibrationPhase.RELAXED:
            # Phase 1: Collecting relaxed baseline
            self.relaxed_buffer.extend(envelope)

            if len(self.relaxed_buffer) >= self.relaxed_buffer.maxlen:
                # Relaxed phase complete, transition to clench
                self.start_clench_phase()

            return DetectionResult(
                envelope=envelope,
                is_clenching=False,
                threshold=None,
                calibrating=True,
                calibration_phase="relaxed"
            )

        if self._calibration_phase == CalibrationPhase.CLENCH:
            # Phase 2: Collecting max clench data
            self.clench_buffer.extend(envelope)

            if len(self.clench_buffer) >= self.clench_buffer.maxlen:
                # Clench phase complete - compute MVC and threshold
                clench_data = np.array(self.clench_buffer)
                # Use 95th percentile as MVC (robust to outliers)
                self.mvc_value = float(np.percentile(clench_data, 95))

                # Threshold = baseline + percent × (mvc - baseline)
                mvc_range = self.mvc_value - self.relaxed_baseline
                self._threshold = self.relaxed_baseline + (
                    self.mvc_threshold_percent * mvc_range
                )

                self._calibration_phase = CalibrationPhase.COMPLETE

                logger.info(
                    f"CALIBRATION COMPLETE: "
                    f"relaxed={self.relaxed_baseline:.2f}, "
                    f"MVC={self.mvc_value:.2f}, "
                    f"threshold={self._threshold:.2f} "
                    f"({self.mvc_threshold_percent:.0%} of range)"
                )

            return DetectionResult(
                envelope=envelope,
                is_clenching=False,
                threshold=None,
                calibrating=True,
                calibration_phase="clench"
            )

        # Calibration complete - run detection
        threshold = self._threshold

        # Check if any sample exceeds threshold
        max_envelope = float(np.max(envelope))
        exceeds_threshold = max_envelope > threshold

        # Apply debounce logic
        is_clenching = False
        if exceeds_threshold:
            current_time = time.time()
            if self._last_detection_time is None:
                is_clenching = True
                self._last_detection_time = current_time
            elif (current_time - self._last_detection_time) >= self.debounce_seconds:
                is_clenching = True
                self._last_detection_time = current_time

        return DetectionResult(
            envelope=envelope,
            is_clenching=is_clenching,
            threshold=threshold,
            calibrating=False
        )

    def process_bilateral(
        self,
        tp9_data: np.ndarray,
        tp10_data: np.ndarray
    ) -> DetectionResult:
        """
        Process both TP9 and TP10 channels for bilateral detection.

        Combines both channels by averaging their envelopes, which can
        improve accuracy by requiring activation on both sides.

        Args:
            tp9_data: Raw EEG from TP9 (left temporalis)
            tp10_data: Raw EEG from TP10 (right temporalis)

        Returns:
            DetectionResult based on combined bilateral signal
        """
        if len(tp9_data) == 0 or len(tp10_data) == 0:
            return DetectionResult(
                envelope=np.array([]),
                is_clenching=False,
                threshold=None,
                calibrating=not self._calibration_complete
            )

        # Average the two channels for bilateral detection
        combined = (tp9_data + tp10_data) / 2.0
        return self.process(combined)
