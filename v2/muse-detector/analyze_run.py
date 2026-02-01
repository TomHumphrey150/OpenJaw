#!/usr/bin/env python3
"""
Analyze inference runs from logs/runs/.

Usage:
    ./analyze_run.py              # Analyze most recent run
    ./analyze_run.py 20260131_175800  # Analyze specific run
    ./analyze_run.py --list       # List all runs
"""

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path


def get_runs_dir() -> Path:
    return Path(__file__).parent / "logs" / "runs"


def list_runs():
    """List all available runs."""
    runs_dir = get_runs_dir()
    if not runs_dir.exists():
        print("No runs directory found.")
        return

    runs = sorted(runs_dir.iterdir(), reverse=True)
    if not runs:
        print("No runs found.")
        return

    print("Available runs (newest first):")
    print("-" * 60)
    for run_dir in runs[:20]:  # Show last 20
        meta_file = run_dir / "meta.json"
        if meta_file.exists():
            meta = json.loads(meta_file.read_text())
            cmd = meta.get("command", "unknown")
            print(f"  {run_dir.name}  {cmd}")
        else:
            print(f"  {run_dir.name}  (no metadata)")


def get_latest_run() -> Path:
    """Get the most recent run directory."""
    runs_dir = get_runs_dir()
    if not runs_dir.exists():
        raise FileNotFoundError("No runs directory")

    runs = sorted(runs_dir.iterdir(), reverse=True)
    if not runs:
        raise FileNotFoundError("No runs found")

    return runs[0]


def analyze_run(run_dir: Path):
    """Analyze a single run."""
    print("=" * 70)
    print(f"ANALYZING RUN: {run_dir.name}")
    print("=" * 70)
    print()

    # Load metadata
    meta_file = run_dir / "meta.json"
    if meta_file.exists():
        meta = json.loads(meta_file.read_text())
        print("METADATA:")
        print(f"  Command: {meta.get('command', 'unknown')}")
        print(f"  Time: {meta.get('timestamp', 'unknown')}")
        print(f"  Git: {meta.get('git_commit', 'unknown')} (dirty={meta.get('git_dirty', 'unknown')})")
        print()

    # Load exit info
    exit_file = run_dir / "exit.json"
    if exit_file.exists():
        exit_info = json.loads(exit_file.read_text())
        print(f"  Exit code: {exit_info.get('exit_code', 'unknown')}")
        print(f"  End time: {exit_info.get('end_time', 'unknown')}")
        print()

    # Load and analyze output
    output_file = run_dir / "output.log"
    if not output_file.exists():
        print("No output.log found!")
        return

    output = output_file.read_text()

    # Extract key information
    print("-" * 70)
    print("INFERENCE SUMMARY:")
    print("-" * 70)

    # Find inference lines (two formats: with and without ground truth)
    inference_pattern = r'\[Inference #(\d+)\].*logit=([-\d.]+).*prob=([\d.]+)'
    inferences = re.findall(inference_pattern, output)

    # Find ground truth comparisons (debug mode)
    gt_pattern = r'\[ml\] Inference: prob=([\d.]+), pred=(True|False), actual=(True|False) \[(OK|MISMATCH)\]'
    gt_matches = re.findall(gt_pattern, output)

    if inferences:
        probs = [float(p) for _, _, p in inferences]
        logits = [float(l) for _, l, _ in inferences]

        print(f"  Total inferences: {len(inferences)}")
        print(f"  Probability range: {min(probs):.4f} - {max(probs):.4f}")
        print(f"  Logit range: {min(logits):.2f} - {max(logits):.2f}")
        print()

        # Count detections
        detections = output.count("is_detection=True")
        print(f"  Detections triggered: {detections}")

        # Check for issues
        if max(probs) < 0.01:
            print()
            print("  WARNING: All probabilities < 0.01 - likely normalization bug")
        if min(logits) < -15:
            print()
            print("  WARNING: Very negative logits - model extremely confident 'not clenching'")

    # Ground truth analysis (debug mode)
    if gt_matches:
        print()
        print("-" * 70)
        print("GROUND TRUTH ANALYSIS (spacebar = actual clench):")
        print("-" * 70)

        total = len(gt_matches)
        mismatches = [(p, pred, act) for p, pred, act, match in gt_matches if match == "MISMATCH"]
        false_negatives = [(p, pred, act) for p, pred, act in mismatches if act == "True"]
        false_positives = [(p, pred, act) for p, pred, act in mismatches if act == "False"]

        print(f"  Total with ground truth: {total}")
        print(f"  Matches (OK): {total - len(mismatches)}")
        print(f"  Mismatches: {len(mismatches)}")
        print(f"    False negatives (clenching but pred=False): {len(false_negatives)}")
        print(f"    False positives (relaxed but pred=True): {len(false_positives)}")

        if false_negatives:
            fn_probs = [float(p) for p, _, _ in false_negatives]
            print(f"    False negative probs: {min(fn_probs):.4f} - {max(fn_probs):.4f}")

        if len(mismatches) > 0:
            accuracy = (total - len(mismatches)) / total
            print(f"  Accuracy: {accuracy:.1%}")

    elif not inferences:
        print("  No inference data found in output")

    # Look for errors
    print()
    print("-" * 70)
    print("ERRORS/WARNINGS:")
    print("-" * 70)

    error_lines = [l for l in output.split('\n') if 'ERROR' in l or 'WARNING' in l or 'MISMATCH' in l]
    if error_lines:
        for line in error_lines[:10]:
            print(f"  {line.strip()}")
        if len(error_lines) > 10:
            print(f"  ... and {len(error_lines) - 10} more")
    else:
        print("  None found")

    # Show first inference details
    print()
    print("-" * 70)
    print("FIRST INFERENCE DETAILS:")
    print("-" * 70)

    first_inf_start = output.find("[Inference #1]")
    if first_inf_start != -1:
        # Get ~10 lines after first inference
        lines = output[first_inf_start:].split('\n')[:10]
        for line in lines:
            if line.strip():
                print(f"  {line.strip()}")
    else:
        print("  No inference details found")

    print()
    print("=" * 70)
    print(f"Full output: {output_file}")
    print("=" * 70)


def main():
    parser = argparse.ArgumentParser(description="Analyze inference runs")
    parser.add_argument("run_id", nargs="?", help="Run ID (timestamp) to analyze")
    parser.add_argument("--list", "-l", action="store_true", help="List all runs")
    parser.add_argument("--tail", "-t", type=int, default=0, help="Show last N lines of output")
    args = parser.parse_args()

    if args.list:
        list_runs()
        return

    try:
        if args.run_id:
            run_dir = get_runs_dir() / args.run_id
            if not run_dir.exists():
                print(f"Run not found: {args.run_id}")
                sys.exit(1)
        else:
            run_dir = get_latest_run()

        analyze_run(run_dir)

        if args.tail > 0:
            output_file = run_dir / "output.log"
            if output_file.exists():
                lines = output_file.read_text().split('\n')
                print()
                print(f"Last {args.tail} lines:")
                print("-" * 70)
                for line in lines[-args.tail:]:
                    print(line)

    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
