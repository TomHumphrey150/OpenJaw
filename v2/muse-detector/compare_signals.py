#!/usr/bin/env python3
"""
Compare signal patterns between training clenching and relaxed states.

Helps diagnose whether:
1. There's a clear signal difference between clench and relax
2. Which channels are most informative for detection
3. Why the model might not be generalizing
"""

import numpy as np
import pandas as pd
from pathlib import Path


def load_training_data():
    """Load training data from parquet files."""
    parquet_files = list(Path("data/raw").glob("*.parquet"))
    if not parquet_files:
        raise FileNotFoundError("No training data found in data/raw/")

    df = pd.read_parquet(parquet_files[0])
    return df


def analyze_channel_differences(df):
    """Analyze differences between clench and relax for all channels."""
    clench_mask = df["label"] == 1
    relax_mask = df["label"] == 0

    # Get all data channels
    exclude = ['timestamp', 'label', 'session_id']
    channels = [c for c in df.columns if c not in exclude]

    results = []
    for ch in channels:
        relax_mean = df.loc[relax_mask, ch].mean()
        clench_mean = df.loc[clench_mask, ch].mean()
        relax_std = df.loc[relax_mask, ch].std()
        clench_std = df.loc[clench_mask, ch].std()

        diff = clench_mean - relax_mean
        diff_pct = (diff / abs(relax_mean) * 100) if relax_mean != 0 else 0
        std_ratio = clench_std / relax_std if relax_std != 0 else 1

        results.append({
            'channel': ch,
            'relax_mean': relax_mean,
            'clench_mean': clench_mean,
            'diff': diff,
            'diff_pct': diff_pct,
            'relax_std': relax_std,
            'clench_std': clench_std,
            'std_ratio': std_ratio,
        })

    return pd.DataFrame(results)


def main():
    print("=" * 80)
    print("TRAINING DATA SIGNAL ANALYSIS")
    print("=" * 80)
    print()

    df = load_training_data()

    clench_count = (df["label"] == 1).sum()
    relax_count = (df["label"] == 0).sum()
    print(f"Clenching samples: {clench_count:,} ({clench_count/len(df):.1%})")
    print(f"Relaxed samples: {relax_count:,} ({relax_count/len(df):.1%})")
    print()

    # Analyze all channels
    results = analyze_channel_differences(df)

    # Sort by absolute difference percentage
    results_sorted = results.reindex(
        results['diff_pct'].abs().sort_values(ascending=False).index
    )

    print("=" * 80)
    print("ALL CHANNELS - Sorted by clench/relax difference")
    print("=" * 80)
    print()
    print(f"{'Channel':<20} {'Relax Mean':>12} {'Clench Mean':>12} {'Diff':>10} {'Diff %':>8} {'Std Ratio':>10}")
    print("-" * 80)

    for _, row in results_sorted.iterrows():
        # Highlight channels with significant differences
        marker = ""
        if abs(row['diff_pct']) > 5:
            marker = " <-- SIGNAL"
        elif row['std_ratio'] > 1.1:
            marker = " <-- variance"

        print(f"{row['channel']:<20} {row['relax_mean']:>12.4f} {row['clench_mean']:>12.4f} "
              f"{row['diff']:>10.4f} {row['diff_pct']:>7.1f}% {row['std_ratio']:>10.2f}{marker}")

    print()
    print("=" * 80)
    print("INTERPRETATION:")
    print("=" * 80)
    print()

    # Find channels with actual signal
    significant = results_sorted[results_sorted['diff_pct'].abs() > 5]
    if len(significant) > 0:
        print(f"Channels with >5% difference: {list(significant['channel'])}")
    else:
        print("WARNING: No channels show >5% difference between clench and relax!")
        print("This means the training data may not have a clear clench signal.")

    # Check std ratio (variance increase during clench)
    high_var = results_sorted[results_sorted['std_ratio'] > 1.1]
    if len(high_var) > 0:
        print(f"Channels with >10% variance increase during clench: {list(high_var['channel'])}")

    print()


if __name__ == "__main__":
    main()
