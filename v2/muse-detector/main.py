#!/usr/bin/env python3
"""
Skywalker v2: Muse Jaw Clench Detector

Connects to OpenMuse LSL stream, detects jaw clenches via EMG extraction,
and broadcasts events via WebSocket to the iOS app.

Usage:
    python main.py --calibrate --verbose
    python main.py --threshold 2.5
    python main.py --test  # Simulate events without Muse
"""

import argparse
import asyncio
import json
import logging
import signal
import sys
from datetime import datetime
from pathlib import Path

import numpy as np

from detector import JawClenchDetector
from server import WebSocketServer, BonjourService
from streaming import LSLReceiver, LSLConnectionError
from utils import EventLogger

# Load configuration
CONFIG_FILE = Path(__file__).parent / "config.json"
with open(CONFIG_FILE) as f:
    CONFIG = json.load(f)

# Logging setup
LOG_DIR = Path(__file__).parent / CONFIG["logging"]["directory"]
LOG_DIR.mkdir(exist_ok=True)
log_file = LOG_DIR / f"detector_{datetime.now().strftime('%Y-%m-%d')}.log"


def setup_logging(verbose: bool = False) -> None:
    """Configure logging to file and console."""
    level = logging.DEBUG if verbose else logging.INFO

    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )


logger = logging.getLogger(__name__)


async def test_event_generator(ws_server: WebSocketServer) -> None:
    """Generate fake jaw clench events every 5 seconds for testing."""
    logger.info("TEST MODE: Generating events every 5 seconds")

    while True:
        await asyncio.sleep(5)
        await ws_server.broadcast_jaw_clench()
        logger.info(f"TEST MODE: Simulated jaw clench #{ws_server.event_count}")


async def detection_loop(
    receiver: LSLReceiver,
    detector: JawClenchDetector,
    ws_server: WebSocketServer,
    event_logger: EventLogger,
    calibrate: bool = True
) -> None:
    """
    Main detection loop: read EEG, detect clenches, broadcast events.

    Args:
        receiver: LSL stream receiver
        detector: Jaw clench detector
        ws_server: WebSocket server for broadcasting
        event_logger: Event logger for analysis
        calibrate: Whether to run calibration phase
    """
    # Track calibration phase transitions for user guidance
    last_phase = None
    calibration_logged = False

    if calibrate:
        logger.info("=" * 60)
        logger.info("MVC CALIBRATION - Two phases:")
        logger.info("  Phase 1: Keep jaw RELAXED (establishes baseline)")
        logger.info("  Phase 2: CLENCH JAW HARD (establishes your maximum)")
        logger.info("=" * 60)
        logger.info("")
        logger.info("Starting Phase 1: Keep your jaw RELAXED...")

    async for chunk in receiver.stream():
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

            # Show calibration progress
            progress = detector.calibration_progress * 100
            if int(progress) % 20 == 0 and progress > 0:
                logger.debug(f"Calibration: {progress:.0f}%")
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

            event_logger.log_calibration(
                baseline_mean=detector.relaxed_baseline,
                baseline_std=0.0,  # Not used in MVC mode
                threshold=result.threshold,
                samples=int(
                    (detector.relaxed_calibration_seconds + detector.clench_calibration_seconds)
                    * detector.sample_rate
                )
            )

        # Handle jaw clench detection
        if result.is_clenching:
            envelope_max = float(np.max(result.envelope)) if len(result.envelope) > 0 else 0.0

            logger.info(f"JAW CLENCH DETECTED! Envelope: {envelope_max:.2f} (threshold: {result.threshold:.2f})")

            # Broadcast to iOS app
            await ws_server.broadcast_jaw_clench()

            # Log for analysis
            event_logger.log_jaw_clench(
                envelope_max=envelope_max,
                threshold=result.threshold,
                baseline_mean=detector.relaxed_baseline,
                baseline_std=0.0
            )


async def main() -> None:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Skywalker v2: Muse Jaw Clench Detector"
    )
    parser.add_argument(
        "--calibrate",
        action="store_true",
        default=True,
        help="Run calibration before detection (default: True)"
    )
    parser.add_argument(
        "--no-calibrate",
        action="store_true",
        help="Skip calibration (use default threshold)"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=CONFIG["detector"]["mvc_threshold_percent"],
        help=f"Threshold as %% of max clench (default: {CONFIG['detector']['mvc_threshold_percent']:.0%})"
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Test mode: simulate events every 5 seconds (no Muse needed)"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable debug logging"
    )

    args = parser.parse_args()
    calibrate = not args.no_calibrate

    setup_logging(args.verbose)

    logger.info("=" * 60)
    logger.info("Skywalker v2: Muse Jaw Clench Detector")
    if args.test:
        logger.info("TEST MODE - Simulating events every 5 seconds")
    logger.info("=" * 60)
    logger.info(f"Log file: {log_file}")
    logger.info(f"Threshold: {args.threshold:.0%} of max clench")
    logger.info("")

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
        logger.info("\nShutdown signal received...")
        stop_event.set()

    loop.add_signal_handler(signal.SIGINT, signal_handler)
    loop.add_signal_handler(signal.SIGTERM, signal_handler)

    try:
        # Start WebSocket server and Bonjour
        await ws_server.start()
        local_ip = await bonjour.register()

        logger.info("")
        logger.info(f"WebSocket server: ws://{local_ip}:{CONFIG['websocket']['port']}")
        logger.info("iOS app will auto-discover via Bonjour")
        logger.info("")
        logger.info("Press Ctrl+C to stop")
        logger.info("=" * 60)

        event_logger.open()

        if args.test:
            # Test mode: generate fake events
            test_task = asyncio.create_task(test_event_generator(ws_server))
            await stop_event.wait()
            test_task.cancel()
        else:
            # Normal mode: connect to LSL and detect
            receiver = LSLReceiver(
                stream_name=CONFIG["lsl"]["stream_name"],
                channels=CONFIG["lsl"]["channels"],
                poll_interval_ms=CONFIG["lsl"]["poll_interval_ms"]
            )

            try:
                await receiver.connect()

                detection_task = asyncio.create_task(
                    detection_loop(receiver, detector, ws_server, event_logger, calibrate)
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
                logger.error("")
                logger.error("Make sure OpenMuse is streaming:")
                logger.error("  1. OpenMuse find")
                logger.error("  2. OpenMuse stream --address <muse-address>")
                sys.exit(1)
            finally:
                await receiver.disconnect()

    finally:
        # Cleanup
        logger.info("Shutting down...")
        event_logger.close()
        await bonjour.unregister()
        await ws_server.stop()

        logger.info(f"Total events: {ws_server.event_count}")
        logger.info("Detector stopped")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)
