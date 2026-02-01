"""LSL stream receiver for OpenMuse EEG data."""

from .lsl_receiver import LSLReceiver, LSLConnectionError

__all__ = ["LSLReceiver", "LSLConnectionError"]
