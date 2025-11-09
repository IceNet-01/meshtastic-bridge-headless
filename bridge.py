#!/usr/bin/env python3
"""
Meshtastic Bridge - Bridges messages between LongFast and LongModerate channels
"""

import time
import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from threading import Thread, Lock
from collections import deque
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

    def __init__(self, max_age_minutes=10, max_messages=1000):
        self.max_age = timedelta(minutes=max_age_minutes)
        self.max_messages = max_messages
        self.messages = deque(maxlen=max_messages)
        self.lock = Lock()
        self.message_log = []

    def add_message(self, msg_id, from_node, to_node, text, channel):
        """Add a message to the tracker"""
        with self.lock:
            entry = {
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

    def has_seen(self, msg_id):
        """Check if we've already seen this message"""
        with self.lock:
            self._cleanup()
            return any(msg['id'] == msg_id for msg in self.messages)

    def mark_forwarded(self, msg_id):
        """Mark a message as forwarded"""
        with self.lock:
            for msg in self.messages:
                if msg['id'] == msg_id:
                    msg['forwarded'] = True
                    return True
            return False

    def _cleanup(self):
        """Remove old messages"""
        cutoff = datetime.now() - self.max_age
        while self.messages and self.messages[0]['timestamp'] < cutoff:
            self.messages.popleft()

    def get_recent_messages(self, count=50):
        """Get recent messages for display"""
        with self.lock:
            return list(self.messages)[-count:]

    def get_stats(self):
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

    def __init__(self, port1=None, port2=None, auto_detect=True):
        self.port1 = port1
        self.port2 = port2
        self.auto_detect = auto_detect
        self.interface1 = None
        self.interface2 = None
        self.tracker = MessageTracker()
        self.running = False
        self.stats = {
            'radio1': {'received': 0, 'sent': 0, 'errors': 0},
            'radio2': {'received': 0, 'sent': 0, 'errors': 0}
        }
        self.lock = Lock()
        self.radio_settings = {}

        # Channel configurations
        self.channel_map = {
            'LongFast': 'LongModerate',
            'LongModerate': 'LongFast'
        }

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

        logger.info(f"Connecting to radio 1 on {self.port1}...")
        try:
            self.interface1 = meshtastic.serial_interface.SerialInterface(self.port1)
            time.sleep(2)  # Wait for connection to stabilize
            logger.info("Radio 1 connected successfully")

            # Check settings
            self.radio_settings['radio1'] = DeviceManager.check_radio_settings(
                self.interface1, self.port1
            )
        except Exception as e:
            logger.error(f"Failed to connect to radio 1: {e}")
            raise

        logger.info(f"Connecting to radio 2 on {self.port2}...")
        try:
            self.interface2 = meshtastic.serial_interface.SerialInterface(self.port2)
            time.sleep(2)  # Wait for connection to stabilize
            logger.info("Radio 2 connected successfully")

            # Check settings
            self.radio_settings['radio2'] = DeviceManager.check_radio_settings(
                self.interface2, self.port2
            )
        except Exception as e:
            logger.error(f"Failed to connect to radio 2: {e}")
            if self.interface1:
                self.interface1.close()
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

    def get_stats(self):
        """Get bridge statistics"""
        with self.lock:
            return {
                **self.stats,
                'tracker': self.tracker.get_stats()
            }

    def get_recent_messages(self):
        """Get recent messages"""
        return self.tracker.get_recent_messages()

    def send_message(self, text, radio='radio1', channel=0):
        """Send a message through specified radio"""
        interface = self.interface1 if radio == 'radio1' else self.interface2
        try:
            interface.sendText(text, channelIndex=channel)
            logger.info(f"Sent message via {radio}: {text}")
            return True
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            return False

    def get_node_info(self, radio='radio1'):
        """Get node information from a radio"""
        interface = self.interface1 if radio == 'radio1' else self.interface2
        try:
            if hasattr(interface, 'myInfo'):
                return interface.myInfo
            return None
        except Exception as e:
            logger.error(f"Failed to get node info: {e}")
            return None

    def close(self):
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

    try:
        bridge.connect()
        print("Bridge is running. Press Ctrl+C to stop.")

        while bridge.running:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\nStopping bridge...")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
    finally:
        bridge.close()


if __name__ == "__main__":
    main()
