#!/usr/bin/env python3
"""
Device Manager - Auto-detection and configuration for Meshtastic radios
"""

import os
import time
import logging
import serial.tools.list_ports
import meshtastic.serial_interface

logger = logging.getLogger(__name__)


class DeviceManager:
    """Manages detection and configuration of Meshtastic devices"""

    @staticmethod
    def find_meshtastic_devices():
        """
        Auto-detect Meshtastic devices connected via USB
        Returns list of port names
        """
        logger.info("Scanning for Meshtastic devices...")

        # Common USB serial device patterns
        potential_ports = []

        # List all serial ports
        ports = serial.tools.list_ports.comports()

        for port in ports:
            # Check for common Meshtastic device patterns
            # ESP32-based devices often show up as CP210x or CH340
            if any(pattern in str(port) for pattern in [
                'CP210', 'CH340', 'USB', 'ACM', 'UART', 'Serial'
            ]):
                potential_ports.append(port.device)
                logger.info(f"Found potential device: {port.device} - {port.description}")

        # Also check /dev/tty* directly
        for prefix in ['/dev/ttyUSB', '/dev/ttyACM']:
            for i in range(10):
                port_name = f"{prefix}{i}"
                if os.path.exists(port_name) and port_name not in potential_ports:
                    potential_ports.append(port_name)

        return potential_ports

    @staticmethod
    def verify_meshtastic_device(port, timeout=10):
        """
        Verify that a port actually has a Meshtastic device
        Returns (success, info_dict)
        """
        logger.info(f"Verifying Meshtastic device on {port}...")

        try:
            # Try to connect with a short timeout
            interface = meshtastic.serial_interface.SerialInterface(port, debugOut=None)

            # Wait a moment for connection
            time.sleep(2)

            # Try to get node info
            info = {}
            if hasattr(interface, 'myInfo') and interface.myInfo:
                info['myInfo'] = interface.myInfo
                info['connected'] = True
                logger.info(f"Verified Meshtastic device on {port}")
            else:
                info['connected'] = False
                logger.warning(f"Device on {port} connected but no info available")

            # Try to get node database
            if hasattr(interface, 'nodes'):
                info['nodes'] = interface.nodes

            interface.close()
            return True, info

        except Exception as e:
            logger.warning(f"Port {port} is not a valid Meshtastic device: {e}")
            return False, {}

    @staticmethod
    def auto_detect_radios(required_count=2):
        """
        Automatically detect the required number of Meshtastic radios
        Returns list of (port, info) tuples
        """
        logger.info(f"Auto-detecting {required_count} Meshtastic radios...")

        # Find potential devices
        potential_ports = DeviceManager.find_meshtastic_devices()

        if not potential_ports:
            logger.error("No potential USB serial devices found!")
            return []

        logger.info(f"Found {len(potential_ports)} potential ports: {potential_ports}")

        # Verify each port
        verified_devices = []
        for port in potential_ports:
            success, info = DeviceManager.verify_meshtastic_device(port)
            if success:
                verified_devices.append((port, info))

            # Stop if we have enough
            if len(verified_devices) >= required_count:
                break

        logger.info(f"Detected {len(verified_devices)} verified Meshtastic device(s)")
        return verified_devices

    @staticmethod
    def check_radio_settings(interface, port_name):
        """
        Check and report radio settings
        Returns dict of settings and recommendations
        """
        logger.info(f"Checking settings for radio on {port_name}...")

        settings = {
            'port': port_name,
            'status': 'unknown',
            'recommendations': []
        }

        try:
            # Get node info
            if hasattr(interface, 'myInfo') and interface.myInfo:
                my_info = interface.myInfo
                settings['node_id'] = my_info.get('user', {}).get('id', 'unknown')
                settings['node_num'] = my_info.get('num', 'unknown')
                settings['hw_model'] = my_info.get('user', {}).get('hwModel', 'unknown')
                settings['status'] = 'connected'

            # Get channel info if available
            if hasattr(interface, 'localNode') and interface.localNode:
                local_node = interface.localNode

                # Try to get channels
                if hasattr(local_node, 'channels'):
                    channels = local_node.channels
                    settings['channels'] = []

                    for idx, channel in enumerate(channels):
                        if channel and hasattr(channel, 'settings'):
                            ch_settings = channel.settings
                            channel_info = {
                                'index': idx,
                                'name': getattr(ch_settings, 'name', f'Channel {idx}'),
                                'role': getattr(channel, 'role', 'DISABLED')
                            }

                            # Check modem preset if available
                            if hasattr(ch_settings, 'modemConfig'):
                                channel_info['modem_config'] = ch_settings.modemConfig

                            settings['channels'].append(channel_info)

            # Add recommendations based on settings
            if 'channels' in settings and len(settings['channels']) > 0:
                primary_channel = settings['channels'][0]
                if primary_channel.get('role') != 'PRIMARY':
                    settings['recommendations'].append("Channel 0 should be set to PRIMARY role")

            logger.info(f"Settings check complete for {port_name}")

        except Exception as e:
            logger.error(f"Error checking settings for {port_name}: {e}")
            settings['error'] = str(e)

        return settings

    @staticmethod
    def wait_for_radios(required_count=2, max_wait=60, check_interval=5):
        """
        Wait for the required number of radios to be connected
        Returns list of (port, info) tuples when ready
        """
        logger.info(f"Waiting for {required_count} radios (max {max_wait}s)...")

        start_time = time.time()

        while time.time() - start_time < max_wait:
            devices = DeviceManager.auto_detect_radios(required_count)

            if len(devices) >= required_count:
                logger.info(f"Found {len(devices)} radio(s)!")
                return devices

            logger.info(f"Found {len(devices)}/{required_count} radios, waiting...")
            time.sleep(check_interval)

        logger.error(f"Timeout: Only found {len(devices)}/{required_count} radios")
        return devices


def main():
    """Test the device manager"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    print("Meshtastic Device Manager - Test Mode")
    print("=" * 50)

    # Auto-detect devices
    devices = DeviceManager.auto_detect_radios(2)

    print(f"\nFound {len(devices)} device(s):")
    for port, info in devices:
        print(f"\n  Port: {port}")
        if 'myInfo' in info:
            my_info = info['myInfo']
            print(f"    Node: {my_info.get('user', {}).get('id', 'unknown')}")
            print(f"    HW: {my_info.get('user', {}).get('hwModel', 'unknown')}")

    # Check settings for each
    if devices:
        print("\n" + "=" * 50)
        print("Checking settings...")

        for port, info in devices:
            try:
                interface = meshtastic.serial_interface.SerialInterface(port)
                time.sleep(2)

                settings = DeviceManager.check_radio_settings(interface, port)
                print(f"\n  {port}:")
                print(f"    Status: {settings.get('status')}")
                print(f"    Node ID: {settings.get('node_id')}")

                if 'channels' in settings:
                    print(f"    Channels: {len(settings['channels'])}")
                    for ch in settings['channels']:
                        print(f"      - {ch['name']} (role: {ch['role']})")

                if settings.get('recommendations'):
                    print(f"    Recommendations:")
                    for rec in settings['recommendations']:
                        print(f"      - {rec}")

                interface.close()
            except Exception as e:
                print(f"  Error checking {port}: {e}")


if __name__ == "__main__":
    main()
