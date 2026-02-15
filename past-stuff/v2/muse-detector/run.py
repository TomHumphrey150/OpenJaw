#!/usr/bin/env python3
"""
Skywalker v2: Single-command Muse jaw clench detector.

Unified entry point that handles:
- Device discovery
- OpenMuse streaming
- Data collection (interactive)
- Model training (automatic)
- Detection with WebSocket server

Usage:
    ./run.py                  # Interactive flow handles everything
    ./run.py --address XX:XX  # Use specific Muse address
    ./run.py --discover       # Force device discovery
    ./run.py --test           # Test mode (no Muse needed)
    ./run.py -v               # Verbose logging
"""

import argparse
import asyncio
import json
import logging
import os
import re
import shutil
import signal
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

import numpy as np

from detector import JawClenchDetector
from server import WebSocketServer, BonjourService
from streaming import LSLReceiver, LSLConnectionError
from utils import EventLogger
from ml import MultiStreamReceiver, MLInferenceEngine
from ml.collect import KeyboardMonitor
from ml.preprocess import EEG_CHANNELS, EEG_ACCGYRO_CHANNELS, TP_CHANNELS

# Configuration paths
CONFIG_FILE = Path(__file__).parent / "config.json"
USER_CONFIG_DIR = Path.home() / ".skywalker"
USER_CONFIG_FILE = USER_CONFIG_DIR / "muse_config.json"

# ML data paths
DATA_DIR = Path(__file__).parent / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
MODELS_DIR = DATA_DIR / "models"
DEFAULT_MODEL_PATH = MODELS_DIR / "model.pt"

# Load configuration
with open(CONFIG_FILE) as f:
    CONFIG = json.load(f)

# Logging setup
LOG_DIR = Path(__file__).parent / CONFIG["logging"]["directory"]
LOG_DIR.mkdir(exist_ok=True)
log_file = LOG_DIR / f"detector_{datetime.now().strftime('%Y-%m-%d')}.log"


def setup_logging(verbosity: int = 0) -> None:
    """Configure logging based on verbosity level."""
    if verbosity >= 2:
        level = logging.DEBUG
        log_format = "%(asctime)s %(levelname)-5s [%(name)s] %(message)s"
    elif verbosity >= 1:
        level = logging.DEBUG
        log_format = "%(asctime)s %(levelname)-5s [%(name)s] %(message)s"
    else:
        level = logging.INFO
        log_format = "%(asctime)s %(levelname)-5s %(message)s"

    logging.basicConfig(
        level=level,
        format=log_format,
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )


logger = logging.getLogger("run")


# =============================================================================
# ML Data/Model Helpers
# =============================================================================

def check_training_data() -> List[Path]:
    """Check for existing training data parquet files."""
    if not RAW_DATA_DIR.exists():
        return []
    return sorted(RAW_DATA_DIR.glob("*.parquet"))


def check_trained_model() -> Optional[Path]:
    """Check if a trained model exists."""
    if DEFAULT_MODEL_PATH.exists():
        return DEFAULT_MODEL_PATH
    return None


def prompt_session_name() -> str:
    """Prompt user for a descriptive session name."""
    print()
    print("Enter a descriptive name for this collection session.")
    print("Examples: sitting_upright, lying_back, lying_left, lying_right")
    print()
    while True:
        name = input("Session name: ").strip()
        if name:
            # Sanitize: replace spaces with underscores, remove special chars
            name = re.sub(r'[^a-zA-Z0-9_-]', '', name.replace(' ', '_'))
            if name:
                return name
        print("Please enter a valid session name (letters, numbers, underscores)")


def prompt_data_choice(existing_files: List[Path]) -> str:
    """
    Prompt user about existing training data.

    Returns:
        "reuse" - Use existing data
        "add_more" - Add another session
        "delete_all" - Delete all and start fresh
    """
    print()
    print(f"Found {len(existing_files)} existing training session(s):")
    for f in existing_files:
        print(f"  - {f.name}")
    print()
    print("What would you like to do?")
    print()
    print("  [1] Use existing data (default - just press Enter)")
    print("  [2] Add more training data")
    print("  [3] Delete all and start fresh")
    print()

    while True:
        choice = input("Choice [1/2/3]: ").strip()
        if choice in ("", "1"):
            return "reuse"
        elif choice == "2":
            return "add_more"
        elif choice == "3":
            return "delete_all"
        print("Please enter 1, 2, or 3 (or press Enter for default)")


def confirm_delete_all(file_count: int) -> bool:
    """
    Triple confirmation before deleting all training data.

    Returns:
        True if user confirms deletion, False otherwise
    """
    print()
    print("=" * 60)
    print("WARNING: You are about to DELETE ALL training data!")
    print(f"This will remove {file_count} session file(s).")
    print("This action CANNOT be undone.")
    print("=" * 60)
    print()

    # Confirmation 1: Type DELETE
    response = input("Type 'DELETE' to confirm: ").strip()
    if response != "DELETE":
        print("Deletion cancelled.")
        return False

    # Confirmation 2: Enter file count
    response = input(f"Enter the number of files to delete ({file_count}): ").strip()
    if response != str(file_count):
        print("Deletion cancelled.")
        return False

    # Confirmation 3: Final yes
    response = input("Final confirmation - type 'yes' to proceed: ").strip().lower()
    if response != "yes":
        print("Deletion cancelled.")
        return False

    return True


def prompt_run_mode(has_data: bool, has_model: bool) -> str:
    """
    Prompt user for what they want to do.

    Returns:
        "inference" - Run live detection (requires headset)
        "train_only" - Just retrain the model (no headset)
        "collect" - Collect new data then train (requires headset)
    """
    print()
    print("What would you like to do?")
    print()

    if has_data and has_model:
        print("  [1] Run live detection (requires headset)")
        print("  [2] Retrain model with existing data (no headset needed)")
        print("  [3] Collect new training data (requires headset)")
        print()

        while True:
            choice = input("Choice [1/2/3]: ").strip()
            if choice == "1":
                return "inference"
            elif choice == "2":
                return "train_only"
            elif choice == "3":
                return "collect"
            print("Please enter 1, 2, or 3")

    elif has_data:
        print("  [1] Train model and run detection (requires headset)")
        print("  [2] Train model only (no headset needed)")
        print("  [3] Collect more training data first (requires headset)")
        print()

        while True:
            choice = input("Choice [1/2/3]: ").strip()
            if choice == "1":
                return "inference"
            elif choice == "2":
                return "train_only"
            elif choice == "3":
                return "collect"
            print("Please enter 1, 2, or 3")

    else:
        # No data - must collect
        print("  No training data found. You'll need to collect some first.")
        print()
        print("  [1] Collect training data (requires headset)")
        print("  [q] Quit")
        print()

        while True:
            choice = input("Choice [1/q]: ").strip().lower()
            if choice == "1":
                return "collect"
            elif choice == "q":
                return "quit"
            print("Please enter 1 or q")


def delete_all_training_data() -> None:
    """Delete all training data and models."""
    if RAW_DATA_DIR.exists():
        for f in RAW_DATA_DIR.glob("*.parquet"):
            f.unlink()
        logger.info(f"Deleted all parquet files from {RAW_DATA_DIR}")

    if DEFAULT_MODEL_PATH.exists():
        DEFAULT_MODEL_PATH.unlink()
        logger.info(f"Deleted model: {DEFAULT_MODEL_PATH}")

    # Also delete the JSON metadata if it exists
    json_path = DEFAULT_MODEL_PATH.with_suffix(".json")
    if json_path.exists():
        json_path.unlink()


async def run_data_collection(session_name: str) -> bool:
    """
    Run data collection for a session.

    Returns:
        True if collection succeeded, False otherwise
    """
    from ml.collect import DataCollector

    print()
    print("=" * 60)
    print("DATA COLLECTION")
    print("=" * 60)
    print()
    print("Instructions:")
    print("  - HOLD SPACEBAR when clenching or grinding")
    print("  - RELEASE SPACEBAR when jaw is relaxed")
    print("  - Press ESC to stop early and save data")
    print()
    print("Recommended: 3-5 minutes per session")
    print()

    # Get duration
    duration_str = input("Duration in seconds [180]: ").strip()
    duration = 180.0
    if duration_str:
        try:
            duration = float(duration_str)
        except ValueError:
            print("Invalid duration, using 180 seconds")
            duration = 180.0

    # Ensure output directory exists
    RAW_DATA_DIR.mkdir(parents=True, exist_ok=True)

    collector = DataCollector(
        session_id=session_name,
        output_dir=str(RAW_DATA_DIR)
    )

    try:
        stats = await collector.run(duration=duration)
        print()
        print(f"Data saved: {stats.output_file}")
        print(f"Samples: {stats.total_samples:,} ({stats.positive_ratio:.1%} positive)")
        return True
    except ValueError as e:
        # No samples collected (e.g., stopped immediately)
        logger.warning(f"Collection incomplete: {e}")
        return False
    except Exception as e:
        logger.error(f"Collection failed: {e}")
        return False


def run_training(
    parquet_files: List[Path],
    eeg_only: bool = False,
    tp_only: bool = False,
    no_early_stopping: bool = False,
    window_size: int = 256,
    augment: bool = False,
    augment_multiplier: int = 10
) -> Optional[Path]:
    """
    Train a model on the given parquet files.

    Args:
        parquet_files: List of paths to training data
        eeg_only: If True, train using only EEG channels (no motion sensors)
        tp_only: If True, train using only TP9/TP10 (temple sensors)
        no_early_stopping: If True, train for full max_epochs without early stopping
        window_size: Window size in samples (256=1s, 128=0.5s at 256Hz)
        augment: If True, apply data augmentation to multiply training data
        augment_multiplier: How many times to multiply training data

    Returns:
        Path to trained model, or None if training failed
    """
    from ml.train import TrainingConfig, train_model

    print()
    print("=" * 60)
    print("TRAINING MODEL")
    print("=" * 60)
    print()
    print(f"Training on {len(parquet_files)} session(s):")
    for f in parquet_files:
        print(f"  - {f.name}")
    if tp_only:
        print()
        print("TP-ONLY MODE: Training with TP9/TP10 only (temple sensors near jaw muscle)")
    elif eeg_only:
        print()
        print("EEG-ONLY MODE: Training with EEG channels only (excluding motion sensors)")
    if no_early_stopping:
        print()
        print("FULL TRAINING: Early stopping disabled, will train for all 100 epochs")
    if window_size != 256:
        print()
        print(f"CUSTOM WINDOW: {window_size} samples ({window_size/256*1000:.0f}ms) - stride {window_size//2}")
    if augment:
        print()
        print(f"AUGMENTATION: Training data will be multiplied x{augment_multiplier}")
    print()

    # Ensure models directory exists
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    # Configure channels (tp_only takes precedence over eeg_only)
    if tp_only:
        channels = TP_CHANNELS
        n_channels = len(TP_CHANNELS)
    elif eeg_only:
        channels = EEG_CHANNELS
        n_channels = len(EEG_CHANNELS)
    else:
        channels = EEG_ACCGYRO_CHANNELS  # 8 EEG + 6 ACCGYRO (no OPTICS)
        n_channels = len(EEG_ACCGYRO_CHANNELS)

    # Set early stopping patience (9999 = effectively disabled)
    patience = 9999 if no_early_stopping else 10

    config = TrainingConfig(
        model_type="cnn",
        n_channels=n_channels,
        window_size=window_size,
        window_stride=window_size // 2,  # 50% overlap
        max_epochs=100,
        early_stopping_patience=patience,
        channels=channels,
        augment=augment,
        augment_multiplier=augment_multiplier,
    )

    try:
        result = train_model(
            parquet_paths=parquet_files,
            output_path=DEFAULT_MODEL_PATH,
            config=config
        )
        print()
        print(f"Model saved: {result.model_path}")
        print(f"Validation accuracy: {result.best_val_accuracy:.1%}")
        print(f"Validation F1: {result.best_val_f1:.3f}")
        return Path(result.model_path)
    except Exception as e:
        logger.error(f"Training failed: {e}")
        import traceback
        traceback.print_exc()
        return None


# =============================================================================
# Address Resolution
# =============================================================================

def load_saved_address() -> Optional[dict]:
    """Load saved Muse device config from ~/.skywalker/muse_config.json."""
    if USER_CONFIG_FILE.exists():
        try:
            with open(USER_CONFIG_FILE) as f:
                config = json.load(f)
                if config.get("muse_address"):
                    return config
        except (json.JSONDecodeError, IOError):
            pass
    return None


def save_address(name: str, address: str) -> None:
    """Save Muse device config to ~/.skywalker/muse_config.json."""
    USER_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    config = {"muse_name": name, "muse_address": address}
    with open(USER_CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    logger.debug(f"Saved address to {USER_CONFIG_FILE}")


def discover_devices(timeout: int = 10) -> list[dict]:
    """
    Run OpenMuse find command and parse discovered devices.

    Returns:
        List of dicts with 'name' and 'address' keys
    """
    logger.debug(f"[discovery] Scanning for {timeout} seconds...")

    try:
        result = subprocess.run(
            ["OpenMuse", "find", "--timeout", str(timeout)],
            capture_output=True,
            text=True,
            timeout=timeout + 5
        )

        devices = []
        # Pattern matches both MAC addresses (with colons) and macOS UUIDs (with dashes)
        pattern = r"Found device ([^,]+), MAC Address ([0-9A-Fa-f:-]+)"

        for line in result.stdout.splitlines() + result.stderr.splitlines():
            match = re.search(pattern, line)
            if match:
                device = {
                    "name": match.group(1).strip(),
                    "address": match.group(2).strip()
                }
                if device not in devices:
                    devices.append(device)

        logger.debug(f"[discovery] Found {len(devices)} device(s)")
        return devices

    except FileNotFoundError:
        logger.error("OpenMuse not found in PATH")
        logger.error("Install with: pip install git+https://github.com/DominiqueMakowski/OpenMuse.git")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        logger.error("Bluetooth scan timed out")
        sys.exit(1)


def select_device_interactive(devices: list[dict]) -> Optional[dict]:
    """Prompt user to select a device from the list."""
    if not devices:
        print()
        print("No Muse devices found.")
        print()
        print("Troubleshooting:")
        print("  - Is the Muse powered on?")
        print("  - Is it in pairing mode (LED pulsing white)?")
        print("  - Is Bluetooth enabled on this Mac?")
        return None

    print()
    print(f"Found {len(devices)} Muse device(s):")
    print()
    for i, device in enumerate(devices, 1):
        print(f"  [{i}] {device['name']} ({device['address']})")
    print()

    if len(devices) == 1:
        response = input("Use this device? [Y/n]: ").strip().lower()
        if response in ("", "y", "yes"):
            return devices[0]
        return None

    while True:
        try:
            choice = input(f"Select device [1-{len(devices)}] or 'q' to quit: ").strip()
            if choice.lower() == 'q':
                return None
            index = int(choice) - 1
            if 0 <= index < len(devices):
                return devices[index]
            print(f"Please enter a number between 1 and {len(devices)}")
        except ValueError:
            print("Invalid input. Enter a number or 'q' to quit.")


def get_muse_address(args) -> Optional[tuple[str, str]]:
    """
    Get Muse address from args, saved config, or interactive discovery.

    Returns:
        Tuple of (name, address) or None if not available
    """
    # 1. Command-line address takes priority
    if args.address:
        logger.info(f"Using provided address: {args.address}")
        return ("Muse", args.address)

    # 2. Check saved address (unless --discover forces new discovery)
    if not args.discover:
        saved = load_saved_address()
        if saved:
            name = saved.get("muse_name", "Muse")
            address = saved["muse_address"]
            logger.info(f"Using saved device: {name} ({address})")
            return (name, address)

    # 3. Interactive discovery
    print()
    print("=" * 60)
    print("MUSE DEVICE DISCOVERY")
    print("=" * 60)
    print()
    print("Make sure your Muse is:")
    print("  1. Powered on")
    print("  2. In pairing mode (LED pulsing white)")
    print()

    devices = discover_devices(timeout=args.timeout)
    selected = select_device_interactive(devices)

    if selected:
        save_address(selected["name"], selected["address"])
        return (selected["name"], selected["address"])

    return None


# =============================================================================
# OpenMuse Subprocess Management
# =============================================================================

class OpenMuseProcess:
    """Manages the OpenMuse streaming subprocess."""

    def __init__(self, address: str):
        self.address = address
        self.process: Optional[subprocess.Popen] = None

    def start(self) -> bool:
        """Start OpenMuse streaming subprocess."""
        logger.debug(f"[openmuse] Starting subprocess: OpenMuse stream --address {self.address}")

        try:
            self.process = subprocess.Popen(
                ["OpenMuse", "stream", "--address", self.address],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            logger.debug(f"[openmuse] Subprocess PID: {self.process.pid}")
            return True

        except FileNotFoundError:
            logger.error("OpenMuse not found in PATH")
            return False
        except Exception as e:
            logger.error(f"Failed to start OpenMuse: {e}")
            return False

    def is_running(self) -> bool:
        """Check if the subprocess is still running."""
        if self.process is None:
            return False
        return self.process.poll() is None

    def stop(self) -> None:
        """Stop the OpenMuse subprocess."""
        if self.process is None:
            return

        logger.debug("[openmuse] Stopping subprocess...")

        try:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                logger.warning("[openmuse] Process didn't terminate, killing...")
                self.process.kill()
                self.process.wait()
        except Exception as e:
            logger.warning(f"[openmuse] Error stopping process: {e}")
        finally:
            self.process = None


# =============================================================================
# LSL Stream Wait
# =============================================================================

async def wait_for_lsl_stream(
    stream_name: str = "Muse",
    timeout: float = 30.0,
    poll_interval: float = 1.0
) -> bool:
    """
    Wait for LSL stream to become available.

    OpenMuse creates streams with names like "Muse-EEG (XX:XX:XX:XX:XX:XX)".
    We search for streams containing "Muse" in the name.

    Returns:
        True if stream found, False on timeout
    """
    from mne_lsl.lsl import resolve_streams

    logger.debug(f"[lsl] Searching for stream matching '{stream_name}'...")

    elapsed = 0.0
    while elapsed < timeout:
        try:
            # resolve_streams returns a list of StreamInfo objects
            streams = resolve_streams(timeout=poll_interval)

            for stream in streams:
                name = stream.name
                if stream_name.lower() in name.lower():
                    sfreq = stream.sfreq
                    n_channels = stream.n_channels
                    logger.debug(f"[lsl] Found stream: {name}, {sfreq} Hz, {n_channels} channels")
                    return True

        except Exception as e:
            logger.debug(f"[lsl] Error resolving streams: {e}")

        elapsed += poll_interval
        await asyncio.sleep(0.1)  # Small additional delay

    logger.error(f"[lsl] Timeout waiting for stream (waited {timeout}s)")
    return False


# =============================================================================
# Detection Loop
# =============================================================================

async def test_event_generator(ws_server: WebSocketServer) -> None:
    """Generate fake jaw clench events every 5 seconds for testing."""
    logger.info("TEST MODE: Generating events every 5 seconds")

    while True:
        await asyncio.sleep(5)
        await ws_server.broadcast_jaw_clench()
        logger.info(f"[detector] JAW CLENCH #{ws_server.event_count} (simulated)")


async def ml_detection_loop(
    receiver: MultiStreamReceiver,
    engine: MLInferenceEngine,
    ws_server: WebSocketServer,
    event_logger: EventLogger,
    keyboard: Optional[KeyboardMonitor] = None,
    verbose: int = 0
) -> None:
    """
    ML-based detection loop using neural network inference.

    No calibration needed - uses pre-trained model.

    If keyboard monitor is provided, spacebar state is logged for debugging
    (shows ground truth vs model prediction).
    """
    logger.info("")
    logger.info("=" * 60)
    logger.info("ML DETECTION MODE")
    logger.info(f"  Model: {engine.model_path.name}")
    logger.info(f"  Threshold: {engine.detection_threshold}")
    logger.info(f"  Debounce: {engine.debounce_seconds}s")
    if keyboard:
        logger.info(f"  Debug: SPACEBAR = ground truth clenching")
    logger.info("=" * 60)
    logger.info("")
    if keyboard:
        logger.info("Ready for ML-based detection. Hold SPACEBAR when clenching for debug.")
    else:
        logger.info("Ready for ML-based detection. Press Ctrl+C to stop.")
    logger.info("")

    async for chunk in receiver.stream():
        if chunk.eeg is None:
            continue

        # Verbose data flow logging
        if verbose >= 2:
            logger.debug(
                f"[lsl] Received chunk: EEG {len(chunk.eeg)} samples, "
                f"ACCGYRO {len(chunk.accgyro) if chunk.accgyro is not None else 0} samples, "
                f"OPTICS {len(chunk.optics) if chunk.optics is not None else 0} samples"
            )

        # Run ML inference with ALL sensor data
        result = engine.process(
            eeg_data=chunk.eeg,
            eeg_timestamps=chunk.eeg_timestamps,
            accgyro_data=chunk.accgyro,
            accgyro_timestamps=chunk.accgyro_timestamps,
            optics_data=chunk.optics,
            optics_timestamps=chunk.optics_timestamps
        )

        if not result.window_ready:
            if verbose >= 2:
                logger.debug(f"[ml] Buffer filling: {engine._buffer.samples_collected}/{engine._buffer.window_size}")
            continue

        # Get ground truth from spacebar if keyboard monitor active
        ground_truth = keyboard.is_clenching if keyboard else None

        # Verbose inference logging with ground truth
        if verbose >= 1:
            if ground_truth is not None:
                # Show ground truth comparison
                match = "OK" if (ground_truth == result.is_clenching) else "MISMATCH"
                logger.debug(
                    f"[ml] Inference: prob={result.probability:.3f}, "
                    f"pred={result.is_clenching}, actual={ground_truth} [{match}]"
                )
            else:
                logger.debug(
                    f"[ml] Inference: prob={result.probability:.3f}, "
                    f"clenching={result.is_clenching}, detection={result.is_detection}"
                )

        # Handle detection
        if result.is_detection:
            logger.info(
                f"[ml] JAW CLENCH #{ws_server.event_count + 1} "
                f"(probability={result.probability:.3f})"
            )

            # Broadcast to iOS app
            await ws_server.broadcast_jaw_clench()

            if verbose >= 1:
                logger.debug(f"[websocket] Broadcast to {len(ws_server._clients)} client(s)")

            # Log for analysis
            event_logger.log_jaw_clench(
                envelope_max=result.probability,
                threshold=engine.detection_threshold,
                baseline_mean=0.0,
                baseline_std=0.0
            )


async def detection_loop(
    receiver: LSLReceiver,
    detector: JawClenchDetector,
    ws_server: WebSocketServer,
    event_logger: EventLogger,
    calibrate: bool = True,
    verbose: int = 0
) -> None:
    """
    Main detection loop: read EEG, detect clenches, broadcast events.

    Uses MVC (Maximum Voluntary Contraction) calibration:
    - Phase 1: Keep jaw relaxed (establishes noise floor)
    - Phase 2: Clench jaw hard (establishes your maximum)
    """
    # Track calibration phase transitions for user guidance
    last_phase = None
    calibration_logged = False

    if calibrate:
        logger.info("")
        logger.info("=" * 60)
        logger.info("MVC CALIBRATION - Two phases:")
        logger.info("  Phase 1: Keep jaw RELAXED (establishes baseline)")
        logger.info("  Phase 2: CLENCH JAW HARD (establishes your maximum)")
        logger.info("=" * 60)
        logger.info("")
        logger.info("Starting Phase 1: Keep your jaw RELAXED...")

    async for chunk in receiver.stream():
        # Verbose data flow logging
        if verbose >= 2:
            logger.debug(
                f"[lsl] Received chunk: {len(chunk.tp9)} samples, "
                f"TP9 range [{chunk.tp9.min():.1f}, {chunk.tp9.max():.1f}]"
            )

        # Process bilateral signal (average of TP9 and TP10)
        result = detector.process_bilateral(chunk.tp9, chunk.tp10)

        # Handle calibration phase transitions
        if result.calibrating:
            current_phase = result.calibration_phase

            # Announce phase transitions
            if current_phase != last_phase:
                if current_phase == "clench":
                    logger.info("")
                    logger.info("=" * 60)
                    logger.info("Phase 2: CLENCH YOUR JAW HARD NOW!")
                    logger.info("=" * 60)
                last_phase = current_phase

            progress = detector.calibration_progress * 100
            if verbose >= 1:
                logger.debug(f"[calibration] Phase: {current_phase}, Progress: {progress:.0f}%")
            continue

        # Log calibration completion (once)
        if detector.is_calibrated and not calibration_logged:
            calibration_logged = True
            logger.info("")
            logger.info("=" * 60)
            logger.info("CALIBRATION COMPLETE - Detection active!")
            logger.info(f"  Relaxed baseline: {detector.relaxed_baseline:.2f}")
            logger.info(f"  Max clench (MVC): {detector.mvc_value:.2f}")
            logger.info(f"  Detection threshold: {result.threshold:.2f}")
            logger.info(f"  ({detector.mvc_threshold_percent:.0%} of clench strength)")
            logger.info("=" * 60)
            logger.info("")
            logger.info("Ready for detection. Press Ctrl+C to stop.")
            logger.info("")

            event_logger.log_calibration(
                baseline_mean=detector.relaxed_baseline,
                baseline_std=0.0,  # Not used in MVC mode
                threshold=result.threshold,
                samples=int(
                    (detector.relaxed_calibration_seconds + detector.clench_calibration_seconds)
                    * detector.sample_rate
                )
            )

        # Verbose threshold checking
        if verbose >= 2 and len(result.envelope) > 0:
            envelope_val = float(np.max(result.envelope))
            above = envelope_val > result.threshold
            logger.debug(
                f"[detector] Envelope: {envelope_val:.2f} "
                f"{'>' if above else '<'} threshold {result.threshold:.2f}"
            )

        # Handle jaw clench detection
        if result.is_clenching:
            envelope_max = float(np.max(result.envelope)) if len(result.envelope) > 0 else 0.0

            logger.info(
                f"[detector] JAW CLENCH #{ws_server.event_count + 1} "
                f"(envelope={envelope_max:.2f}, threshold={result.threshold:.2f})"
            )

            # Broadcast to iOS app
            await ws_server.broadcast_jaw_clench()

            if verbose >= 1:
                logger.debug(f"[websocket] Broadcast to {len(ws_server._clients)} client(s)")

            # Log for analysis
            event_logger.log_jaw_clench(
                envelope_max=envelope_max,
                threshold=result.threshold,
                baseline_mean=detector.relaxed_baseline,
                baseline_std=0.0
            )


# =============================================================================
# Main Entry Point
# =============================================================================

async def main() -> None:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Skywalker v2: Muse Jaw Clench Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./run.py                     # Interactive flow: choose mode, handles everything
  ./run.py --train-only        # Retrain model with existing data (no headset)
  ./run.py --address XX:XX:XX  # Skip discovery, use specific address
  ./run.py --discover          # Force new device discovery
  ./run.py --test              # Test mode (no Muse needed)
  ./run.py -v                  # Verbose output
  ./run.py -vv                 # Extra verbose (trace-level)

The interactive flow will:
  1. Check for existing training data
  2. Guide you through data collection if needed
  3. Train a model automatically
  4. Run detection with the trained model
"""
    )
    parser.add_argument(
        "--address", "-a",
        type=str,
        help="Muse MAC address (skip discovery)"
    )
    parser.add_argument(
        "--discover", "-d",
        action="store_true",
        help="Force device discovery even if address saved"
    )
    parser.add_argument(
        "--timeout", "-t",
        type=int,
        default=10,
        help="Discovery timeout seconds (default: 10)"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=CONFIG["detector"]["mvc_threshold_percent"],
        help=f"Threshold as %% of max clench (default: {CONFIG['detector']['mvc_threshold_percent'] * 100:.0f}%%)"
    )
    parser.add_argument(
        "--no-calibrate",
        action="store_true",
        help="Skip calibration phase (threshold mode only)"
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Test mode: simulate events (no Muse needed)"
    )
    parser.add_argument(
        "--model", "-m",
        type=str,
        help="Path to trained ML model (.pt file) - skips interactive flow"
    )
    parser.add_argument(
        "--ml-threshold",
        type=float,
        default=0.5,
        help="ML detection threshold (0-1, default: 0.5)"
    )
    parser.add_argument(
        "--threshold-mode",
        action="store_true",
        help="Use threshold-based detection instead of ML"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Debug mode: hold SPACEBAR when clenching to show ground truth vs prediction"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="count",
        default=0,
        help="Debug logging (-v for debug, -vv for trace)"
    )
    parser.add_argument(
        "--eeg-only",
        action="store_true",
        help="Train/run with EEG channels only (exclude motion sensors)"
    )
    parser.add_argument(
        "--tp-only",
        action="store_true",
        help="Train/run with TP9/TP10 only (temple sensors closest to jaw muscle)"
    )
    parser.add_argument(
        "--no-early-stopping",
        action="store_true",
        help="Disable early stopping (train for full max_epochs)"
    )
    parser.add_argument(
        "--window-size",
        type=int,
        default=256,
        help="Window size in samples (256=1s, 128=0.5s, 64=0.25s). Smaller = more data but less context."
    )
    parser.add_argument(
        "--augment",
        action="store_true",
        help="Apply data augmentation to multiply training data"
    )
    parser.add_argument(
        "--augment-multiplier",
        type=int,
        default=10,
        help="How many times to multiply training data (default: 10)"
    )
    parser.add_argument(
        "--train-only",
        action="store_true",
        help="Only retrain the model using existing data (no headset needed)"
    )

    args = parser.parse_args()

    setup_logging(args.verbose)

    print()
    print("Skywalker v2: Muse Jaw Clench Detector")
    print("=" * 40)
    print()

    # Initialize variables
    openmuse_proc = None
    muse_name = None
    muse_address = None
    model_path = None

    # =================================================================
    # Determine run mode (what does the user want to do?)
    # =================================================================

    # Check current state
    data_files = check_training_data()
    existing_model = check_trained_model()

    # Handle explicit flags first
    if args.test:
        run_mode = "test"
    elif args.train_only:
        if not data_files:
            logger.error("No training data found. Cannot use --train-only without data.")
            logger.error("Run without --train-only to collect training data first.")
            sys.exit(1)
        run_mode = "train_only"
    elif args.model:
        # Explicit model path - go straight to inference
        model_path = Path(args.model)
        if not model_path.exists():
            logger.error(f"Model not found: {model_path}")
            sys.exit(1)
        run_mode = "inference"
    elif args.threshold_mode:
        run_mode = "inference"
    else:
        # Interactive mode selection
        print("=" * 60)
        print("MODE SELECTION")
        print("=" * 60)

        if data_files:
            print(f"Found {len(data_files)} training session(s)")
            if existing_model:
                print(f"Found trained model: {existing_model.name}")

        run_mode = prompt_run_mode(
            has_data=len(data_files) > 0,
            has_model=existing_model is not None
        )

        if run_mode == "quit":
            print("Goodbye!")
            sys.exit(0)

    # =================================================================
    # Handle train-only mode (no headset needed)
    # =================================================================

    if run_mode == "train_only":
        print()
        print("=" * 60)
        print("TRAIN ONLY MODE")
        print("=" * 60)

        # Offer data management options
        choice = prompt_data_choice(data_files)

        if choice == "delete_all":
            if confirm_delete_all(len(data_files)):
                delete_all_training_data()
                logger.error("All data deleted. No data left to train on.")
                sys.exit(1)
            else:
                print("Deletion cancelled, using existing data")

        # Refresh data files list
        data_files = check_training_data()
        if not data_files:
            logger.error("No training data available")
            sys.exit(1)

        # Train model
        print()
        print("Training model on existing data...")
        model_path = run_training(
            data_files,
            eeg_only=args.eeg_only,
            tp_only=args.tp_only,
            no_early_stopping=args.no_early_stopping,
            window_size=args.window_size,
            augment=args.augment,
            augment_multiplier=args.augment_multiplier
        )

        if not model_path:
            logger.error("Training failed")
            sys.exit(1)

        print()
        print("=" * 60)
        print("TRAINING COMPLETE")
        print(f"Model saved to: {model_path}")
        print()
        print("To run live detection with this model:")
        print(f"  ./run.py")
        print("=" * 60)
        sys.exit(0)

    # =================================================================
    # Connect to Muse (needed for collect and inference modes)
    # =================================================================

    if run_mode != "test":
        # Get Muse address
        result = get_muse_address(args)
        if not result:
            logger.error("No Muse device configured. Run with --discover or --address.")
            sys.exit(1)

        muse_name, muse_address = result

        # Start OpenMuse subprocess
        print(f"Starting OpenMuse stream for {muse_name}...")
        openmuse_proc = OpenMuseProcess(muse_address)
        if not openmuse_proc.start():
            sys.exit(1)

        # Wait for LSL stream
        print("Waiting for LSL stream...")
        stream_ready = await wait_for_lsl_stream(
            stream_name="Muse",
            timeout=30.0
        )

        if not stream_ready:
            logger.error("Could not connect to Muse LSL stream")
            openmuse_proc.stop()
            sys.exit(1)

        logger.info("[lsl] Connected to LSL stream")

    # =================================================================
    # Handle collect mode (collect new data, then optionally train)
    # =================================================================

    if run_mode == "collect":
        print()
        print("=" * 60)
        print("DATA COLLECTION")
        print("=" * 60)

        # If data exists, offer management options
        if data_files:
            choice = prompt_data_choice(data_files)

            if choice == "delete_all":
                if confirm_delete_all(len(data_files)):
                    delete_all_training_data()
                    data_files = []
                else:
                    print("Deletion cancelled, will add to existing data")
            elif choice == "reuse":
                print("Using existing data (skipping collection)")
                # Skip to training
                data_files = check_training_data()
                if data_files:
                    print()
                    print("Training model...")
                    model_path = run_training(
                        data_files,
                        eeg_only=args.eeg_only,
                        tp_only=args.tp_only,
                        no_early_stopping=args.no_early_stopping,
                        window_size=args.window_size,
                        augment=args.augment,
                        augment_multiplier=args.augment_multiplier
                    )
                    if model_path:
                        run_mode = "inference"  # Continue to inference after training

        # Collect new data if we're still in collect mode
        if run_mode == "collect":
            session_name = prompt_session_name()
            if await run_data_collection(session_name):
                data_files = check_training_data()
            else:
                if not data_files:
                    logger.error("Data collection failed and no existing data")
                    if openmuse_proc:
                        openmuse_proc.stop()
                    sys.exit(1)
                print("Collection failed, continuing with existing data")

            # Train after collection
            if data_files:
                print()
                print("Training model on collected data...")
                model_path = run_training(
                    data_files,
                    eeg_only=args.eeg_only,
                    tp_only=args.tp_only,
                    no_early_stopping=args.no_early_stopping,
                    window_size=args.window_size,
                    augment=args.augment,
                    augment_multiplier=args.augment_multiplier
                )
                if not model_path:
                    logger.error("Training failed")
                    if openmuse_proc:
                        openmuse_proc.stop()
                    sys.exit(1)

            # Continue to inference
            run_mode = "inference"

    # =================================================================
    # Prepare for inference mode
    # =================================================================

    if run_mode == "inference" and not args.threshold_mode and not model_path:
        # Need a trained model for ML inference
        model_path = check_trained_model()
        if not model_path:
            # Need to train first
            data_files = check_training_data()
            if not data_files:
                logger.error("No training data and no model. Cannot run inference.")
                if openmuse_proc:
                    openmuse_proc.stop()
                sys.exit(1)

            print()
            print("Training model before inference...")
            model_path = run_training(
                data_files,
                eeg_only=args.eeg_only,
                tp_only=args.tp_only,
                no_early_stopping=args.no_early_stopping,
                window_size=args.window_size,
                augment=args.augment,
                augment_multiplier=args.augment_multiplier
            )
            if not model_path:
                logger.error("Training failed")
                if openmuse_proc:
                    openmuse_proc.stop()
                sys.exit(1)

    # Initialize components
    ws_server = WebSocketServer(
        host=CONFIG["websocket"]["ip"],
        port=CONFIG["websocket"]["port"]
    )

    bonjour = BonjourService(
        service_type=CONFIG["bonjour"]["service_type"],
        service_name=CONFIG["bonjour"]["service_name"],
        port=CONFIG["websocket"]["port"]
    )

    detector = JawClenchDetector(
        sample_rate=CONFIG["detector"]["sample_rate"],
        mvc_threshold_percent=args.threshold,
        relaxed_calibration_seconds=CONFIG["detector"]["relaxed_calibration_seconds"],
        clench_calibration_seconds=CONFIG["detector"]["clench_calibration_seconds"],
        debounce_seconds=CONFIG["detector"]["debounce_seconds"],
        bandpass_low_hz=CONFIG["detector"]["bandpass_low_hz"],
        bandpass_high_hz=CONFIG["detector"]["bandpass_high_hz"],
        envelope_cutoff_hz=CONFIG["detector"]["envelope_cutoff_hz"],
        filter_order=CONFIG["detector"]["filter_order"]
    )

    event_logger = EventLogger(log_dir=str(LOG_DIR))

    # Set up graceful shutdown
    loop = asyncio.get_event_loop()
    stop_event = asyncio.Event()

    def signal_handler() -> None:
        logger.info("")
        logger.info("Shutdown signal received...")
        stop_event.set()

    loop.add_signal_handler(signal.SIGINT, signal_handler)
    loop.add_signal_handler(signal.SIGTERM, signal_handler)

    try:
        # Start WebSocket server and Bonjour
        await ws_server.start()
        local_ip = await bonjour.register()

        logger.info(f"WebSocket server: ws://{local_ip}:{CONFIG['websocket']['port']}")
        logger.info("iOS app will auto-discover via Bonjour")

        event_logger.open()

        if run_mode == "test":
            # Test mode: generate fake events
            logger.info("")
            logger.info("TEST MODE - Press Ctrl+C to stop")
            logger.info("")

            test_task = asyncio.create_task(test_event_generator(ws_server))
            await stop_event.wait()
            test_task.cancel()
        elif model_path:
            # ML mode: use trained neural network
            logger.info(f"ML MODE: Using model {model_path.name}")

            # Initialize ML inference engine
            engine = MLInferenceEngine(
                model_path=str(model_path),
                detection_threshold=args.ml_threshold,
                debounce_seconds=CONFIG["detector"]["debounce_seconds"]
            )

            # Use multi-stream receiver for EEG + ACCGYRO streams (OPTICS excluded)
            receiver = MultiStreamReceiver(
                stream_name_prefix="Muse",
                require_accgyro=True,
                include_optics=False,  # OPTICS excluded due to variance issues
                poll_interval_ms=CONFIG["lsl"]["poll_interval_ms"]
            )

            # Set up keyboard monitor for ground truth debugging
            keyboard = None
            if args.debug:
                keyboard = KeyboardMonitor()
                keyboard.start()
                logger.info("Debug mode: Hold SPACEBAR when clenching for ground truth")

            try:
                await receiver.connect()

                detection_task = asyncio.create_task(
                    ml_detection_loop(
                        receiver, engine, ws_server, event_logger,
                        keyboard=keyboard,
                        verbose=args.verbose
                    )
                )

                done, pending = await asyncio.wait(
                    [asyncio.create_task(stop_event.wait()), detection_task],
                    return_when=asyncio.FIRST_COMPLETED
                )

                for task in pending:
                    task.cancel()

            except Exception as e:
                logger.error(f"ML detection error: {e}")
                sys.exit(1)
            finally:
                if keyboard:
                    keyboard.stop()
                await receiver.disconnect()

        else:
            # Threshold mode: MVC-calibrated detection
            # Use partial matching for OpenMuse stream names like "Muse-EEG (XX:XX:...)"
            receiver = LSLReceiver(
                stream_name="Muse",  # Partial match
                channels=CONFIG["lsl"]["channels"],
                poll_interval_ms=CONFIG["lsl"]["poll_interval_ms"]
            )

            try:
                await receiver.connect()

                calibrate = not args.no_calibrate
                detection_task = asyncio.create_task(
                    detection_loop(
                        receiver, detector, ws_server, event_logger,
                        calibrate=calibrate, verbose=args.verbose
                    )
                )

                # Wait for shutdown or task completion
                done, pending = await asyncio.wait(
                    [asyncio.create_task(stop_event.wait()), detection_task],
                    return_when=asyncio.FIRST_COMPLETED
                )

                for task in pending:
                    task.cancel()

            except LSLConnectionError as e:
                logger.error(f"LSL connection error: {e}")
                sys.exit(1)
            finally:
                await receiver.disconnect()

    finally:
        # Cleanup
        logger.info("Shutting down...")

        event_logger.close()
        await bonjour.unregister()
        await ws_server.stop()

        if openmuse_proc:
            openmuse_proc.stop()

        logger.info(f"Total events: {ws_server.event_count}")
        logger.info("Done")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.error(f"Fatal error: {e}")
        sys.exit(1)
