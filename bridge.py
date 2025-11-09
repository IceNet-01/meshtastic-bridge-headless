#!/usr/bin/env python3
"""
Meshtastic Bridge - Bridges messages between LongFast and LongModerate channels
"""

import time
import json
import logging
import signal
from datetime import datetime, timedelta
from pathlib import Path
from threading import Thread, Lock
from collections import deque
from typing import Optional, Dict, Any, Tuple, List, Deque
import meshtastic
import meshtastic.serial_interface
from pubsub import pub

from device_manager import DeviceManager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MessageTracker:
    """Tracks messages to prevent duplicate forwarding and loops"""

    def __init__(self, max_age_minutes=10, max_messages=1000, max_log_size=10000):
        self.max_age = timedelta(minutes=max_age_minutes)
        self.max_messages = max_messages
        self.messages = deque(maxlen=max_messages)
        self.lock = Lock()
        # Use bounded deque to prevent memory leak in long-running deployments
        self.message_log = deque(maxlen=max_log_size)

    def add_message(self, msg_id: int, from_node: str, to_node: str, text: str, channel: int) -> Dict[str, Any]:
        """Add a message to the tracker"""
        with self.lock:
            entry: Dict[str, Any] = {
                'id': msg_id,
                'from': from_node,
                'to': to_node,
                'text': text,
                'channel': channel,
                'timestamp': datetime.now(),
                'forwarded': False
            }
            self.messages.append(entry)
            self.message_log.append(entry)
            self._cleanup()
            return entry

    def has_seen(self, msg_id: int) -> bool:
        """Check if we've already seen this message"""
        with self.lock:
            self._cleanup()
            return any(msg['id'] == msg_id for msg in self.messages)

    def mark_forwarded(self, msg_id: int) -> bool:
        """Mark a message as forwarded"""
        with self.lock:
            for msg in self.messages:
                if msg['id'] == msg_id:
                    msg['forwarded'] = True
                    return True
            return False

    def _cleanup(self) -> None:
        """Remove old messages"""
        cutoff = datetime.now() - self.max_age
        while self.messages and self.messages[0]['timestamp'] < cutoff:
            self.messages.popleft()

    def get_recent_messages(self, count: int = 50) -> List[Dict[str, Any]]:
        """Get recent messages for display"""
        with self.lock:
            return list(self.messages)[-count:]

    def get_stats(self) -> Dict[str, int]:
        """Get statistics about message tracking"""
        with self.lock:
            total = len(self.message_log)
            forwarded = sum(1 for msg in self.message_log if msg['forwarded'])
            return {
                'total_seen': total,
                'total_forwarded': forwarded,
                'currently_tracked': len(self.messages)
            }


class MeshtasticBridge:
    """Main bridge class that connects two Meshtastic radios"""

    def __init__(self, port1: Optional[str] = None, port2: Optional[str] = None, auto_detect: bool = True):
        self.port1: Optional[str] = port1
        self.port2: Optional[str] = port2
        self.auto_detect: bool = auto_detect
        self.interface1: Optional[Any] = None  # meshtastic.serial_interface.SerialInterface
        self.interface2: Optional[Any] = None  # meshtastic.serial_interface.SerialInterface
        self.tracker: MessageTracker = MessageTracker()
        self.running: bool = False
        self.stats: Dict[str, Dict[str, int]] = {
            'radio1': {'received': 0, 'sent': 0, 'errors': 0},
            'radio2': {'received': 0, 'sent': 0, 'errors': 0}
        }
        self.lock: Lock = Lock()
        self.radio_settings: Dict[str, Dict[str, Any]] = {}
        self.start_time: float = time.time()

        # Health check tracking for automatic radio recovery
        self.health_failures: Dict[str, int] = {
            'radio1': 0,
            'radio2': 0
        }
        self.max_health_failures: int = 3  # Reboot radio after 3 consecutive failures

        # Channel configurations
        self.channel_map: Dict[str, str] = {
            'LongFast': 'LongModerate',
            'LongModerate': 'LongFast'
        }

    def connect_with_retry(self, port: str, radio_name: str, max_retries: int = 5, initial_delay: int = 2) -> Any:
        """
        Connect to a radio with retry logic and exponential backoff

        Args:
            port: Serial port path
            radio_name: Name for logging (e.g., "radio1")
            max_retries: Maximum number of connection attempts
            initial_delay: Initial delay in seconds (doubles each retry)

        Returns:
            Connected SerialInterface object

        Raises:
            RuntimeError: If connection fails after all retries
        """
        for attempt in range(max_retries):
            try:
                logger.info(f"Connecting to {radio_name} on {port} (attempt {attempt + 1}/{max_retries})...")
                interface = meshtastic.serial_interface.SerialInterface(port)
                time.sleep(2)  # Wait for connection to stabilize
                logger.info(f"{radio_name} connected successfully on {port}")
                return interface
            except Exception as e:
                delay = initial_delay * (2 ** attempt)  # Exponential backoff
                logger.warning(f"Connection attempt {attempt + 1}/{max_retries} failed for {radio_name}: {e}")

                if attempt < max_retries - 1:
                    logger.info(f"Retrying {radio_name} in {delay} seconds...")
                    time.sleep(delay)
                else:
                    logger.error(f"Failed to connect to {radio_name} after {max_retries} attempts")
                    raise RuntimeError(f"Could not connect to {radio_name} on {port} after {max_retries} attempts: {e}")

    def connect(self):
        """Connect to both radios (with auto-detection if needed)"""
        # Auto-detect radios if ports not specified
        if (not self.port1 or not self.port2) and self.auto_detect:
            logger.info("Auto-detecting Meshtastic radios...")
            devices = DeviceManager.auto_detect_radios(required_count=2)

            if len(devices) < 2:
                raise RuntimeError(f"Auto-detection found only {len(devices)} radio(s), need 2")

            self.port1 = devices[0][0]
            self.port2 = devices[1][0]
            logger.info(f"Auto-detected: Radio 1 on {self.port1}, Radio 2 on {self.port2}")

        # Connect to radio 1 with retry logic
        try:
            self.interface1 = self.connect_with_retry(self.port1, "Radio 1")
            # Check settings
            self.radio_settings['radio1'] = DeviceManager.check_radio_settings(
                self.interface1, self.port1
            )
        except Exception as e:
            logger.error(f"Failed to connect to radio 1: {e}")
            raise

        # Connect to radio 2 with retry logic
        try:
            self.interface2 = self.connect_with_retry(self.port2, "Radio 2")
            # Check settings
            self.radio_settings['radio2'] = DeviceManager.check_radio_settings(
                self.interface2, self.port2
            )
        except Exception as e:
            logger.error(f"Failed to connect to radio 2: {e}")
            # Clean up radio 1 connection
            if self.interface1:
                try:
                    self.interface1.close()
                except:
                    pass
            raise

        # Log settings and recommendations
        for radio_name, settings in self.radio_settings.items():
            logger.info(f"{radio_name} settings: {settings.get('node_id', 'unknown')}")
            if settings.get('recommendations'):
                for rec in settings['recommendations']:
                    logger.warning(f"{radio_name}: {rec}")

        # Subscribe to message events
        pub.subscribe(self._on_receive_radio1, "meshtastic.receive")

        self.running = True
        logger.info("Bridge is now running")

    def _on_receive_radio1(self, packet, interface):
        """Handle messages received on radio 1"""
        try:
            # Determine which radio received this
            if interface == self.interface1:
                self._handle_message(packet, 'radio1', self.interface2)
            elif interface == self.interface2:
                self._handle_message(packet, 'radio2', self.interface1)
        except Exception as e:
            logger.error(f"Error handling message: {e}")

    def _handle_message(self, packet, source_radio, target_interface):
        """Process and forward a message"""
        try:
            # Extract message details
            if 'decoded' not in packet:
                return

            decoded = packet['decoded']

            # Only handle text messages
            if decoded.get('portnum') != 'TEXT_MESSAGE_APP':
                return

            msg_id = packet.get('id', 0)
            from_node = packet.get('fromId', 'unknown')
            to_node = packet.get('toId', 'unknown')

            # Get the text payload
            payload = decoded.get('payload', b'')
            if isinstance(payload, bytes):
                text = payload.decode('utf-8', errors='ignore')
            else:
                text = str(payload)

            # Get channel info
            channel = packet.get('channel', 0)

            # Check if we've already seen this message
            if self.tracker.has_seen(msg_id):
                logger.debug(f"Already seen message {msg_id}, skipping")
                return

            # Add to tracker
            self.tracker.add_message(msg_id, from_node, to_node, text, channel)

            with self.lock:
                self.stats[source_radio]['received'] += 1

            logger.info(f"[{source_radio}] Received from {from_node}: {text}")

            # Forward to the other radio
            try:
                target_interface.sendText(text, channelIndex=channel)
                self.tracker.mark_forwarded(msg_id)

                target_radio = 'radio2' if source_radio == 'radio1' else 'radio1'
                with self.lock:
                    self.stats[target_radio]['sent'] += 1

                logger.info(f"[{source_radio} -> {target_radio}] Forwarded message")
            except Exception as e:
                logger.error(f"Failed to forward message: {e}")
                target_radio = 'radio2' if source_radio == 'radio1' else 'radio1'
                with self.lock:
                    self.stats[target_radio]['errors'] += 1

        except Exception as e:
            logger.error(f"Error in _handle_message: {e}")

    def get_stats(self) -> Dict[str, Any]:
        """Get bridge statistics"""
        with self.lock:
            return {
                **self.stats,
                'tracker': self.tracker.get_stats()
            }

    def get_recent_messages(self) -> List[Dict[str, Any]]:
        """Get recent messages"""
        return self.tracker.get_recent_messages()

    def send_message(self, text: str, radio: str = 'radio1', channel: int = 0) -> bool:
        """Send a message through specified radio"""
        interface = self.interface1 if radio == 'radio1' else self.interface2
        try:
            interface.sendText(text, channelIndex=channel)
            logger.info(f"Sent message via {radio}: {text}")
            return True
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            return False

    def get_node_info(self, radio: str = 'radio1') -> Optional[Dict[str, Any]]:
        """Get node information from a radio"""
        interface = self.interface1 if radio == 'radio1' else self.interface2
        try:
            if hasattr(interface, 'myInfo'):
                return interface.myInfo
            return None
        except Exception as e:
            logger.error(f"Failed to get node info: {e}")
            return None

    def close(self) -> None:
        """Close connections to both radios"""
        self.running = False
        logger.info("Closing bridge connections...")

        if self.interface1:
            try:
                self.interface1.close()
            except Exception as e:
                logger.error(f"Error closing radio 1: {e}")

        if self.interface2:
            try:
                self.interface2.close()
            except Exception as e:
                logger.error(f"Error closing radio 2: {e}")

        logger.info("Bridge closed")

    def get_uptime(self) -> float:
        """Get bridge uptime in seconds"""
        return time.time() - self.start_time

    def reboot_radio(self, radio_name: str) -> bool:
        """
        Send reboot command to a specific radio

        Args:
            radio_name: 'radio1' or 'radio2'

        Returns:
            True if reboot command sent successfully, False otherwise
        """
        try:
            interface = self.interface1 if radio_name == 'radio1' else self.interface2
            port = self.port1 if radio_name == 'radio1' else self.port2

            if not interface:
                logger.error(f"Cannot reboot {radio_name}: no interface available")
                return False

            logger.warning(f"Sending reboot command to {radio_name} on {port}")

            # Send reboot command via the Meshtastic interface
            # The reboot() method sends a reboot request to the device
            if hasattr(interface, 'getNode') and hasattr(interface.getNode('^local'), 'reboot'):
                interface.getNode('^local').reboot()
                logger.info(f"Reboot command sent to {radio_name}")

                # Close the interface
                try:
                    interface.close()
                except:
                    pass

                # Wait for radio to reboot
                logger.info(f"Waiting 10 seconds for {radio_name} to reboot...")
                time.sleep(10)

                # Reconnect
                logger.info(f"Reconnecting to {radio_name}...")
                new_interface = self.connect_with_retry(port, radio_name, max_retries=3)

                if radio_name == 'radio1':
                    self.interface1 = new_interface
                else:
                    self.interface2 = new_interface

                logger.info(f"{radio_name} successfully rebooted and reconnected")
                return True
            else:
                logger.warning(f"Reboot method not available for {radio_name}, attempting manual reconnect")
                # Fallback: close and reconnect
                try:
                    interface.close()
                except:
                    pass

                time.sleep(5)
                new_interface = self.connect_with_retry(port, radio_name, max_retries=3)

                if radio_name == 'radio1':
                    self.interface1 = new_interface
                else:
                    self.interface2 = new_interface

                return True

        except Exception as e:
            logger.error(f"Failed to reboot {radio_name}: {e}")
            return False

    def write_health_status(self, status_file: str = '/tmp/meshtastic-bridge-status.json') -> None:
        """
        Write health status to a JSON file for external monitoring

        Args:
            status_file: Path to status file (default: /tmp/meshtastic-bridge-status.json)
        """
        try:
            status = {
                'running': self.running,
                'radios_connected': bool(self.interface1 and self.interface2),
                'uptime_seconds': self.get_uptime(),
                'stats': self.get_stats(),
                'timestamp': time.time(),
                'ports': {
                    'radio1': self.port1,
                    'radio2': self.port2
                },
                'health_failures': self.health_failures
            }

            with open(status_file, 'w') as f:
                json.dump(status, f, indent=2)

            logger.debug(f"Health status written to {status_file}")
        except Exception as e:
            logger.warning(f"Failed to write health status: {e}")

    def health_check(self) -> bool:
        """
        Verify radios are still responsive
        Automatically reboots radios after consecutive failures

        Returns:
            True if both radios are healthy, False otherwise
        """
        try:
            radio1_ok = False
            radio2_ok = False

            # Check radio 1
            if self.interface1:
                try:
                    # Verify interface is responsive
                    if hasattr(self.interface1, 'myInfo'):
                        radio1_ok = True
                        # Reset failure counter on success
                        self.health_failures['radio1'] = 0
                except Exception as e:
                    logger.warning(f"Radio 1 health check failed: {e}")

            # Check radio 2
            if self.interface2:
                try:
                    # Verify interface is responsive
                    if hasattr(self.interface2, 'myInfo'):
                        radio2_ok = True
                        # Reset failure counter on success
                        self.health_failures['radio2'] = 0
                except Exception as e:
                    logger.warning(f"Radio 2 health check failed: {e}")

            # Handle Radio 1 failures
            if not radio1_ok:
                self.health_failures['radio1'] += 1
                logger.warning(f"Radio 1 health check failed ({self.health_failures['radio1']}/{self.max_health_failures})")

                if self.health_failures['radio1'] >= self.max_health_failures:
                    logger.error(f"Radio 1 has failed {self.max_health_failures} consecutive health checks - attempting reboot")
                    if self.reboot_radio('radio1'):
                        self.health_failures['radio1'] = 0  # Reset on successful reboot
                        radio1_ok = True
                    else:
                        logger.error("Radio 1 reboot failed - will retry on next health check")

            # Handle Radio 2 failures
            if not radio2_ok:
                self.health_failures['radio2'] += 1
                logger.warning(f"Radio 2 health check failed ({self.health_failures['radio2']}/{self.max_health_failures})")

                if self.health_failures['radio2'] >= self.max_health_failures:
                    logger.error(f"Radio 2 has failed {self.max_health_failures} consecutive health checks - attempting reboot")
                    if self.reboot_radio('radio2'):
                        self.health_failures['radio2'] = 0  # Reset on successful reboot
                        radio2_ok = True
                    else:
                        logger.error("Radio 2 reboot failed - will retry on next health check")

            # Log overall health status
            if not (radio1_ok and radio2_ok):
                logger.warning(f"Health check incomplete (Radio 1: {radio1_ok}, Radio 2: {radio2_ok})")

            return radio1_ok and radio2_ok

        except Exception as e:
            logger.error(f"Health check error: {e}")
            return False


def main():
    """Main entry point for the bridge"""
    import sys

    # Support both auto-detection and manual port specification
    if len(sys.argv) == 3:
        # Manual mode
        port1 = sys.argv[1]
        port2 = sys.argv[2]
        print(f"Using specified ports: {port1} and {port2}")
        bridge = MeshtasticBridge(port1, port2, auto_detect=False)
    elif len(sys.argv) == 1:
        # Auto-detection mode
        print("Auto-detecting Meshtastic radios...")
        print("Please ensure both radios are connected via USB.")
        bridge = MeshtasticBridge(auto_detect=True)
    else:
        print("Usage: python bridge.py [port1] [port2]")
        print("")
        print("Auto-detection mode (recommended):")
        print("  python bridge.py")
        print("")
        print("Manual mode:")
        print("  python bridge.py /dev/ttyUSB0 /dev/ttyUSB1")
        sys.exit(1)

    # Signal handler for graceful shutdown
    def signal_handler(signum, frame):
        """Handle shutdown signals gracefully"""
        sig_name = signal.Signals(signum).name
        logger.info(f"Received signal {sig_name} ({signum}), initiating graceful shutdown...")
        print(f"\nReceived {sig_name}, shutting down gracefully...")
        bridge.running = False

    # Register signal handlers
    signal.signal(signal.SIGTERM, signal_handler)  # Systemd stop
    signal.signal(signal.SIGINT, signal_handler)   # Ctrl+C

    try:
        bridge.connect()
        logger.info("Bridge is running. Press Ctrl+C to stop.")
        print("Bridge is running. Press Ctrl+C to stop.")

        # Health monitoring counters
        health_check_interval = 60  # Check every 60 seconds
        status_write_interval = 30  # Write status every 30 seconds
        loop_counter = 0

        while bridge.running:
            time.sleep(1)
            loop_counter += 1

            # Perform health check periodically
            if loop_counter % health_check_interval == 0:
                bridge.health_check()

            # Write health status periodically
            if loop_counter % status_write_interval == 0:
                bridge.write_health_status()

        logger.info("Main loop exited, cleaning up...")

    except KeyboardInterrupt:
        # This should rarely happen now that we have signal handlers
        logger.info("Received KeyboardInterrupt")
        print("\nStopping bridge...")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        print(f"Error: {e}")
    finally:
        logger.info("Closing bridge connections...")
        bridge.close()
        logger.info("Shutdown complete")


if __name__ == "__main__":
    main()
