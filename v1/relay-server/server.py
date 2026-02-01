#!/usr/bin/env python3
"""
Bruxism Biofeedback Relay Server

Receives OSC/UDP messages from Mind Monitor (iPhone 1) and forwards
jaw clench events via WebSocket to iPhone 2.

Architecture:
  Mind Monitor (OSC/UDP) -> This Server (WebSocket) -> iPhone 2 App

Optional data collection mode (--collect):
  Records raw EEG/ACC/GYRO data to JSONL for ML training.
"""

import argparse
import asyncio
import json
import logging
import signal
import socket
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional, Set

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import AsyncIOOSCUDPServer
import websockets
from websockets.server import WebSocketServerProtocol
from zeroconf import ServiceInfo, Zeroconf

from data_collector import DataCollector

# Configuration
OSC_IP = "0.0.0.0"  # Listen on all interfaces
OSC_PORT = 5000
WEBSOCKET_IP = "0.0.0.0"
WEBSOCKET_PORT = 8765

# Session timestamp for log files
SESSION_TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")

# Logging setup with session timestamp
LOG_DIR = Path(__file__).parent / "logs"
LOG_DIR.mkdir(exist_ok=True)
log_file = LOG_DIR / f"relay_{SESSION_TIMESTAMP}.log"

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Global state
connected_clients: Set[WebSocketServerProtocol] = set()
event_count = 0
test_mode = False
collect_mode = False
zeroconf_instance = None
service_info = None
data_collector: Optional[DataCollector] = None


# ========== OSC Message Handlers ==========

def jaw_clench_handler(address: str, *args):
    """Handle /muse/elements/jaw_clench messages from Mind Monitor"""
    global event_count

    event_count += 1
    timestamp = datetime.now().isoformat()
    logger.info(f"[OSC] Jaw clench detected (#{event_count})")

    # Record to data collector if enabled
    if data_collector:
        data_collector.record_jaw_clench()

    # Create JSON payload for WebSocket clients
    payload = {
        "event": "jaw_clench",
        "timestamp": timestamp,
        "count": event_count
    }

    # Broadcast to all connected WebSocket clients
    asyncio.create_task(broadcast_to_clients(payload))


def eeg_handler(address: str, *args):
    """Handle /muse/eeg messages - raw EEG data (4 channels)"""
    if data_collector and len(args) >= 4:
        data_collector.record_eeg(
            tp9=float(args[0]),
            af7=float(args[1]),
            af8=float(args[2]),
            tp10=float(args[3])
        )


def acc_handler(address: str, *args):
    """Handle /muse/acc messages - accelerometer data (x, y, z)"""
    if data_collector and len(args) >= 3:
        data_collector.record_acc(
            x=float(args[0]),
            y=float(args[1]),
            z=float(args[2])
        )


def gyro_handler(address: str, *args):
    """Handle /muse/gyro messages - gyroscope data (x, y, z)"""
    if data_collector and len(args) >= 3:
        data_collector.record_gyro(
            x=float(args[0]),
            y=float(args[1]),
            z=float(args[2])
        )


def generic_osc_handler(address: str, *args):
    """Log all other OSC messages for debugging"""
    logger.debug(f"[OSC] {address}: {args}")


# ========== WebSocket Server ==========

async def websocket_handler(websocket: WebSocketServerProtocol, path: str):
    """Handle WebSocket connections from iPhone 2"""
    client_id = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
    logger.info(f"[WebSocket] Client connected: {client_id}")

    # Register client
    connected_clients.add(websocket)

    try:
        # Send welcome message with current stats
        welcome = {
            "event": "connected",
            "timestamp": datetime.now().isoformat(),
            "total_events": event_count
        }
        await websocket.send(json.dumps(welcome))

        # Keep connection alive and handle incoming messages (if any)
        async for message in websocket:
            logger.debug(f"[WebSocket] Received from {client_id}: {message}")
            # For MVP, we don't expect messages from client, but log them

    except websockets.exceptions.ConnectionClosed:
        logger.info(f"[WebSocket] Client disconnected: {client_id}")
    except Exception as e:
        logger.error(f"[WebSocket] Error with {client_id}: {e}")
    finally:
        # Unregister client
        connected_clients.discard(websocket)
        logger.info(f"[WebSocket] Client removed: {client_id} (active clients: {len(connected_clients)})")


async def broadcast_to_clients(payload: dict):
    """Broadcast message to all connected WebSocket clients"""
    if not connected_clients:
        logger.warning("[WebSocket] No clients connected, event not sent")
        return

    message = json.dumps(payload)
    logger.info(f"[WebSocket] Broadcasting to {len(connected_clients)} client(s): {message}")

    # Send to all clients concurrently
    disconnected = set()
    for client in connected_clients:
        try:
            await client.send(message)
        except websockets.exceptions.ConnectionClosed:
            logger.warning(f"[WebSocket] Client connection closed during broadcast")
            disconnected.add(client)
        except Exception as e:
            logger.error(f"[WebSocket] Error broadcasting to client: {e}")
            disconnected.add(client)

    # Clean up any disconnected clients
    for client in disconnected:
        connected_clients.discard(client)


# ========== Bonjour/mDNS Service Advertisement ==========

def get_local_ip():
    """Get the local IP address of this machine"""
    try:
        # Create a socket to determine the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"


async def start_bonjour_service():
    """Advertise the WebSocket server via Bonjour/mDNS"""
    global zeroconf_instance, service_info

    local_ip = get_local_ip()
    logger.info(f"[Bonjour] Local IP: {local_ip}")

    # Create Zeroconf instance
    zeroconf_instance = Zeroconf()

    # Define service type and name
    service_type = "_openjaw-relay._tcp.local."
    service_name = "OpenJaw Relay Server._openjaw-relay._tcp.local."

    # Create service info
    service_info = ServiceInfo(
        service_type,
        service_name,
        addresses=[socket.inet_aton(local_ip)],
        port=WEBSOCKET_PORT,
        properties={
            "version": "1.0",
            "protocol": "websocket"
        },
        server=f"{socket.gethostname()}.local."
    )

    # Register service (async)
    await zeroconf_instance.async_register_service(service_info)
    logger.info(f"[Bonjour] Service advertised as '{service_name}' on port {WEBSOCKET_PORT}")


async def stop_bonjour_service():
    """Unregister the Bonjour service"""
    global zeroconf_instance, service_info

    if zeroconf_instance and service_info:
        logger.info("[Bonjour] Unregistering service...")
        await zeroconf_instance.async_unregister_service(service_info)
        await zeroconf_instance.async_close()
        logger.info("[Bonjour] Service unregistered")


# ========== Server Initialization ==========

async def init_osc_server():
    """Initialize OSC/UDP server"""
    dispatcher = Dispatcher()

    # Map jaw clench events to handler
    dispatcher.map("/muse/elements/jaw_clench", jaw_clench_handler)

    # Map raw data streams (only processed if data_collector is active)
    dispatcher.map("/muse/eeg", eeg_handler)
    dispatcher.map("/muse/acc", acc_handler)
    dispatcher.map("/muse/gyro", gyro_handler)

    # Map all other messages to generic handler for debugging
    dispatcher.set_default_handler(generic_osc_handler)

    # Create and start OSC server
    server = AsyncIOOSCUDPServer(
        (OSC_IP, OSC_PORT),
        dispatcher,
        asyncio.get_event_loop()
    )

    transport, protocol = await server.create_serve_endpoint()
    logger.info(f"[OSC] Server listening on {OSC_IP}:{OSC_PORT}")

    return transport


async def init_websocket_server():
    """Initialize WebSocket server"""
    server = await websockets.serve(
        websocket_handler,
        WEBSOCKET_IP,
        WEBSOCKET_PORT
    )

    logger.info(f"[WebSocket] Server listening on {WEBSOCKET_IP}:{WEBSOCKET_PORT}")
    return server


# ========== Main ==========

async def test_event_generator():
    """Generate fake jaw clench events every 5 seconds for testing.

    Note: Data collection is automatically disabled in test mode,
    so these simulated events never get recorded to training data.
    """
    global event_count
    logger.info("[TEST MODE] Starting test event generator (every 5 seconds)")
    logger.info("[TEST MODE] No Muse headband connection needed")

    while True:
        await asyncio.sleep(5)
        event_count += 1
        timestamp = datetime.now().isoformat()

        logger.info(f"[TEST MODE] Simulated jaw clench (#{event_count})")

        payload = {
            "event": "jaw_clench",
            "timestamp": timestamp,
            "count": event_count
        }

        await broadcast_to_clients(payload)


async def main():
    """Run both OSC and WebSocket servers concurrently"""
    global test_mode, collect_mode, data_collector

    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Bruxism Biofeedback Relay Server")
    parser.add_argument("--test", action="store_true",
                        help="Enable test mode (simulates jaw clench events every 5 seconds, disables data collection)")
    parser.add_argument("--collect", action="store_true",
                        help="Enable data collection mode (records EEG/ACC/GYRO to JSONL)")
    args = parser.parse_args()

    test_mode = args.test
    collect_mode = args.collect

    # IMPORTANT: Test mode automatically disables data collection to prevent
    # polluting training data with simulated events
    if test_mode and collect_mode:
        logger.warning("TEST MODE: Data collection automatically disabled to prevent training data pollution")
        collect_mode = False

    # Log startup metadata
    logger.info("=" * 60)
    if test_mode:
        logger.info("Bruxism Biofeedback Relay Server - TEST MODE")
    else:
        logger.info("Bruxism Biofeedback Relay Server Starting")
    logger.info("=" * 60)
    logger.info(f"Session ID: {SESSION_TIMESTAMP}")
    logger.info(f"Python version: {sys.version}")
    logger.info(f"Command: {' '.join(sys.argv)}")
    logger.info(f"Log file: {log_file}")
    if test_mode:
        logger.info("")
        logger.info("*** TEST MODE ***")
        logger.info("- Simulating jaw clench events every 5 seconds")
        logger.info("- No Muse headband connection required")
        logger.info("- Data collection DISABLED (training data not polluted)")
        logger.info("")
    if collect_mode:
        logger.info("DATA COLLECTION MODE ENABLED - Recording EEG/ACC/GYRO to JSONL")

    # Initialize data collector if enabled
    if collect_mode:
        data_collector = DataCollector(
            output_dir="data/raw",
            buffer_size=1000,
            session_id=SESSION_TIMESTAMP
        )
        data_collector.start()
        logger.info(f"[Data Collection] Output file: {data_collector.output_file}")

    logger.info("")
    logger.info("Waiting for connections:")
    if not test_mode:
        logger.info(f"  - Mind Monitor (OSC/UDP): {OSC_IP}:{OSC_PORT}")
    logger.info(f"  - iPhone 2 App (WebSocket): {WEBSOCKET_IP}:{WEBSOCKET_PORT}")
    logger.info("")
    logger.info("Press Ctrl+C to stop")
    logger.info("=" * 60)

    # Start servers
    if not test_mode:
        osc_transport = await init_osc_server()
    else:
        osc_transport = None
        logger.info("[TEST MODE] OSC server NOT started - simulation only")

    websocket_server = await init_websocket_server()

    # Advertise via Bonjour
    await start_bonjour_service()

    # Start test event generator if in test mode
    test_task = None
    if test_mode:
        test_task = asyncio.create_task(test_event_generator())

    # Set up graceful shutdown
    loop = asyncio.get_event_loop()
    stop = loop.create_future()

    def signal_handler():
        logger.info("\n[Shutdown] Received interrupt signal, shutting down...")
        stop.set_result(None)

    loop.add_signal_handler(signal.SIGINT, signal_handler)
    loop.add_signal_handler(signal.SIGTERM, signal_handler)

    # Wait for shutdown signal
    await stop

    # Cancel test task if running
    if test_task:
        test_task.cancel()

    # Stop data collector and log stats
    if data_collector:
        stats = data_collector.stop()
        logger.info(f"[Data Collection] Session complete:")
        logger.info(f"  - Total samples: {stats['total_samples']:,}")
        logger.info(f"  - EEG samples: {stats['stream_counts']['eeg']:,}")
        logger.info(f"  - ACC samples: {stats['stream_counts']['acc']:,}")
        logger.info(f"  - GYRO samples: {stats['stream_counts']['gyro']:,}")
        logger.info(f"  - Jaw clench events: {stats['stream_counts']['jaw_clench']:,}")
        logger.info(f"  - Output file: {stats['output_file']}")

    # Cleanup
    logger.info("[Shutdown] Closing servers...")
    await stop_bonjour_service()
    if osc_transport:
        osc_transport.close()
    websocket_server.close()
    await websocket_server.wait_closed()

    logger.info(f"[Shutdown] Total events processed: {event_count}")
    logger.info("[Shutdown] Server stopped")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("\n[Shutdown] Keyboard interrupt received")
    except Exception as e:
        logger.error(f"[Error] Fatal error: {e}")
        sys.exit(1)
