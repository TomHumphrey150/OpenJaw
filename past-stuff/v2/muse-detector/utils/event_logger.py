"""
JSON event logging for jaw clench detection analysis.

Logs all detection events to a JSON Lines file for later analysis
and threshold tuning.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class EventLogger:
    """
    JSON Lines event logger for jaw clench detection.

    Logs events with timestamps, envelope values, thresholds, and
    other diagnostic information for analysis and tuning.
    """

    def __init__(
        self,
        log_dir: str = "logs",
        prefix: str = "events"
    ):
        """
        Initialize the event logger.

        Args:
            log_dir: Directory to store log files
            prefix: Filename prefix for log files
        """
        self.log_dir = Path(log_dir)
        self.prefix = prefix

        # Create log directory
        self.log_dir.mkdir(parents=True, exist_ok=True)

        # Create log file with date
        date_str = datetime.now().strftime("%Y-%m-%d")
        self.log_file = self.log_dir / f"{prefix}_{date_str}.jsonl"

        self._file = None
        self._event_count = 0

    def open(self) -> None:
        """Open the log file for appending."""
        self._file = open(self.log_file, "a")
        logger.info(f"Event log opened: {self.log_file}")

    def close(self) -> None:
        """Close the log file."""
        if self._file:
            self._file.close()
            self._file = None
            logger.info(f"Event log closed. Total events: {self._event_count}")

    def log_event(
        self,
        event_type: str,
        envelope_max: Optional[float] = None,
        threshold: Optional[float] = None,
        baseline_mean: Optional[float] = None,
        baseline_std: Optional[float] = None,
        extra: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Log a detection event.

        Args:
            event_type: Type of event (e.g., "jaw_clench", "calibration_complete")
            envelope_max: Maximum envelope value in the chunk
            threshold: Current detection threshold
            baseline_mean: Calibrated baseline mean
            baseline_std: Calibrated baseline std
            extra: Additional fields to include
        """
        if self._file is None:
            return

        self._event_count += 1

        record = {
            "timestamp": datetime.now().isoformat(),
            "event": event_type,
            "count": self._event_count
        }

        if envelope_max is not None:
            record["envelope_max"] = round(envelope_max, 6)
        if threshold is not None:
            record["threshold"] = round(threshold, 6)
        if baseline_mean is not None:
            record["baseline_mean"] = round(baseline_mean, 6)
        if baseline_std is not None:
            record["baseline_std"] = round(baseline_std, 6)
        if extra:
            record.update(extra)

        try:
            self._file.write(json.dumps(record) + "\n")
            self._file.flush()
        except Exception as e:
            logger.error(f"Error writing event log: {e}")

    def log_calibration(
        self,
        baseline_mean: float,
        baseline_std: float,
        threshold: float,
        samples: int
    ) -> None:
        """Log calibration completion."""
        self.log_event(
            "calibration_complete",
            baseline_mean=baseline_mean,
            baseline_std=baseline_std,
            threshold=threshold,
            extra={"samples": samples}
        )

    def log_jaw_clench(
        self,
        envelope_max: float,
        threshold: float,
        baseline_mean: float,
        baseline_std: float
    ) -> None:
        """Log a jaw clench detection."""
        self.log_event(
            "jaw_clench",
            envelope_max=envelope_max,
            threshold=threshold,
            baseline_mean=baseline_mean,
            baseline_std=baseline_std
        )

    def __enter__(self) -> "EventLogger":
        """Context manager entry."""
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """Context manager exit."""
        self.close()
