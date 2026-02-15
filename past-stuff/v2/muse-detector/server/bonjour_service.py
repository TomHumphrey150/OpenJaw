"""
Bonjour/mDNS service advertisement for iOS app discovery.

Advertises the WebSocket server so the iOS app can auto-discover it
on the local network.
"""

import logging
import socket
from typing import Optional

from zeroconf import ServiceInfo, Zeroconf

logger = logging.getLogger(__name__)


def get_local_ip() -> str:
    """Get the local IP address of this machine."""
    try:
        # Create a socket to determine the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception:
        return "127.0.0.1"


class BonjourService:
    """
    Bonjour/mDNS service for advertising the WebSocket server.

    The iOS app uses this to discover the server on the local network
    without requiring manual IP configuration.
    """

    def __init__(
        self,
        service_type: str = "_skywalker-relay._tcp.local.",
        service_name: str = "Skywalker Muse Detector",
        port: int = 8765
    ):
        """
        Initialize the Bonjour service.

        Args:
            service_type: mDNS service type (must match iOS app expectation)
            service_name: Human-readable service name
            port: WebSocket server port
        """
        self.service_type = service_type
        self.service_name = service_name
        self.port = port

        self._zeroconf: Optional[Zeroconf] = None
        self._service_info: Optional[ServiceInfo] = None
        self._registered = False

    @property
    def is_registered(self) -> bool:
        """Check if service is currently registered."""
        return self._registered

    async def register(self) -> str:
        """
        Register the Bonjour service.

        Returns:
            The local IP address being advertised

        Raises:
            RuntimeError: If registration fails
        """
        local_ip = get_local_ip()
        logger.info(f"Local IP: {local_ip}")

        try:
            # Create Zeroconf instance
            self._zeroconf = Zeroconf()

            # Full service name includes the service type
            full_service_name = f"{self.service_name}.{self.service_type}"

            # Create service info
            self._service_info = ServiceInfo(
                self.service_type,
                full_service_name,
                addresses=[socket.inet_aton(local_ip)],
                port=self.port,
                properties={
                    "version": "2.0",
                    "protocol": "websocket",
                    "source": "muse-detector"
                },
                server=f"{socket.gethostname()}.local."
            )

            # Register service
            await self._zeroconf.async_register_service(self._service_info)
            self._registered = True

            logger.info(
                f"Bonjour service registered: {full_service_name} on port {self.port}"
            )

            return local_ip

        except Exception as e:
            logger.error(f"Failed to register Bonjour service: {e}")
            raise RuntimeError(f"Bonjour registration failed: {e}") from e

    async def unregister(self) -> None:
        """Unregister the Bonjour service."""
        if self._zeroconf and self._service_info:
            try:
                logger.info("Unregistering Bonjour service...")
                await self._zeroconf.async_unregister_service(self._service_info)
                await self._zeroconf.async_close()
                logger.info("Bonjour service unregistered")
            except Exception as e:
                logger.warning(f"Error unregistering Bonjour service: {e}")
            finally:
                self._zeroconf = None
                self._service_info = None
                self._registered = False

    async def __aenter__(self) -> "BonjourService":
        """Async context manager entry."""
        await self.register()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Async context manager exit."""
        await self.unregister()
