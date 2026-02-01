"""
ML-based jaw clench detection module.

Provides data collection, training, and inference for neural network-based
detection trained on labeled Muse data.
"""

from .streams import MultiStreamReceiver, StreamChunk
from .collect import DataCollector, LabeledSample
from .preprocess import (
    PreprocessedDataset,
    WindowConfig,
    preprocess_sessions,
    train_val_split,
    CHANNEL_NAMES,
)
from .inference import MLInferenceEngine, InferenceResult, load_inference_engine

__all__ = [
    "MultiStreamReceiver",
    "StreamChunk",
    "DataCollector",
    "LabeledSample",
    "PreprocessedDataset",
    "WindowConfig",
    "preprocess_sessions",
    "train_val_split",
    "CHANNEL_NAMES",
    "MLInferenceEngine",
    "InferenceResult",
    "load_inference_engine",
]
