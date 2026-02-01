"""Tests for ml/model.py - neural network architectures."""

import numpy as np
import pytest
import torch

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from ml.model import JawClenchCNN, JawClenchLSTM, create_model


class TestJawClenchCNN:
    """Tests for the CNN model."""

    def test_forward_shape(self):
        """Test output shape is correct."""
        model = JawClenchCNN(n_channels=30, window_size=256)
        x = torch.randn(8, 256, 30)  # batch=8, window=256, channels=10

        output = model(x)

        assert output.shape == (8, 1)

    def test_predict_proba_range(self):
        """Test probability output is in [0, 1]."""
        model = JawClenchCNN()
        x = torch.randn(4, 256, 30)

        proba = model.predict_proba(x)

        assert proba.shape == (4,)
        assert torch.all(proba >= 0)
        assert torch.all(proba <= 1)

    def test_predict_binary(self):
        """Test binary prediction output."""
        model = JawClenchCNN()
        x = torch.randn(4, 256, 30)

        preds = model.predict(x, threshold=0.5)

        assert preds.shape == (4,)
        assert torch.all((preds == 0) | (preds == 1))

    def test_parameter_count(self):
        """Test CNN model has expected parameter count (~1.5M)."""
        model = JawClenchCNN()
        n_params = sum(p.numel() for p in model.parameters())

        # CNN is ~1.5M params (6 conv blocks with up to 256 channels)
        assert 1000000 < n_params < 2000000

    def test_different_batch_sizes(self):
        """Test model works with different batch sizes."""
        model = JawClenchCNN()

        for batch_size in [1, 4, 16, 32]:
            x = torch.randn(batch_size, 256, 30)
            output = model(x)
            assert output.shape == (batch_size, 1)


class TestJawClenchLSTM:
    """Tests for the LSTM model."""

    def test_forward_shape(self):
        """Test output shape is correct."""
        model = JawClenchLSTM(n_channels=30)
        x = torch.randn(8, 256, 30)

        output = model(x)

        assert output.shape == (8, 1)

    def test_predict_proba_range(self):
        """Test probability output is in [0, 1]."""
        model = JawClenchLSTM()
        x = torch.randn(4, 256, 30)

        proba = model.predict_proba(x)

        assert proba.shape == (4,)
        assert torch.all(proba >= 0)
        assert torch.all(proba <= 1)


class TestCreateModel:
    """Tests for model factory function."""

    def test_create_cnn(self):
        """Test creating CNN model."""
        model = create_model("cnn")
        assert isinstance(model, JawClenchCNN)

    def test_create_lstm(self):
        """Test creating LSTM model."""
        model = create_model("lstm")
        assert isinstance(model, JawClenchLSTM)

    def test_create_unknown_raises(self):
        """Test that unknown model type raises error."""
        with pytest.raises(ValueError):
            create_model("unknown_model")

    def test_case_insensitive(self):
        """Test that model type is case-insensitive."""
        model1 = create_model("CNN")
        model2 = create_model("cnn")
        model3 = create_model("Cnn")

        assert type(model1) == type(model2) == type(model3)


class TestModelGradients:
    """Tests for model training capability."""

    def test_cnn_gradients_flow(self):
        """Test that gradients flow through CNN."""
        model = JawClenchCNN()
        x = torch.randn(4, 256, 30)
        y = torch.tensor([[1.0], [0.0], [1.0], [0.0]])

        output = model(x)
        loss = torch.nn.functional.binary_cross_entropy_with_logits(output, y)
        loss.backward()

        # Check gradients exist and are non-zero
        for name, param in model.named_parameters():
            if param.requires_grad:
                assert param.grad is not None, f"No gradient for {name}"
                assert not torch.all(param.grad == 0), f"Zero gradient for {name}"

    def test_lstm_gradients_flow(self):
        """Test that gradients flow through LSTM."""
        model = JawClenchLSTM()
        x = torch.randn(4, 256, 30)
        y = torch.tensor([[1.0], [0.0], [1.0], [0.0]])

        output = model(x)
        loss = torch.nn.functional.binary_cross_entropy_with_logits(output, y)
        loss.backward()

        # Check gradients exist
        for name, param in model.named_parameters():
            if param.requires_grad:
                assert param.grad is not None, f"No gradient for {name}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
