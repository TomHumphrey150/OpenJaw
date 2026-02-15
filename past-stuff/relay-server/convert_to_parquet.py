#!/usr/bin/env python3
"""
Convert Raw OSC JSONL to V2-Compatible Parquet

Processes raw data collected by the relay server and converts it to
the parquet format expected by the V2 ML training pipeline.

Key transformations:
- Interpolates ACC/GYRO (52 Hz) to EEG timestamps (256 Hz)
- Generates labels from jaw_clench events (configurable window)
- Outputs V2-compatible columns: timestamp, eeg_*, acc_*, gyro_*, label, session_id
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd


def load_jsonl(file_path: Path) -> list[dict]:
    """Load records from a JSONL file."""
    records = []
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def separate_streams(records: list[dict]) -> dict[str, pd.DataFrame]:
    """Separate records by stream type into DataFrames."""
    streams = {"eeg": [], "acc": [], "gyro": [], "jaw_clench": []}

    for rec in records:
        stream = rec.get("stream")
        if stream in streams:
            streams[stream].append(rec)

    # Convert to DataFrames
    result = {}
    for stream_name, data in streams.items():
        if data:
            df = pd.DataFrame(data)
            df = df.sort_values("ts").reset_index(drop=True)
            result[stream_name] = df

    return result


def interpolate_to_timestamps(
    source_df: pd.DataFrame,
    target_timestamps: np.ndarray,
    value_columns: list[str]
) -> pd.DataFrame:
    """Interpolate source data to target timestamps."""
    if source_df is None or source_df.empty:
        # Return NaN-filled DataFrame if no source data
        return pd.DataFrame({
            col: np.full(len(target_timestamps), np.nan)
            for col in value_columns
        })

    source_ts = source_df["ts"].values
    result = {}

    for col in value_columns:
        source_values = source_df[col].values
        # Linear interpolation
        interpolated = np.interp(
            target_timestamps,
            source_ts,
            source_values,
            left=np.nan,
            right=np.nan
        )
        result[col] = interpolated

    return pd.DataFrame(result)


def generate_labels(
    eeg_timestamps: np.ndarray,
    jaw_clench_df: Optional[pd.DataFrame],
    label_window_seconds: float = 0.5
) -> np.ndarray:
    """Generate binary labels based on proximity to jaw clench events.

    A sample is labeled 1 if it falls within label_window_seconds
    AFTER a jaw clench event (the window captures the clench itself).
    """
    labels = np.zeros(len(eeg_timestamps), dtype=np.int64)

    if jaw_clench_df is None or jaw_clench_df.empty:
        return labels

    clench_times = jaw_clench_df["ts"].values

    for clench_ts in clench_times:
        # Label samples within the window after the clench event
        mask = (eeg_timestamps >= clench_ts) & (eeg_timestamps < clench_ts + label_window_seconds)
        labels[mask] = 1

    return labels


def convert_file(
    input_path: Path,
    output_dir: Path,
    label_window_seconds: float = 0.5,
    session_id: Optional[str] = None
) -> dict:
    """Convert a single JSONL file to parquet.

    Returns stats about the conversion.
    """
    # Load and separate streams
    records = load_jsonl(input_path)
    if not records:
        return {"error": "No records found", "input_file": str(input_path)}

    streams = separate_streams(records)

    # Check we have EEG data (required as base timeline)
    if "eeg" not in streams or streams["eeg"].empty:
        return {"error": "No EEG data found", "input_file": str(input_path)}

    eeg_df = streams["eeg"]
    eeg_timestamps = eeg_df["ts"].values

    # Derive session ID from filename if not provided
    if session_id is None:
        # Extract from filename like "osc_raw_20260201_233000.jsonl"
        stem = input_path.stem
        if stem.startswith("osc_raw_"):
            session_id = stem.replace("osc_raw_", "")
        else:
            session_id = stem

    # Build output DataFrame
    output_df = pd.DataFrame({
        "timestamp": eeg_timestamps,
        "eeg_tp9": eeg_df["tp9"].values,
        "eeg_af7": eeg_df["af7"].values,
        "eeg_af8": eeg_df["af8"].values,
        "eeg_tp10": eeg_df["tp10"].values,
    })

    # Interpolate ACC data
    acc_df = streams.get("acc")
    acc_interp = interpolate_to_timestamps(
        acc_df, eeg_timestamps, ["x", "y", "z"]
    )
    output_df["acc_x"] = acc_interp["x"]
    output_df["acc_y"] = acc_interp["y"]
    output_df["acc_z"] = acc_interp["z"]

    # Interpolate GYRO data
    gyro_df = streams.get("gyro")
    gyro_interp = interpolate_to_timestamps(
        gyro_df, eeg_timestamps, ["x", "y", "z"]
    )
    output_df["gyro_x"] = gyro_interp["x"]
    output_df["gyro_y"] = gyro_interp["y"]
    output_df["gyro_z"] = gyro_interp["z"]

    # Generate labels from jaw clench events
    jaw_clench_df = streams.get("jaw_clench")
    labels = generate_labels(eeg_timestamps, jaw_clench_df, label_window_seconds)
    output_df["label"] = labels

    # Add session ID
    output_df["session_id"] = session_id

    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)

    # Write parquet
    output_path = output_dir / f"{session_id}.parquet"
    output_df.to_parquet(output_path, index=False)

    # Compute stats
    stats = {
        "input_file": str(input_path),
        "output_file": str(output_path),
        "session_id": session_id,
        "total_samples": len(output_df),
        "eeg_samples": len(eeg_df),
        "acc_samples": len(acc_df) if acc_df is not None else 0,
        "gyro_samples": len(gyro_df) if gyro_df is not None else 0,
        "jaw_clench_events": len(jaw_clench_df) if jaw_clench_df is not None else 0,
        "positive_labels": int(labels.sum()),
        "label_window_seconds": label_window_seconds,
        "duration_seconds": float(eeg_timestamps[-1] - eeg_timestamps[0]) if len(eeg_timestamps) > 1 else 0,
    }

    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Convert raw OSC JSONL files to V2-compatible parquet"
    )
    parser.add_argument(
        "input_files",
        nargs="+",
        type=Path,
        help="Input JSONL files (supports glob patterns)"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/processed"),
        help="Output directory for parquet files (default: data/processed)"
    )
    parser.add_argument(
        "--label-window",
        type=float,
        default=0.5,
        help="Label window in seconds after jaw clench event (default: 0.5)"
    )

    args = parser.parse_args()

    print(f"Converting {len(args.input_files)} file(s) to parquet")
    print(f"Output directory: {args.output_dir}")
    print(f"Label window: {args.label_window}s")
    print("-" * 60)

    total_stats = {
        "files_processed": 0,
        "files_failed": 0,
        "total_samples": 0,
        "total_jaw_clench_events": 0,
        "total_positive_labels": 0,
    }

    for input_path in args.input_files:
        if not input_path.exists():
            print(f"WARNING: File not found: {input_path}")
            total_stats["files_failed"] += 1
            continue

        print(f"\nProcessing: {input_path.name}")
        stats = convert_file(
            input_path,
            args.output_dir,
            label_window_seconds=args.label_window
        )

        if "error" in stats:
            print(f"  ERROR: {stats['error']}")
            total_stats["files_failed"] += 1
            continue

        print(f"  Session ID: {stats['session_id']}")
        print(f"  Duration: {stats['duration_seconds']:.1f}s ({stats['duration_seconds']/3600:.2f}h)")
        print(f"  EEG samples: {stats['eeg_samples']:,}")
        print(f"  ACC samples: {stats['acc_samples']:,} (interpolated)")
        print(f"  GYRO samples: {stats['gyro_samples']:,} (interpolated)")
        print(f"  Jaw clench events: {stats['jaw_clench_events']:,}")
        print(f"  Positive labels: {stats['positive_labels']:,}")
        print(f"  Output: {stats['output_file']}")

        total_stats["files_processed"] += 1
        total_stats["total_samples"] += stats["total_samples"]
        total_stats["total_jaw_clench_events"] += stats["jaw_clench_events"]
        total_stats["total_positive_labels"] += stats["positive_labels"]

    print("\n" + "=" * 60)
    print("Conversion complete:")
    print(f"  Files processed: {total_stats['files_processed']}")
    if total_stats["files_failed"] > 0:
        print(f"  Files failed: {total_stats['files_failed']}")
    print(f"  Total samples: {total_stats['total_samples']:,}")
    print(f"  Total jaw clench events: {total_stats['total_jaw_clench_events']:,}")
    print(f"  Total positive labels: {total_stats['total_positive_labels']:,}")


if __name__ == "__main__":
    main()
