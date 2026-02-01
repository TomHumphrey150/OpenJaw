"""
WebSocket server for broadcasting jaw clench events to iOS app.

Maintains v1 protocol compatibility so the existing iOS app works unchanged.
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Callable, Optional, Set

import websockets
from websockets.server import WebSocketServerProtocol

logger = logging.getLogger(__name__)


class WebSocketServer:
    """
    WebSocket server for broadcasting jaw clench events.

    Protocol (v1-compatible):
        On connect: {"event": "connected", "timestamp": "...", "total_events": N}
        On clench:  {"event": "jaw_clench", "timestamp": "...", "count": N}
    """

    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 8765,
        on_client_connect: Optional[Callable[[str], None]] = None,
        on_client_disconnect: Optional[Callable[[str], None]] = None
    ):
        """
        Initialize the WebSocket server.

        Args:
            host: Host address to bind to
            port: Port to listen on
            on_client_connect: Optional callback when client connects
            on_client_disconnect: Optional callback when client disconnects
        """
        self.host = host
        self.port = port
        self.on_client_connect = on_client_connect
        self.on_client_disconnect = on_client_disconnect

        self._clients: Set[WebSocketServerProtocol] = set()
        self._server = None
        self._event_count = 0
        self._running = False

    @property
    def client_count(self) -> int:
        """Get the number of connected clients."""
        return len(self._clients)

    @property
    def event_count(self) -> int:
        """Get the total number of events broadcast."""
        return self._event_count

    @property
    def is_running(self) -> bool:
        """Check if server is running."""
        return self._running

    async def start(self) -> None:
        """Start the WebSocket server."""
        self._server = await websockets.serve(
            self._handle_client,
            self.host,
            self.port
        )
        self._running = True
        logger.info(f"WebSocket server listening on {self.host}:{self.port}")

    async def stop(self) -> None:
        """Stop the WebSocket server."""
        if self._server:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
            self._running = False
            logger.info("WebSocket server stopped")

    async def broadcast_jaw_clench(self) -> None:
        """
        Broadcast a jaw clench event to all connected clients.

        Increments the event counter and sends the v1-compatible payload.
        """
        self._event_count += 1

        payload = {
            "event": "jaw_clench",
            "timestamp": datetime.now().isoformat(),
            "count": self._event_count
        }

        await self._broadcast(payload)
        logger.info(f"Jaw clench event #{self._event_count} broadcast to {self.client_count} client(s)")

    async def _broadcast(self, payload: dict) -> None:
        """Broadcast a message to all connected clients."""
        if not self._clients:
            logger.debug("No clients connected, skipping broadcast")
            return

        message = json.dumps(payload)
        disconnected: Set[WebSocketServerProtocol] = set()

        for client in self._clients:
            try:
                await client.send(message)
            except websockets.exceptions.ConnectionClosed:
                disconnected.add(client)
            except Exception as e:
                logger.error(f"Error broadcasting to client: {e}")
                disconnected.add(client)

        # Clean up disconnected clients
        for client in disconnected:
            self._clients.discard(client)

    async def _handle_client(
        self,
        websocket: WebSocketServerProtocol,
        path: str = ""
    ) -> None:
        """Handle a WebSocket client connection."""
        client_id = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
        logger.info(f"Client connected: {client_id}")

        # Register client
        self._clients.add(websocket)

        if self.on_client_connect:
            try:
                self.on_client_connect(client_id)
            except Exception as e:
                logger.error(f"Error in on_client_connect callback: {e}")

        try:
            # Send welcome message (v1-compatible)
            welcome = {
                "event": "connected",
                "timestamp": datetime.now().isoformat(),
                "total_events": self._event_count
            }
            await websocket.send(json.dumps(welcome))

            # Keep connection alive and handle incoming messages
            async for message in websocket:
                logger.debug(f"Received from {client_id}: {message}")
                # For v2, we don't expect messages from client, but log them

        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Client disconnected: {client_id}")
        except Exception as e:
            logger.error(f"Error with client {client_id}: {e}")
        finally:
            # Unregister client
            self._clients.discard(websocket)

            if self.on_client_disconnect:
                try:
                    self.on_client_disconnect(client_id)
                except Exception as e:
                    logger.error(f"Error in on_client_disconnect callback: {e}")

            logger.info(f"Client removed: {client_id} (active: {self.client_count})")

    async def __aenter__(self) -> "WebSocketServer":
        """Async context manager entry."""
        await self.start()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Async context manager exit."""
        await self.stop()
