#!/usr/bin/env python3
"""
Debug script to verify model works on training data.

This helps diagnose whether the model is fundamentally broken
or if there's a distribution mismatch between training and inference.
"""

import numpy as np
import torch
from pathlib import Path


def load_model():
    """Load the trained model and normalization stats."""
    checkpoint = torch.load("data/models/model.pt", map_location="cpu", weights_only=False)

    channel_means = np.array(checkpoint["channel_means"])
    channel_stds = np.array(checkpoint["channel_stds"])

    from ml.model import create_model
    model = create_model(
        model_type=checkpoint["config"]["model_type"],
        n_channels=checkpoint["config"]["n_channels"],
        window_size=checkpoint["config"]["window_size"]
    )
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    return model, channel_means, channel_stds, checkpoint["config"]


def normalize_window_inference(window_data, channel_means, channel_stds):
    """Normalize a window using INFERENCE method (min std = 0.01)."""
    safe_stds = np.maximum(channel_stds, 0.01)
    normalized = (window_data - channel_means) / safe_stds
    normalized = np.clip(normalized, -10.0, 10.0)
    normalized = np.nan_to_num(normalized, nan=0.0).astype(np.float32)
    return normalized


def normalize_window_training(window_data, channel_means, channel_stds):
    """Normalize a window using TRAINING method (min std = 1e-8)."""
    safe_stds = np.where(channel_stds < 1e-8, 1.0, channel_stds)
    normalized = (window_data - channel_means) / safe_stds
    # Training doesn't clip or handle NaN the same way
    normalized = np.nan_to_num(normalized, nan=0.0).astype(np.float32)
    return normalized


def run_inference(model, normalized_window):
    """Run inference on a normalized window."""
    with torch.no_grad():
        x = torch.tensor(normalized_window, dtype=torch.float32).unsqueeze(0)
        logits = model(x)
        prob = torch.sigmoid(logits).item()
    return logits.item(), prob


def main():
    print("=" * 60)
    print("MODEL SANITY CHECK")
    print("=" * 60)
    print()

    # Load model
    print("Loading model...")
    model, channel_means, channel_stds, config = load_model()
    window_size = config["window_size"]
    print(f"  Window size: {window_size}")
    print(f"  Channels: {config['n_channels']}")
    print()

    # Check for small stds that might cause normalization issues
    print("Checking channel stds...")
    from ml.preprocess import CHANNEL_NAMES
    small_std_channels = []
    for i, (name, std) in enumerate(zip(CHANNEL_NAMES, channel_stds)):
        if std < 0.01:
            small_std_channels.append((i, name, std))
            print(f"  Channel {i} ({name}): std={std:.6f} < 0.01")

    if small_std_channels:
        print()
        print("  WARNING: These channels have std < 0.01")
        print("  Training uses actual std, but inference caps at 0.01")
        print("  This causes different normalized values!")
    print()

    # Load training data
    print("Loading training data...")
    import pandas as pd
    from ml.preprocess import CHANNEL_NAMES

    parquet_files = list(Path("data/raw").glob("*.parquet"))
    if not parquet_files:
        print("ERROR: No training data found in data/raw/")
        return

    df = pd.read_parquet(parquet_files[0])
    data = df[CHANNEL_NAMES].values
    labels = df["label"].values

    print(f"  File: {parquet_files[0].name}")
    print(f"  Samples: {len(data)}")
    print(f"  Positive ratio: {labels.mean():.1%}")
    print()

    # Test on relaxed windows
    print("=" * 60)
    print("RELAXED WINDOWS (label=0) - using TRAINING normalization")
    print("=" * 60)
    relaxed_count = 0
    for i in range(0, len(data) - window_size, 128):
        window_labels = labels[i:i+window_size]
        positive_ratio = window_labels.mean()

        if positive_ratio < 0.1:  # Clearly relaxed
            window_data = data[i:i+window_size]
            normalized = normalize_window_training(window_data, channel_means, channel_stds)
            logit, prob = run_inference(model, normalized)

            print(f"  Window {i:6d}: logit={logit:7.2f}, prob={prob:.4f}")
            relaxed_count += 1
            if relaxed_count >= 5:
                break

    print()

    # Test on clenching windows - compare both normalization methods
    print("=" * 60)
    print("CLENCHING WINDOWS - COMPARING NORMALIZATION METHODS")
    print("=" * 60)
    print("  'train' = training normalization (std >= 1e-8)")
    print("  'infer' = inference normalization (std >= 0.01)")
    print()
    clench_count = 0
    for i in range(0, len(data) - window_size, 128):
        window_labels = labels[i:i+window_size]
        positive_ratio = window_labels.mean()

        if positive_ratio >= 0.5:  # Clenching
            window_data = data[i:i+window_size]

            # Try both normalization methods
            norm_train = normalize_window_training(window_data, channel_means, channel_stds)
            norm_infer = normalize_window_inference(window_data, channel_means, channel_stds)

            logit_train, prob_train = run_inference(model, norm_train)
            logit_infer, prob_infer = run_inference(model, norm_infer)

            print(f"  Window {i:6d}: ratio={positive_ratio:.2f}")
            print(f"    train: logit={logit_train:7.2f}, prob={prob_train:.4f}")
            print(f"    infer: logit={logit_infer:7.2f}, prob={prob_infer:.4f}")
            if abs(prob_train - prob_infer) > 0.01:
                print(f"    ^ DIFFERENCE!")

            # Show normalized stats for first clenching window (for comparison with live)
            if clench_count == 0:
                print(f"    Normalized stats: min={norm_train.min():.2f}, max={norm_train.max():.2f}, mean={norm_train.mean():.2f}")
            print()

            clench_count += 1
            if clench_count >= 5:
                break

    if clench_count == 0:
        print("  No clenching windows found in training data!")

    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print()
    print("If relaxed windows have negative logits (prob ~0) and")
    print("clenching windows have positive logits (prob ~1), the model works.")
    print()
    print("If ALL windows have very negative logits, there's a bug.")
    print()


if __name__ == "__main__":
    main()
