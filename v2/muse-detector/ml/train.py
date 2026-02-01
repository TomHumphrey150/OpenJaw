"""
Training pipeline for jaw clench detection model.

Handles:
- Loading and preprocessing parquet sessions
- Train/val split (by session to avoid leakage)
- Training with early stopping
- Model checkpointing and saving
"""

import json
import logging
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from .model import create_model
from .preprocess import (
    CHANNEL_NAMES,
    EEG_ACCGYRO_CHANNELS,
    PreprocessedDataset,
    WindowConfig,
    preprocess_sessions,
    train_val_split,
)

logger = logging.getLogger("ml.train")


@dataclass
class TrainingConfig:
    """Configuration for training."""
    # Model
    model_type: str = "cnn"
    n_channels: int = 14  # 8 EEG + 6 ACCGYRO (no OPTICS)
    window_size: int = 256

    # Training
    batch_size: int = 32
    learning_rate: float = 1e-3
    weight_decay: float = 1e-4
    max_epochs: int = 100
    early_stopping_patience: int = 10

    # Data
    val_ratio: float = 0.2
    stratify_by_session: bool = True

    # Preprocessing
    window_stride: int = 128
    min_positive_ratio: float = 0.5

    # Class balancing
    use_class_weights: bool = True

    # Channel selection (None = all channels)
    channels: Optional[List[str]] = None

    # Data augmentation
    augment: bool = False
    augment_multiplier: int = 10


@dataclass
class TrainingResult:
    """Result from training run."""
    best_epoch: int
    best_val_loss: float
    best_val_accuracy: float
    best_val_f1: float
    train_losses: List[float]
    val_losses: List[float]
    val_accuracies: List[float]
    model_path: str
    config: Dict


class EarlyStopping:
    """Early stopping to prevent overfitting."""

    def __init__(self, patience: int = 10, min_delta: float = 0.0):
        self.patience = patience
        self.min_delta = min_delta
        self.counter = 0
        self.best_loss = float('inf')
        self.should_stop = False

    def __call__(self, val_loss: float) -> bool:
        if val_loss < self.best_loss - self.min_delta:
            self.best_loss = val_loss
            self.counter = 0
        else:
            self.counter += 1
            if self.counter >= self.patience:
                self.should_stop = True
        return self.should_stop


def compute_class_weights(y: np.ndarray) -> torch.Tensor:
    """Compute class weights for imbalanced data."""
    n_samples = len(y)
    n_positive = np.sum(y)
    n_negative = n_samples - n_positive

    # Inverse frequency weighting
    weight_positive = n_samples / (2 * n_positive) if n_positive > 0 else 1.0
    weight_negative = n_samples / (2 * n_negative) if n_negative > 0 else 1.0

    # Return weight for positive class (used with BCEWithLogitsLoss)
    return torch.tensor([weight_positive / weight_negative], dtype=torch.float32)


def compute_metrics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    y_proba: Optional[np.ndarray] = None
) -> Dict[str, float]:
    """Compute classification metrics."""
    tp = np.sum((y_true == 1) & (y_pred == 1))
    tn = np.sum((y_true == 0) & (y_pred == 0))
    fp = np.sum((y_true == 0) & (y_pred == 1))
    fn = np.sum((y_true == 1) & (y_pred == 0))

    accuracy = (tp + tn) / len(y_true) if len(y_true) > 0 else 0
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    return {
        "accuracy": accuracy,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "tp": int(tp),
        "tn": int(tn),
        "fp": int(fp),
        "fn": int(fn),
    }


def create_dataloaders(
    train_dataset: PreprocessedDataset,
    val_dataset: PreprocessedDataset,
    batch_size: int = 32
) -> Tuple[DataLoader, DataLoader]:
    """Create PyTorch DataLoaders from preprocessed datasets."""
    if train_dataset.n_windows == 0 or val_dataset.n_windows == 0:
        raise ValueError(
            "Cannot create dataloaders with empty datasets. "
            f"Train={train_dataset.n_windows}, Val={val_dataset.n_windows}."
        )

    effective_batch_size = min(batch_size, train_dataset.n_windows)
    drop_last = train_dataset.n_windows >= effective_batch_size

    # Convert to tensors
    X_train = torch.tensor(train_dataset.X, dtype=torch.float32)
    y_train = torch.tensor(train_dataset.y, dtype=torch.float32)
    X_val = torch.tensor(val_dataset.X, dtype=torch.float32)
    y_val = torch.tensor(val_dataset.y, dtype=torch.float32)

    train_loader = DataLoader(
        TensorDataset(X_train, y_train),
        batch_size=effective_batch_size,
        shuffle=True,
        drop_last=drop_last
    )

    val_loader = DataLoader(
        TensorDataset(X_val, y_val),
        batch_size=min(batch_size, val_dataset.n_windows),
        shuffle=False
    )

    return train_loader, val_loader


def train_epoch(
    model: nn.Module,
    train_loader: DataLoader,
    criterion: nn.Module,
    optimizer: torch.optim.Optimizer,
    device: torch.device
) -> float:
    """Train for one epoch."""
    model.train()
    total_loss = 0.0

    for X_batch, y_batch in train_loader:
        X_batch = X_batch.to(device)
        y_batch = y_batch.to(device).unsqueeze(1)

        optimizer.zero_grad()
        logits = model(X_batch)
        loss = criterion(logits, y_batch)
        loss.backward()
        optimizer.step()

        total_loss += loss.item()

    if len(train_loader) == 0:
        raise ValueError("Training loader is empty. Check dataset size and batch_size.")
    return total_loss / len(train_loader)


def evaluate(
    model: nn.Module,
    val_loader: DataLoader,
    criterion: nn.Module,
    device: torch.device
) -> Tuple[float, Dict[str, float]]:
    """Evaluate model on validation set."""
    model.eval()
    total_loss = 0.0
    all_preds = []
    all_proba = []
    all_labels = []

    with torch.no_grad():
        for X_batch, y_batch in val_loader:
            X_batch = X_batch.to(device)
            y_batch = y_batch.to(device).unsqueeze(1)

            logits = model(X_batch)
            loss = criterion(logits, y_batch)
            total_loss += loss.item()

            proba = torch.sigmoid(logits).squeeze(-1)
            preds = (proba >= 0.5).long()

            all_preds.extend(preds.cpu().numpy())
            all_proba.extend(proba.cpu().numpy())
            all_labels.extend(y_batch.squeeze(-1).cpu().numpy())

    if len(val_loader) == 0:
        raise ValueError("Validation loader is empty. Check dataset size and val_ratio.")
    avg_loss = total_loss / len(val_loader)
    metrics = compute_metrics(
        np.array(all_labels),
        np.array(all_preds),
        np.array(all_proba)
    )

    return avg_loss, metrics


def train_model(
    parquet_paths: List[Path],
    output_path: Path,
    config: Optional[TrainingConfig] = None,
    device: Optional[torch.device] = None
) -> TrainingResult:
    """
    Full training pipeline.

    Args:
        parquet_paths: Paths to parquet session files
        output_path: Path to save trained model
        config: Training configuration
        device: PyTorch device (auto-detected if None)

    Returns:
        TrainingResult with metrics and model path
    """
    if config is None:
        config = TrainingConfig()

    if device is None:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    logger.info(f"Training on device: {device}")
    logger.info(f"Configuration: {config}")

    # Preprocess data
    logger.info("")
    logger.info("=" * 60)
    logger.info("PREPROCESSING")
    logger.info("=" * 60)

    window_config = WindowConfig(
        window_size_samples=config.window_size,
        stride_samples=config.window_stride,
        min_positive_ratio=config.min_positive_ratio
    )

    # Determine channels to use (default: EEG + ACCGYRO, no OPTICS)
    channels = config.channels if config.channels else EEG_ACCGYRO_CHANNELS
    n_channels = len(channels)
    config.n_channels = n_channels
    logger.info(f"Using {n_channels} channels: {channels[0]}...{channels[-1]}")

    dataset = preprocess_sessions(parquet_paths, window_config, channels=channels)

    # Split data
    train_dataset, val_dataset = train_val_split(
        dataset,
        val_ratio=config.val_ratio,
        stratify_by_session=config.stratify_by_session
    )
    if train_dataset.n_windows == 0 or val_dataset.n_windows == 0:
        raise ValueError(
            "Train/val split produced an empty set. "
            "Collect more data or adjust val_ratio."
        )

    # Apply data augmentation to training set only
    if config.augment:
        from .augment import augment_dataset
        original_count = len(train_dataset.X)
        train_dataset.X, train_dataset.y = augment_dataset(
            train_dataset.X, train_dataset.y, config.augment_multiplier
        )
        logger.info(f"Augmented training set: {original_count} -> {train_dataset.n_windows} windows (x{config.augment_multiplier})")

    # Create dataloaders
    train_loader, val_loader = create_dataloaders(
        train_dataset, val_dataset, config.batch_size
    )

    # Create model
    logger.info("")
    logger.info("=" * 60)
    logger.info("MODEL")
    logger.info("=" * 60)

    model = create_model(
        model_type=config.model_type,
        n_channels=config.n_channels,
        window_size=config.window_size
    )
    model = model.to(device)

    # Loss function with class weights
    if config.use_class_weights:
        pos_weight = compute_class_weights(train_dataset.y).to(device)
        criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)
        logger.info(f"Using class weights: pos_weight={pos_weight.item():.2f}")
    else:
        criterion = nn.BCEWithLogitsLoss()

    # Optimizer
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=config.learning_rate,
        weight_decay=config.weight_decay
    )

    # Learning rate scheduler
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode='min', factor=0.5, patience=5
    )

    # Early stopping
    early_stopping = EarlyStopping(patience=config.early_stopping_patience)

    # Training loop
    logger.info("")
    logger.info("=" * 60)
    logger.info("TRAINING")
    logger.info("=" * 60)

    train_losses = []
    val_losses = []
    val_accuracies = []
    best_val_loss = float('inf')
    best_val_metrics = {}
    best_epoch = 0
    best_state_dict = None

    for epoch in range(config.max_epochs):
        train_loss = train_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_metrics = evaluate(model, val_loader, criterion, device)

        train_losses.append(train_loss)
        val_losses.append(val_loss)
        val_accuracies.append(val_metrics["accuracy"])

        scheduler.step(val_loss)

        # Check for best model
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            best_val_metrics = val_metrics
            best_epoch = epoch
            best_state_dict = model.state_dict().copy()

        # Logging
        logger.info(
            f"Epoch {epoch+1:3d}: "
            f"train_loss={train_loss:.4f}, "
            f"val_loss={val_loss:.4f}, "
            f"val_acc={val_metrics['accuracy']:.3f}, "
            f"val_f1={val_metrics['f1']:.3f}"
        )

        # Early stopping
        if early_stopping(val_loss):
            logger.info(f"Early stopping triggered at epoch {epoch+1}")
            break

    # Load best model
    model.load_state_dict(best_state_dict)

    # Save model and metadata
    logger.info("")
    logger.info("=" * 60)
    logger.info("SAVING MODEL")
    logger.info("=" * 60)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Save model checkpoint
    checkpoint = {
        "model_state_dict": model.state_dict(),
        "config": asdict(config),
        "channel_means": dataset.channel_means.tolist(),
        "channel_stds": dataset.channel_stds.tolist(),
        "channel_names": channels,  # Save channel list for inference
        "best_epoch": best_epoch,
        "best_val_metrics": best_val_metrics,
    }
    torch.save(checkpoint, output_path)
    logger.info(f"Model saved to: {output_path}")

    # Save training metadata as JSON
    metadata_path = output_path.with_suffix(".json")
    metadata = {
        "config": asdict(config),
        "best_epoch": best_epoch,
        "best_val_loss": best_val_loss,
        "best_val_metrics": best_val_metrics,
        "train_sessions": sorted(set(train_dataset.session_ids)),
        "val_sessions": sorted(set(val_dataset.session_ids)),
        "n_train_windows": train_dataset.n_windows,
        "n_val_windows": val_dataset.n_windows,
        "channel_means": dataset.channel_means.tolist(),
        "channel_stds": dataset.channel_stds.tolist(),
        "channel_names": channels,
    }
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)
    logger.info(f"Metadata saved to: {metadata_path}")

    # Summary
    logger.info("")
    logger.info("=" * 60)
    logger.info("TRAINING COMPLETE")
    logger.info(f"  Best epoch: {best_epoch + 1}")
    logger.info(f"  Best val loss: {best_val_loss:.4f}")
    logger.info(f"  Best val accuracy: {best_val_metrics['accuracy']:.3f}")
    logger.info(f"  Best val F1: {best_val_metrics['f1']:.3f}")
    logger.info(f"  Best val precision: {best_val_metrics['precision']:.3f}")
    logger.info(f"  Best val recall: {best_val_metrics['recall']:.3f}")
    logger.info("=" * 60)

    return TrainingResult(
        best_epoch=best_epoch,
        best_val_loss=best_val_loss,
        best_val_accuracy=best_val_metrics["accuracy"],
        best_val_f1=best_val_metrics["f1"],
        train_losses=train_losses,
        val_losses=val_losses,
        val_accuracies=val_accuracies,
        model_path=str(output_path),
        config=asdict(config),
    )
