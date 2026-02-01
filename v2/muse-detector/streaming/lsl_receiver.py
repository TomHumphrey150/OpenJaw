"""
LSL stream receiver for connecting to OpenMuse EEG data.

OpenMuse streams Muse data via Lab Streaming Layer (LSL). This module
provides an async interface to receive EEG samples from the Muse_EEG stream.

Note: OpenMuse creates streams with names like "Muse-EEG (XX:XX:XX:XX:XX:XX)".
This module supports partial name matching to find these streams.
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import AsyncIterator, List, Optional

import numpy as np

logger = logging.getLogger("lsl")


class LSLConnectionError(Exception):
    """Raised when unable to connect to LSL stream."""
    pass


@dataclass
class EEGChunk:
    """A chunk of EEG data from the LSL stream."""
    tp9: np.ndarray
    tp10: np.ndarray
    timestamps: np.ndarray
    sample_rate: float


class LSLReceiver:
    """
    Async receiver for OpenMuse EEG data via Lab Streaming Layer.

    Usage:
        receiver = LSLReceiver()
        await receiver.connect()

        async for chunk in receiver.stream():
            # Process chunk.tp9 and chunk.tp10
            pass
    """

    def __init__(
        self,
        stream_name: str = "Muse_EEG",
        channels: Optional[List[str]] = None,
        poll_interval_ms: int = 50,
        buffer_seconds: float = 2.0
    ):
        """
        Initialize the LSL receiver.

        Args:
            stream_name: Name of the LSL stream (default: "Muse_EEG")
            channels: Channel names to pick (default: ["EEG_TP9", "EEG_TP10"])
            poll_interval_ms: Polling interval in milliseconds
            buffer_seconds: Internal buffer size in seconds
        """
        self.stream_name = stream_name
        self.channels = channels or ["EEG_TP9", "EEG_TP10"]
        self.poll_interval = poll_interval_ms / 1000.0
        self.buffer_seconds = buffer_seconds

        self._stream = None
        self._sample_rate: Optional[float] = None
        self._connected = False

    @property
    def is_connected(self) -> bool:
        """Check if connected to LSL stream."""
        return self._connected

    @property
    def sample_rate(self) -> Optional[float]:
        """Get the stream sample rate (available after connect)."""
        return self._sample_rate

    def _find_matching_stream(self, timeout: float = 5.0) -> Optional[str]:
        """
        Find an LSL stream whose name contains self.stream_name.

        OpenMuse creates streams with names like "Muse-EEG (XX:XX:XX:XX:XX:XX)".
        This function searches for streams containing the given partial name,
        prioritizing EEG streams over other types (ACCGYRO, OPTICS, etc).

        Returns:
            Full stream name if found, None otherwise
        """
        try:
            from mne_lsl.lsl import resolve_streams
        except ImportError:
            return None

        logger.debug(f"Searching for stream matching '{self.stream_name}'...")

        streams = resolve_streams(timeout=timeout)

        # Collect all matching streams, prioritize EEG
        eeg_streams = []
        other_streams = []

        for stream in streams:
            name = stream.name
            # Check for partial match (case-insensitive)
            if self.stream_name.lower() in name.lower():
                # Prioritize EEG streams (we need TP9/TP10 channels)
                if "EEG" in name:
                    eeg_streams.append(name)
                    logger.debug(f"Found EEG stream: {name}")
                else:
                    other_streams.append(name)
                    logger.debug(f"Found other stream: {name}")

        # Return EEG stream first if available
        if eeg_streams:
            logger.debug(f"Selecting EEG stream: {eeg_streams[0]}")
            return eeg_streams[0]

        # Fall back to other streams
        if other_streams:
            logger.warning(f"No EEG stream found, using: {other_streams[0]}")
            return other_streams[0]

        return None

    async def connect(self, timeout_seconds: float = 10.0) -> None:
        """
        Connect to the LSL EEG stream.

        Supports partial name matching - if stream_name is "Muse", will match
        streams like "Muse-EEG (XX:XX:XX:XX:XX:XX)".

        Args:
            timeout_seconds: Maximum time to wait for stream

        Raises:
            LSLConnectionError: If stream not found or connection fails
        """
        try:
            from mne_lsl.stream import StreamLSL as Stream
        except ImportError as e:
            raise LSLConnectionError(
                "mne_lsl not installed. Install with: pip install -r requirements.txt"
            ) from e

        logger.info(f"Connecting to LSL stream matching: {self.stream_name}")

        try:
            # First, find the actual stream name (supports partial matching)
            loop = asyncio.get_event_loop()
            actual_name = await loop.run_in_executor(
                None, lambda: self._find_matching_stream(timeout=5.0)
            )

            if actual_name and actual_name != self.stream_name:
                logger.debug(f"Resolved '{self.stream_name}' to '{actual_name}'")
                stream_name_to_use = actual_name
            else:
                stream_name_to_use = self.stream_name

            # Create stream with buffer
            self._stream = Stream(
                bufsize=self.buffer_seconds,
                name=stream_name_to_use
            )

            # Connect with timeout
            await asyncio.wait_for(
                loop.run_in_executor(None, self._stream.connect),
                timeout=timeout_seconds
            )

            # Get sample rate from stream info
            self._sample_rate = self._stream.info["sfreq"]
            self._connected = True

            logger.info(
                f"Connected to '{stream_name_to_use}' at {self._sample_rate} Hz"
            )

        except asyncio.TimeoutError:
            raise LSLConnectionError(
                f"Timeout waiting for LSL stream '{self.stream_name}'. "
                "Is OpenMuse streaming? Run: OpenMuse stream --address <muse-address>"
            )
        except Exception as e:
            raise LSLConnectionError(
                f"Failed to connect to LSL stream: {e}"
            ) from e

    async def disconnect(self) -> None:
        """Disconnect from the LSL stream."""
        if self._stream is not None:
            try:
                self._stream.disconnect()
            except Exception as e:
                logger.warning(f"Error disconnecting from stream: {e}")
            finally:
                self._stream = None
                self._connected = False
                logger.info("Disconnected from LSL stream")

    async def stream(self) -> AsyncIterator[EEGChunk]:
        """
        Async generator yielding EEG chunks from the stream.

        Yields:
            EEGChunk with TP9, TP10 data and timestamps

        Raises:
            LSLConnectionError: If not connected
        """
        if not self._connected or self._stream is None:
            raise LSLConnectionError("Not connected. Call connect() first.")

        logger.info("Starting EEG stream...")

        while self._connected:
            try:
                # Check for new samples
                n_new = self._stream.n_new_samples

                if n_new > 0:
                    # Calculate window size in seconds
                    winsize = n_new / self._sample_rate

                    # Get data for TP9 and TP10 channels
                    data, timestamps = self._stream.get_data(
                        winsize,
                        picks=self.channels
                    )

                    # data shape: (n_channels, n_samples)
                    # channels[0] = TP9, channels[1] = TP10
                    yield EEGChunk(
                        tp9=data[0],
                        tp10=data[1],
                        timestamps=timestamps,
                        sample_rate=self._sample_rate
                    )

                # Wait before next poll
                await asyncio.sleep(self.poll_interval)

            except Exception as e:
                logger.error(f"Error reading from stream: {e}")
                # Brief pause before retry
                await asyncio.sleep(0.1)

    async def __aenter__(self) -> "LSLReceiver":
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Async context manager exit."""
        await self.disconnect()
