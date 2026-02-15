"""
Multi-stream LSL receiver for capturing all Muse sensor data.

Captures EEG, accelerometer/gyroscope, and optionally optics streams
simultaneously for ML training data collection.

OpenMuse creates streams with names like:
- "Muse-EEG (XX:XX:XX:XX:XX:XX)" - 256 Hz, 4-8 channels
- "Muse-ACCGYRO (XX:XX:XX:XX:XX:XX)" - 52 Hz, 6 channels
- "Muse-OPTICS (XX:XX:XX:XX:XX:XX)" - 64 Hz, up to 16 channels
"""

import asyncio
import logging
from dataclasses import dataclass
from typing import AsyncIterator, Dict, List, Optional

import numpy as np

logger = logging.getLogger("ml.streams")


class MultiStreamConnectionError(Exception):
    """Raised when unable to connect to required LSL streams."""
    pass


@dataclass
class StreamChunk:
    """A chunk of multi-stream sensor data."""
    timestamp: float  # LSL timestamp of first sample

    # EEG data (256 Hz) - shape: (n_samples, 4)
    # Channels: TP9, AF7, AF8, TP10
    eeg: Optional[np.ndarray] = None
    eeg_timestamps: Optional[np.ndarray] = None

    # Accelerometer/Gyroscope data (52 Hz) - shape: (n_samples, 6)
    # Channels: ACC_X, ACC_Y, ACC_Z, GYRO_X, GYRO_Y, GYRO_Z
    accgyro: Optional[np.ndarray] = None
    accgyro_timestamps: Optional[np.ndarray] = None

    # Optics data (64 Hz) - shape: (n_samples, n_channels)
    optics: Optional[np.ndarray] = None
    optics_timestamps: Optional[np.ndarray] = None


@dataclass
class StreamInfo:
    """Information about a connected LSL stream."""
    name: str
    sfreq: float
    n_channels: int
    channel_names: List[str]


class MultiStreamReceiver:
    """
    Async receiver for multiple Muse sensor streams via LSL.

    Captures EEG (required) and ACCGYRO (required for ML) streams simultaneously.
    Optics stream is optional.

    Usage:
        receiver = MultiStreamReceiver()
        await receiver.connect()

        async for chunk in receiver.stream():
            # Process chunk.eeg, chunk.accgyro
            pass
    """

    # Channel names for each stream type
    EEG_CHANNELS = ["EEG_TP9", "EEG_AF7", "EEG_AF8", "EEG_TP10"]
    ACCGYRO_CHANNELS = ["ACC_X", "ACC_Y", "ACC_Z", "GYRO_X", "GYRO_Y", "GYRO_Z"]

    def __init__(
        self,
        stream_name_prefix: str = "Muse",
        poll_interval_ms: int = 50,
        buffer_seconds: float = 2.0,
        require_accgyro: bool = True,
        include_optics: bool = False
    ):
        """
        Initialize the multi-stream receiver.

        Args:
            stream_name_prefix: Prefix to match stream names (e.g., "Muse")
            poll_interval_ms: Polling interval in milliseconds
            buffer_seconds: Internal buffer size in seconds
            require_accgyro: If True, fail if ACCGYRO stream not found
            include_optics: If True, also capture optics stream
        """
        self.stream_name_prefix = stream_name_prefix
        self.poll_interval = poll_interval_ms / 1000.0
        self.buffer_seconds = buffer_seconds
        self.require_accgyro = require_accgyro
        self.include_optics = include_optics

        self._streams: Dict[str, any] = {}  # stream_type -> StreamLSL
        self._stream_info: Dict[str, StreamInfo] = {}
        self._connected = False

    @property
    def is_connected(self) -> bool:
        """Check if connected to required streams."""
        return self._connected

    @property
    def eeg_sample_rate(self) -> Optional[float]:
        """Get EEG stream sample rate."""
        info = self._stream_info.get("EEG")
        return info.sfreq if info else None

    @property
    def accgyro_sample_rate(self) -> Optional[float]:
        """Get ACCGYRO stream sample rate."""
        info = self._stream_info.get("ACCGYRO")
        return info.sfreq if info else None

    def _find_streams(self, timeout: float = 5.0) -> Dict[str, str]:
        """
        Find available Muse LSL streams.

        Returns:
            Dict mapping stream type ("EEG", "ACCGYRO", "OPTICS") to full stream name
        """
        try:
            from mne_lsl.lsl import resolve_streams
        except ImportError:
            raise MultiStreamConnectionError(
                "mne_lsl not installed. Install with: pip install mne-lsl"
            )

        logger.debug(f"Searching for streams matching '{self.stream_name_prefix}'...")

        streams = resolve_streams(timeout=timeout)
        found = {}

        for stream in streams:
            name = stream.name
            # Check for prefix match (case-insensitive)
            if self.stream_name_prefix.lower() not in name.lower():
                continue

            # Determine stream type from name
            if "EEG" in name:
                found["EEG"] = name
                logger.debug(f"Found EEG stream: {name}")
            elif "ACCGYRO" in name:
                found["ACCGYRO"] = name
                logger.debug(f"Found ACCGYRO stream: {name}")
            elif "OPTICS" in name:
                found["OPTICS"] = name
                logger.debug(f"Found OPTICS stream: {name}")

        return found

    async def connect(self, timeout_seconds: float = 30.0) -> None:
        """
        Connect to available Muse LSL streams.

        Args:
            timeout_seconds: Maximum time to wait for streams

        Raises:
            MultiStreamConnectionError: If required streams not found
        """
        try:
            from mne_lsl.stream import StreamLSL as Stream
        except ImportError as e:
            raise MultiStreamConnectionError(
                "mne_lsl not installed. Install with: pip install mne-lsl"
            ) from e

        logger.info(f"Connecting to Muse streams matching: {self.stream_name_prefix}")

        loop = asyncio.get_event_loop()

        # Find available streams
        stream_names = await loop.run_in_executor(
            None, lambda: self._find_streams(timeout=min(10.0, timeout_seconds))
        )

        # Validate required streams
        if "EEG" not in stream_names:
            raise MultiStreamConnectionError(
                f"EEG stream not found. Is OpenMuse streaming? "
                f"Run: OpenMuse stream --address <muse-address>"
            )

        if self.require_accgyro and "ACCGYRO" not in stream_names:
            raise MultiStreamConnectionError(
                f"ACCGYRO stream not found. Required for ML training. "
                f"Ensure OpenMuse is streaming all sensors."
            )

        # Connect to each stream
        for stream_type in ["EEG", "ACCGYRO", "OPTICS"]:
            if stream_type not in stream_names:
                continue

            if stream_type == "OPTICS" and not self.include_optics:
                continue

            try:
                stream = Stream(
                    bufsize=self.buffer_seconds,
                    name=stream_names[stream_type]
                )

                await asyncio.wait_for(
                    loop.run_in_executor(None, stream.connect),
                    timeout=timeout_seconds
                )

                # Get channel names from stream info
                # Use dict-style access which works with mne-lsl
                ch_names = list(stream.info["ch_names"])

                self._streams[stream_type] = stream
                self._stream_info[stream_type] = StreamInfo(
                    name=stream_names[stream_type],
                    sfreq=stream.info["sfreq"],
                    n_channels=stream.info["nchan"],
                    channel_names=ch_names
                )

                logger.info(
                    f"Connected to {stream_type}: {stream_names[stream_type]} "
                    f"({self._stream_info[stream_type].sfreq} Hz, "
                    f"{self._stream_info[stream_type].n_channels} channels)"
                )

            except asyncio.TimeoutError:
                if stream_type in ["EEG"] or (stream_type == "ACCGYRO" and self.require_accgyro):
                    raise MultiStreamConnectionError(
                        f"Timeout connecting to {stream_type} stream"
                    )
                logger.warning(f"Timeout connecting to optional {stream_type} stream")
            except Exception as e:
                if stream_type in ["EEG"] or (stream_type == "ACCGYRO" and self.require_accgyro):
                    raise MultiStreamConnectionError(
                        f"Failed to connect to {stream_type}: {e}"
                    ) from e
                logger.warning(f"Failed to connect to optional {stream_type}: {e}")

        self._connected = True
        logger.info(f"Connected to {len(self._streams)} stream(s)")

    async def disconnect(self) -> None:
        """Disconnect from all LSL streams."""
        for stream_type, stream in self._streams.items():
            try:
                stream.disconnect()
                logger.debug(f"Disconnected from {stream_type}")
            except Exception as e:
                logger.warning(f"Error disconnecting from {stream_type}: {e}")

        self._streams.clear()
        self._stream_info.clear()
        self._connected = False
        logger.info("Disconnected from all streams")

    def _get_stream_data(self, stream_type: str) -> tuple:
        """
        Get available data from a stream.

        Returns:
            Tuple of (data, timestamps) or (None, None) if no data
        """
        stream = self._streams.get(stream_type)
        if stream is None:
            return None, None

        n_new = stream.n_new_samples
        if n_new == 0:
            return None, None

        sfreq = self._stream_info[stream_type].sfreq
        winsize = n_new / sfreq

        try:
            data, timestamps = stream.get_data(winsize)
            # data shape: (n_channels, n_samples) -> transpose to (n_samples, n_channels)
            return data.T, timestamps
        except Exception as e:
            logger.debug(f"Error getting {stream_type} data: {e}")
            return None, None

    async def stream(self) -> AsyncIterator[StreamChunk]:
        """
        Async generator yielding multi-stream data chunks.

        Yields:
            StreamChunk with EEG, ACCGYRO, and optionally OPTICS data
        """
        if not self._connected:
            raise MultiStreamConnectionError("Not connected. Call connect() first.")

        logger.info("Starting multi-stream capture...")

        while self._connected:
            # Get data from each stream
            eeg_data, eeg_ts = self._get_stream_data("EEG")
            accgyro_data, accgyro_ts = self._get_stream_data("ACCGYRO")
            optics_data, optics_ts = self._get_stream_data("OPTICS")

            # Only yield if we have at least EEG data
            if eeg_data is not None and len(eeg_data) > 0:
                # Use earliest EEG timestamp as chunk timestamp
                chunk_ts = eeg_ts[0] if eeg_ts is not None else 0.0

                yield StreamChunk(
                    timestamp=chunk_ts,
                    eeg=eeg_data,
                    eeg_timestamps=eeg_ts,
                    accgyro=accgyro_data,
                    accgyro_timestamps=accgyro_ts,
                    optics=optics_data,
                    optics_timestamps=optics_ts,
                )

            await asyncio.sleep(self.poll_interval)

    async def __aenter__(self) -> "MultiStreamReceiver":
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Async context manager exit."""
        await self.disconnect()
