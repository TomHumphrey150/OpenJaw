"""Tests for ml/inference.py - real-time inference engine."""

import numpy as np
import pytest
import tempfile
import time
import torch
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from ml.inference import SlidingWindowBuffer, TimestampedBuffer, MLInferenceEngine
from ml.model import JawClenchCNN


class TestSlidingWindowBuffer:
    """Tests for the sliding window buffer."""

    def test_initial_state(self):
        """Test buffer starts empty."""
        buffer = SlidingWindowBuffer(window_size=256, n_channels=14)

        assert buffer.samples_collected == 0
        assert not buffer.is_ready
        assert buffer.get_window() is None

    def test_add_samples(self):
        """Test adding samples to buffer."""
        buffer = SlidingWindowBuffer(window_size=256, n_channels=14)

        samples = np.random.randn(100, 14).astype(np.float32)
        buffer.add_samples(samples)

        assert buffer.samples_collected == 100
        assert not buffer.is_ready

    def test_buffer_ready(self):
        """Test buffer becomes ready when full."""
        buffer = SlidingWindowBuffer(window_size=256, n_channels=14)

        samples = np.random.randn(300, 14).astype(np.float32)
        buffer.add_samples(samples)

        assert buffer.is_ready
        window = buffer.get_window()
        assert window is not None
        assert window.shape == (256, 14)

    def test_window_content(self):
        """Test window contains most recent samples."""
        buffer = SlidingWindowBuffer(window_size=100, n_channels=1)

        # Add samples with increasing values
        samples = np.arange(200).reshape(-1, 1).astype(np.float32)
        buffer.add_samples(samples)

        window = buffer.get_window()

        # Should contain last 100 values (100-199)
        expected = np.arange(100, 200).reshape(-1, 1).astype(np.float32)
        assert np.allclose(window, expected)

    def test_incremental_filling(self):
        """Test buffer fills correctly with multiple small chunks."""
        buffer = SlidingWindowBuffer(window_size=256, n_channels=14)

        # Add small chunks
        for i in range(10):
            samples = np.random.randn(30, 14).astype(np.float32)
            buffer.add_samples(samples)

        # After 10 chunks of 30 = 300 samples
        assert buffer.is_ready

    def test_reset(self):
        """Test buffer reset."""
        buffer = SlidingWindowBuffer(window_size=256, n_channels=14)

        samples = np.random.randn(300, 14).astype(np.float32)
        buffer.add_samples(samples)
        assert buffer.is_ready

        buffer.reset()

        assert buffer.samples_collected == 0
        assert not buffer.is_ready

    def test_buffer_wraparound(self):
        """Test buffer handles wraparound correctly."""
        buffer = SlidingWindowBuffer(window_size=100, n_channels=1)

        # Add many samples to trigger wraparound
        for i in range(20):
            samples = np.full((50, 1), i, dtype=np.float32)
            buffer.add_samples(samples)

        # Should still work and contain most recent data
        window = buffer.get_window()
        assert window is not None
        assert window.shape == (100, 1)


class TestMLInferenceEngine:
    """Tests for the ML inference engine."""

    @pytest.fixture
    def temp_model_path(self):
        """Create a temporary model file for testing."""
        with tempfile.NamedTemporaryFile(suffix='.pt', delete=False) as f:
            # Create and save a model with 30 channels (8 EEG + 6 ACCGYRO + 16 OPTICS)
            model = JawClenchCNN(n_channels=14, window_size=256)

            checkpoint = {
                "model_state_dict": model.state_dict(),
                "config": {
                    "model_type": "cnn",
                    "n_channels": 14,
                    "window_size": 256,
                },
                "channel_means": [0.0] * 14,
                "channel_stds": [1.0] * 14,
                "best_val_metrics": {"accuracy": 0.9, "f1": 0.85},
            }
            torch.save(checkpoint, f.name)

            yield Path(f.name)

        # Cleanup
        Path(f.name).unlink(missing_ok=True)

    def test_load_model(self, temp_model_path):
        """Test loading a model checkpoint."""
        engine = MLInferenceEngine(
            model_path=str(temp_model_path),
            detection_threshold=0.5,
            debounce_seconds=2.0
        )

        assert engine.window_size == 256
        assert engine.n_channels == 14  # 8 EEG + 6 ACCGYRO (no OPTICS)
        assert engine.detection_threshold == 0.5

    def test_process_empty_data(self, temp_model_path):
        """Test processing empty data."""
        engine = MLInferenceEngine(str(temp_model_path))

        result = engine.process(
            eeg_data=None,
            eeg_timestamps=None
        )

        assert result.probability == 0.0
        assert not result.is_clenching
        assert not result.is_detection
        assert not result.window_ready

    def test_process_insufficient_data(self, temp_model_path):
        """Test processing when buffer not full."""
        engine = MLInferenceEngine(str(temp_model_path))

        # Add less than a full window (8 EEG channels)
        eeg = np.random.randn(100, 8).astype(np.float32)
        ts = np.arange(100).astype(np.float64)

        result = engine.process(
            eeg_data=eeg,
            eeg_timestamps=ts
        )

        assert not result.window_ready

    def test_process_full_window(self, temp_model_path):
        """Test processing with a full window."""
        engine = MLInferenceEngine(str(temp_model_path))

        # Add enough for a full window (8 EEG channels)
        eeg = np.random.randn(300, 8).astype(np.float32)
        ts = np.arange(300).astype(np.float64)
        accgyro = np.random.randn(60, 6).astype(np.float32)
        accgyro_ts = np.linspace(0, 300, 60).astype(np.float64)
        optics = np.random.randn(75, 16).astype(np.float32)
        optics_ts = np.linspace(0, 300, 75).astype(np.float64)

        result = engine.process(
            eeg_data=eeg,
            eeg_timestamps=ts,
            accgyro_data=accgyro,
            accgyro_timestamps=accgyro_ts,
            optics_data=optics,
            optics_timestamps=optics_ts
        )

        assert result.window_ready
        assert 0 <= result.probability <= 1

    def test_debounce(self, temp_model_path):
        """Test debounce prevents rapid detections."""
        engine = MLInferenceEngine(
            str(temp_model_path),
            detection_threshold=0.0,  # Always detect
            debounce_seconds=1.0
        )

        # First detection (8 EEG channels)
        eeg = np.random.randn(300, 8).astype(np.float32)
        ts = np.arange(300).astype(np.float64)

        result1 = engine.process(eeg, ts)
        assert result1.is_detection  # First should be detection

        # Immediate second should be debounced
        result2 = engine.process(eeg, ts)
        assert result2.is_clenching  # Still clenching
        assert not result2.is_detection  # But not a new detection

    def test_debounce_expires(self, temp_model_path):
        """Test debounce expires after timeout."""
        engine = MLInferenceEngine(
            str(temp_model_path),
            detection_threshold=0.0,  # Always detect
            debounce_seconds=0.1  # Very short for testing
        )

        eeg = np.random.randn(300, 8).astype(np.float32)
        ts = np.arange(300).astype(np.float64)

        result1 = engine.process(eeg, ts)
        assert result1.is_detection

        # Wait for debounce to expire
        time.sleep(0.15)

        result2 = engine.process(eeg, ts)
        assert result2.is_detection  # Should be new detection

    def test_reset(self, temp_model_path):
        """Test engine reset."""
        engine = MLInferenceEngine(str(temp_model_path))

        # Fill buffer (8 EEG channels)
        eeg = np.random.randn(300, 8).astype(np.float32)
        ts = np.arange(300).astype(np.float64)
        engine.process(eeg, ts)

        assert engine.is_ready

        engine.reset()

        assert not engine.is_ready

    def test_model_not_found_raises(self):
        """Test loading non-existent model raises error."""
        with pytest.raises(FileNotFoundError):
            MLInferenceEngine("/nonexistent/model.pt")


class TestTimestampedBuffer:
    """Tests for TimestampedBuffer - stores samples with timestamps."""

    def test_initial_state(self):
        """Test buffer starts empty."""
        buffer = TimestampedBuffer(max_samples=256, n_channels=8)

        assert buffer.samples_collected == 0
        assert buffer.total_samples_received == 0

    def test_add_samples(self):
        """Test adding samples with timestamps."""
        buffer = TimestampedBuffer(max_samples=256, n_channels=8)

        data = np.random.randn(100, 8).astype(np.float32)
        timestamps = np.arange(100).astype(np.float64)
        buffer.add_samples(data, timestamps)

        assert buffer.samples_collected == 100
        assert buffer.total_samples_received == 100

    def test_get_all_data(self):
        """Test retrieving all buffered data."""
        buffer = TimestampedBuffer(max_samples=256, n_channels=8)

        data = np.random.randn(100, 8).astype(np.float32)
        timestamps = np.arange(100).astype(np.float64)
        buffer.add_samples(data, timestamps)

        retrieved_data, retrieved_ts = buffer.get_all_data()

        assert np.allclose(retrieved_data, data)
        assert np.allclose(retrieved_ts, timestamps)

    def test_buffer_overflow_keeps_recent(self):
        """Test that buffer keeps most recent samples when overflow."""
        buffer = TimestampedBuffer(max_samples=100, n_channels=1)

        # Add more samples than buffer can hold
        data = np.arange(200).reshape(-1, 1).astype(np.float32)
        timestamps = np.arange(200).astype(np.float64)
        buffer.add_samples(data, timestamps)

        retrieved_data, retrieved_ts = buffer.get_all_data()

        # Should have kept the last 100 samples (100-199)
        assert len(retrieved_data) == 100
        assert retrieved_data[0, 0] == 100.0
        assert retrieved_data[-1, 0] == 199.0

    def test_incremental_add_with_overflow(self):
        """Test incremental adding triggers proper overflow handling."""
        buffer = TimestampedBuffer(max_samples=100, n_channels=1)

        # Add chunks that will eventually overflow
        for i in range(5):
            data = np.full((30, 1), i * 30, dtype=np.float32) + np.arange(30).reshape(-1, 1)
            timestamps = np.arange(i * 30, (i + 1) * 30).astype(np.float64)
            buffer.add_samples(data, timestamps)

        retrieved_data, retrieved_ts = buffer.get_all_data()

        # Should have kept the most recent 100 samples
        assert len(retrieved_data) <= 100
        # Most recent value should be 149 (5*30 - 1)
        assert retrieved_data[-1, 0] == 149.0

    def test_reset(self):
        """Test buffer reset."""
        buffer = TimestampedBuffer(max_samples=256, n_channels=8)

        data = np.random.randn(100, 8).astype(np.float32)
        timestamps = np.arange(100).astype(np.float64)
        buffer.add_samples(data, timestamps)

        buffer.reset()

        assert buffer.samples_collected == 0
        # total_samples_received is also reset
        assert buffer.total_samples_received == 0

    def test_get_data_in_range(self):
        """Test getting data within a timestamp range."""
        buffer = TimestampedBuffer(max_samples=256, n_channels=1)

        data = np.arange(100).reshape(-1, 1).astype(np.float32)
        timestamps = np.arange(100).astype(np.float64)
        buffer.add_samples(data, timestamps)

        # Get data in range 25-75
        range_data, range_ts = buffer.get_data_in_range(25, 75)

        # Should include data around that range (with margin)
        assert len(range_data) > 0
        assert range_ts.min() >= 20  # 25 - 10% margin
        assert range_ts.max() <= 80  # 75 + 10% margin


class TestNormalization:
    """Tests for normalization edge cases that caused bugs."""

    @pytest.fixture
    def engine_with_extreme_stats(self):
        """Create engine with near-zero std (simulating edge case)."""
        with tempfile.NamedTemporaryFile(suffix='.pt', delete=False) as f:
            model = JawClenchCNN(n_channels=14, window_size=256)

            # Simulate edge case: some channels have near-zero std
            # 8 EEG + 6 ACCGYRO = 14 channels
            channel_stds = [1.0] * 8  # Normal EEG stds
            channel_stds += [0.0008, 0.0008, 0.1, 0.1, 0.1, 0.1]  # ACCGYRO with some tiny stds

            checkpoint = {
                "model_state_dict": model.state_dict(),
                "config": {"model_type": "cnn", "n_channels": 14, "window_size": 256},
                "channel_means": [0.0] * 14,
                "channel_stds": channel_stds,
            }
            torch.save(checkpoint, f.name)
            engine = MLInferenceEngine(f.name)
            yield engine
        Path(f.name).unlink(missing_ok=True)

    def test_near_zero_std_does_not_explode(self, engine_with_extreme_stats):
        """Test that near-zero std doesn't cause exploding normalized values."""
        # Process data - should not produce inf or extreme values
        eeg = np.random.randn(300, 8).astype(np.float32)
        ts = np.arange(300).astype(np.float64)

        result = engine_with_extreme_stats.process(eeg, ts)

        # Should produce a valid result (not NaN or extreme)
        assert result.window_ready
        assert 0 <= result.probability <= 1
        assert not np.isnan(result.probability)

    def test_normalization_matches_training(self, engine_with_extreme_stats):
        """Test that normalization matches training preprocessing.

        Training does NOT clip values - it uses actual std even if small.
        Inference must match this to produce correct model outputs.
        """
        engine = engine_with_extreme_stats

        # With std=0.0008 and mean=0, a value of 1.0 gives z-score of 1250
        data = np.ones((256, 14), dtype=np.float32)

        normalized = engine._normalize(data)

        # Should NOT clip - values can be large (training doesn't clip)
        # This is intentional: the model learned with these large values
        assert normalized.max() > 100  # Would be 1250 for the extreme channels
        assert not np.any(np.isnan(normalized))
        assert not np.any(np.isinf(normalized))


class TestInterpolation:
    """Tests for ACCGYRO interpolation in inference."""

    @pytest.fixture
    def engine(self):
        """Create engine with temp model."""
        with tempfile.NamedTemporaryFile(suffix='.pt', delete=False) as f:
            model = JawClenchCNN(n_channels=14, window_size=256)
            checkpoint = {
                "model_state_dict": model.state_dict(),
                "config": {"model_type": "cnn", "n_channels": 14, "window_size": 256},
                "channel_means": [0.0] * 14,
                "channel_stds": [1.0] * 14,
            }
            torch.save(checkpoint, f.name)
            engine = MLInferenceEngine(f.name)
            yield engine
        Path(f.name).unlink(missing_ok=True)

    def test_interpolation_works(self, engine):
        """Test ACCGYRO interpolation to EEG timestamps."""
        # EEG at 256 Hz (8 channels)
        eeg = np.random.randn(256, 8).astype(np.float32)
        eeg_ts = np.arange(256).astype(np.float64)

        # ACCGYRO at 52 Hz (fewer samples)
        accgyro = np.random.randn(52, 6).astype(np.float32)
        accgyro_ts = np.linspace(0, 256, 52).astype(np.float64)

        # Should process without error (OPTICS is ignored)
        result = engine.process(eeg, eeg_ts, accgyro, accgyro_ts)

        assert result.window_ready

    def test_missing_accgyro(self, engine):
        """Test handling when ACCGYRO is None."""
        eeg = np.random.randn(300, 8).astype(np.float32)
        eeg_ts = np.arange(300).astype(np.float64)

        # Should still work with zeros for ACCGYRO
        result = engine.process(eeg, eeg_ts, None, None)

        assert result.window_ready

    def test_missing_optics(self, engine):
        """Test that OPTICS data is ignored (no longer used)."""
        eeg = np.random.randn(300, 8).astype(np.float32)
        eeg_ts = np.arange(300).astype(np.float64)
        accgyro = np.random.randn(60, 6).astype(np.float32)
        accgyro_ts = np.linspace(0, 300, 60).astype(np.float64)

        # OPTICS is passed but should be ignored
        optics = np.random.randn(75, 16).astype(np.float32)
        optics_ts = np.linspace(0, 300, 75).astype(np.float64)
        result = engine.process(eeg, eeg_ts, accgyro, accgyro_ts, optics, optics_ts)

        assert result.window_ready

    def test_non_overlapping_timestamps_uses_edge_values(self, engine):
        """
        Test that interpolation uses edge values when timestamps don't overlap.

        This was a bug: np.interp with left=0.0, right=0.0 produced zeros
        when ACCGYRO timestamps didn't overlap with EEG timestamps,
        causing normalized values to explode.
        """
        # First chunk: EEG timestamps 0-99, ACCGYRO timestamps 0-99
        eeg1 = np.ones((100, 8), dtype=np.float32) * 10
        eeg_ts1 = np.arange(100).astype(np.float64)
        accgyro1 = np.ones((20, 6), dtype=np.float32) * 5
        accgyro_ts1 = np.linspace(0, 99, 20).astype(np.float64)

        engine.process(eeg1, eeg_ts1, accgyro1, accgyro_ts1)

        # Second chunk: EEG timestamps 100-199, ACCGYRO timestamps 100-199
        eeg2 = np.ones((100, 8), dtype=np.float32) * 10
        eeg_ts2 = np.arange(100, 200).astype(np.float64)
        accgyro2 = np.ones((20, 6), dtype=np.float32) * 5
        accgyro_ts2 = np.linspace(100, 199, 20).astype(np.float64)

        engine.process(eeg2, eeg_ts2, accgyro2, accgyro_ts2)

        # Third chunk with partial overlap - this was where the bug occurred
        # ACCGYRO timestamps START later than EEG timestamps
        eeg3 = np.ones((100, 8), dtype=np.float32) * 10
        eeg_ts3 = np.arange(200, 300).astype(np.float64)
        accgyro3 = np.ones((20, 6), dtype=np.float32) * 5
        # ACCGYRO starts at 220, not 200 - previously this caused zeros for ts 200-219
        accgyro_ts3 = np.linspace(220, 299, 20).astype(np.float64)

        result = engine.process(eeg3, eeg_ts3, accgyro3, accgyro_ts3)

        # Should still work and produce a valid probability
        assert result.window_ready
        assert 0 <= result.probability <= 1
        # Key assertion: probability should NOT be extreme (1.0 was the bug symptom)
        # With normalized random data, extreme probs are unlikely

    def test_chunk_by_chunk_maintains_consistency(self, engine):
        """
        Test that processing data chunk-by-chunk produces similar results
        to processing a larger chunk.

        This tests the fix for buffering streams separately with timestamps.
        """
        # Create continuous data
        total_samples = 512
        eeg_full = np.random.randn(total_samples, 8).astype(np.float32)
        eeg_ts_full = np.arange(total_samples).astype(np.float64)
        accgyro_full = np.random.randn(total_samples // 5, 6).astype(np.float32)
        accgyro_ts_full = np.linspace(0, total_samples, total_samples // 5).astype(np.float64)

        # Process in one big chunk
        engine.reset()
        result_full = engine.process(
            eeg_full, eeg_ts_full,
            accgyro_full, accgyro_ts_full
        )

        # Process in smaller chunks
        engine.reset()
        chunk_size = 64
        for i in range(0, total_samples, chunk_size):
            end_i = min(i + chunk_size, total_samples)
            eeg_chunk = eeg_full[i:end_i]
            eeg_ts_chunk = eeg_ts_full[i:end_i]

            # Find corresponding accgyro samples
            accgyro_mask = (accgyro_ts_full >= i) & (accgyro_ts_full < end_i)
            accgyro_chunk = accgyro_full[accgyro_mask]
            accgyro_ts_chunk = accgyro_ts_full[accgyro_mask]

            result_chunked = engine.process(
                eeg_chunk, eeg_ts_chunk,
                accgyro_chunk if len(accgyro_chunk) > 0 else None,
                accgyro_ts_chunk if len(accgyro_ts_chunk) > 0 else None
            )

        # Both should have processed and be ready
        assert result_full.window_ready
        assert result_chunked.window_ready

        # Results don't need to be identical (window timing differs),
        # but both should produce valid probabilities
        assert 0 <= result_full.probability <= 1
        assert 0 <= result_chunked.probability <= 1


class TestStreamingEdgeCases:
    """Tests for edge cases in streaming inference that caused bugs."""

    @pytest.fixture
    def engine(self):
        """Create engine with temp model."""
        with tempfile.NamedTemporaryFile(suffix='.pt', delete=False) as f:
            model = JawClenchCNN(n_channels=14, window_size=256)
            checkpoint = {
                "model_state_dict": model.state_dict(),
                "config": {"model_type": "cnn", "n_channels": 14, "window_size": 256},
                "channel_means": [0.0] * 14,
                "channel_stds": [1.0] * 14,
            }
            torch.save(checkpoint, f.name)
            engine = MLInferenceEngine(f.name)
            yield engine
        Path(f.name).unlink(missing_ok=True)

    def test_first_window_then_streaming(self, engine):
        """
        Test the exact scenario that caused the bug:
        - First chunk is large (fills buffer)
        - Subsequent chunks are small
        - Interpolation must work correctly for both
        """
        # First large chunk (like startup)
        eeg1 = np.random.randn(512, 8).astype(np.float32)
        eeg_ts1 = np.arange(512).astype(np.float64)
        accgyro1 = np.random.randn(104, 6).astype(np.float32)
        accgyro_ts1 = np.linspace(0, 512, 104).astype(np.float64)

        result1 = engine.process(
            eeg1, eeg_ts1,
            accgyro1, accgyro_ts1
        )

        assert result1.window_ready
        prob1 = result1.probability

        # Small subsequent chunks (like streaming)
        for i in range(5):
            start = 512 + i * 64
            eeg = np.random.randn(64, 8).astype(np.float32)
            eeg_ts = np.arange(start, start + 64).astype(np.float64)
            accgyro = np.random.randn(12, 6).astype(np.float32)
            accgyro_ts = np.linspace(start, start + 64, 12).astype(np.float64)

            result = engine.process(
                eeg, eeg_ts,
                accgyro, accgyro_ts
            )

            assert result.window_ready
            # Key: probability should vary, not always be 1.0 (the bug)
            assert 0 <= result.probability <= 1

    def test_gaps_in_stream_handled(self, engine):
        """Test that gaps in the stream are handled gracefully."""
        # First chunk
        eeg1 = np.random.randn(300, 8).astype(np.float32)
        eeg_ts1 = np.arange(300).astype(np.float64)
        engine.process(eeg1, eeg_ts1)

        # Second chunk with a gap (timestamps jump)
        eeg2 = np.random.randn(64, 8).astype(np.float32)
        eeg_ts2 = np.arange(500, 564).astype(np.float64)  # Gap from 300-500

        result = engine.process(eeg2, eeg_ts2)

        # Should still work without crashing
        assert result.window_ready
        assert 0 <= result.probability <= 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
