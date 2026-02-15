"""
Neural network architectures for jaw clench detection.

Uses 1D CNN as the primary architecture - good for temporal patterns
in biosignal data, faster than RNNs, and easier to train.
"""

import logging

import torch
import torch.nn as nn

logger = logging.getLogger("ml.model")


class JawClenchLSTM(nn.Module):
    """
    LSTM-based model for jaw clench detection.

    Alternative to CNN - may capture longer-range dependencies
    but slower to train and run inference.
    """

    def __init__(
        self,
        n_channels: int = 30,  # 8 EEG + 6 ACCGYRO + 16 OPTICS
        hidden_size: int = 64,
        num_layers: int = 2,
        dropout: float = 0.3,
        bidirectional: bool = True
    ):
        super().__init__()

        self.n_channels = n_channels
        self.hidden_size = hidden_size
        self.num_layers = num_layers
        self.bidirectional = bidirectional

        self.lstm = nn.LSTM(
            input_size=n_channels,
            hidden_size=hidden_size,
            num_layers=num_layers,
            batch_first=True,
            dropout=dropout if num_layers > 1 else 0,
            bidirectional=bidirectional
        )

        # Output size depends on bidirectional
        lstm_output_size = hidden_size * 2 if bidirectional else hidden_size

        self.classifier = nn.Sequential(
            nn.Linear(lstm_output_size, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

        total_params = sum(p.numel() for p in self.parameters())
        logger.info(f"JawClenchLSTM initialized: {total_params:,} parameters")

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Forward pass.

        Args:
            x: Input tensor of shape (batch, window_size, n_channels)

        Returns:
            Logits of shape (batch, 1)
        """
        # LSTM forward
        lstm_out, _ = self.lstm(x)

        # Use last hidden state
        last_hidden = lstm_out[:, -1, :]

        # Classifier
        return self.classifier(last_hidden)

    def predict_proba(self, x: torch.Tensor) -> torch.Tensor:
        logits = self.forward(x)
        return torch.sigmoid(logits).squeeze(-1)

    def predict(self, x: torch.Tensor, threshold: float = 0.5) -> torch.Tensor:
        proba = self.predict_proba(x)
        return (proba >= threshold).long()


class JawClenchCNN(nn.Module):
    """
    1D CNN for jaw clench detection from raw Muse sensor data.

    Architecture:
        Input: (batch, window_size=256, channels=30)
        6 convolutional blocks with increasing filter counts
        Global average pooling for position invariance
        Dense layers for classification

    Input channels (30 total):
        - EEG: TP9, AF7, AF8, TP10, AUX1-4 (8 channels)
        - Accelerometer: X, Y, Z (3 channels)
        - Gyroscope: X, Y, Z (3 channels)
        - Optics/PPG: 16 channels (NIR, IR, RED, AMB from 4 sensors)

    ~1.5M parameters for good capacity on modern hardware.
    """

    def __init__(
        self,
        n_channels: int = 30,  # 8 EEG + 6 ACCGYRO + 16 OPTICS
        window_size: int = 256,
        dropout: float = 0.4
    ):
        super().__init__()

        self.n_channels = n_channels
        self.window_size = window_size

        # Initial projection to more channels
        self.input_proj = nn.Sequential(
            nn.Conv1d(n_channels, 64, kernel_size=1),
            nn.BatchNorm1d(64),
            nn.ReLU(),
        )

        # Block 1: 64 -> 64 channels
        self.block1 = self._make_block(64, 64, kernel_size=7)
        self.pool1 = nn.MaxPool1d(2)

        # Block 2: 64 -> 128 channels
        self.block2 = self._make_block(64, 128, kernel_size=5)
        self.pool2 = nn.MaxPool1d(2)

        # Block 3: 128 -> 128 channels
        self.block3 = self._make_block(128, 128, kernel_size=5)
        self.pool3 = nn.MaxPool1d(2)

        # Block 4: 128 -> 256 channels
        self.block4 = self._make_block(128, 256, kernel_size=3)
        self.pool4 = nn.MaxPool1d(2)

        # Block 5: 256 -> 256 channels
        self.block5 = self._make_block(256, 256, kernel_size=3)
        self.pool5 = nn.MaxPool1d(2)

        # Block 6: 256 -> 256 channels
        self.block6 = self._make_block(256, 256, kernel_size=3)

        # Global pooling
        self.global_pool = nn.AdaptiveAvgPool1d(1)

        # Classifier with more capacity
        self.classifier = nn.Sequential(
            nn.Flatten(),
            nn.Linear(256, 128),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(128, 64),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(64, 1),
        )

        self._init_weights()

        total_params = sum(p.numel() for p in self.parameters())
        logger.info(f"JawClenchCNN initialized: {total_params:,} parameters")

    def _make_block(self, in_channels: int, out_channels: int, kernel_size: int) -> nn.Module:
        """Create a convolutional block with residual connection if channels match."""
        return nn.Sequential(
            nn.Conv1d(in_channels, out_channels, kernel_size, padding=kernel_size // 2),
            nn.BatchNorm1d(out_channels),
            nn.ReLU(),
            nn.Conv1d(out_channels, out_channels, kernel_size, padding=kernel_size // 2),
            nn.BatchNorm1d(out_channels),
            nn.ReLU(),
        )

    def _init_weights(self):
        for m in self.modules():
            if isinstance(m, nn.Conv1d):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='relu')
                if m.bias is not None:
                    nn.init.zeros_(m.bias)
            elif isinstance(m, nn.BatchNorm1d):
                nn.init.ones_(m.weight)
                nn.init.zeros_(m.bias)
            elif isinstance(m, nn.Linear):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='relu')
                nn.init.zeros_(m.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # Input: (batch, window_size, n_channels)
        # Conv1d expects: (batch, channels, length)
        x = x.permute(0, 2, 1)

        x = self.input_proj(x)

        x = self.pool1(self.block1(x))
        x = self.pool2(self.block2(x))
        x = self.pool3(self.block3(x))
        x = self.pool4(self.block4(x))
        x = self.pool5(self.block5(x))
        x = self.block6(x)

        x = self.global_pool(x)
        x = self.classifier(x)

        return x

    def predict_proba(self, x: torch.Tensor) -> torch.Tensor:
        logits = self.forward(x)
        return torch.sigmoid(logits).squeeze(-1)

    def predict(self, x: torch.Tensor, threshold: float = 0.5) -> torch.Tensor:
        proba = self.predict_proba(x)
        return (proba >= threshold).long()


def create_model(
    model_type: str = "cnn",
    n_channels: int = 30,  # 8 EEG + 6 ACCGYRO + 16 OPTICS
    window_size: int = 256,
    **kwargs
) -> nn.Module:
    """
    Factory function to create a model.

    Args:
        model_type: Model architecture to use
            - "cnn": 1D CNN (~1.5M params) - good for temporal patterns
            - "lstm": Bidirectional LSTM - captures long-range dependencies
        n_channels: Number of input channels
        window_size: Window size in samples
        **kwargs: Additional model-specific arguments

    Returns:
        Initialized model
    """
    model_type = model_type.lower()

    if model_type == "cnn":
        return JawClenchCNN(n_channels=n_channels, window_size=window_size, **kwargs)
    elif model_type == "lstm":
        return JawClenchLSTM(n_channels=n_channels, **kwargs)
    else:
        raise ValueError(f"Unknown model type: {model_type}. Choose from: cnn, lstm")
