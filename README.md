# Meshtastic Bridge - Headless Server

**Production-ready headless server for bridging Meshtastic radio networks**

A reliable, always-on bridge that forwards messages between two Meshtastic radios with different channel configurations. Designed for dedicated server deployments, Raspberry Pi installations, or any scenario where you need a headless, self-healing bridge.

## ✨ Features

### Core Functionality
- **🚀 100% Headless Operation**: No GUI dependencies, runs as a background service
- **⚡ Auto-Start on Boot**: Automatically starts when the system boots with smart USB device waiting
- **🔄 Auto-Restart on Crash**: Service automatically restarts if it fails with exponential backoff retry logic
- **🛡️ Crash Protection**: Prevents restart loops with intelligent backoff (safer than before - no forced reboots!)
- **🔍 Auto-Detection**: Automatically finds and connects to Meshtastic radios
- **🔁 Bidirectional Bridge**: Forwards messages between two radios seamlessly
- **📝 Message Deduplication**: Prevents message loops and duplicate forwarding
- **📊 Robust Logging**: All activity logged to systemd journal
- **⚙️ Resource Efficient**: Optimized for low-resource systems (~50-100 MB RAM)
- **🔒 Security Hardened**: Runs with minimal privileges

### NEW: Enhanced Stability & Monitoring (v2.0)
- **🔧 Connection Retry Logic**: Exponential backoff (2s → 32s) for resilient USB connections
- **🛑 Graceful Shutdown**: Proper signal handling (SIGTERM/SIGINT) for clean shutdowns
- **💚 Health Monitoring**: Automatic health checks every 60s with JSON status file output
- **📊 External Monitoring Support**: Health check script compatible with Nagios/Icinga/cron
- **🔔 Failure Notifications**: Optional alerts via Slack/Discord/Email/Telegram/Pushover/ntfy.sh
- **🎯 Type Hints**: Full type annotations for better code quality and IDE support
- **🐛 Memory Leak Fixed**: Bounded message log prevents memory exhaustion
- **📌 Dependency Pinning**: Version constraints prevent breaking changes from upstream

### 🆕 NEW: Automatic Radio Recovery (v2.1)
- **🔄 Individual Radio Reboot**: Automatically reboots unresponsive radios after 3 health check failures
- **⚡ Smart Recovery**: Sends reboot command to radio, waits for restart, then reconnects
- **🎯 Graceful System Reboot**: As last resort, system reboots gracefully (not forced) after exhausting all retries
- **📊 Failure Tracking**: Monitors consecutive failures per radio with automatic reset on recovery

**📖 See [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for detailed technical documentation of all improvements.**

## 🎯 Quick Install (2 Minutes)

### One-Command Installation

**Connect your radios, then run:**

```bash
git clone https://github.com/IceNet-01/meshtastic-bridge-headless.git && cd meshtastic-bridge-headless && ./install-auto.sh
```

**That's it!** The script automatically:
- ✅ Installs all dependencies
- ✅ Configures permissions and service
- ✅ Enables auto-start and auto-restart
- ✅ Starts your bridge immediately

**Takes 2-3 minutes. No prompts needed.**

### Alternative Installation Methods

```bash
# Interactive mode (asks before starting service)
./install-headless.sh

# Fully automated (no prompts at all)
./install-headless.sh --auto
```

**📖 See [INSTALL.md](INSTALL.md) for detailed installation options and troubleshooting.**

## 📋 System Requirements

- **OS**: Linux with systemd (Ubuntu, Debian, Raspberry Pi OS, etc.)
- **Python**: 3.8 or higher
- **Hardware**: Two Meshtastic-compatible radios with USB connections
- **Permissions**: User account with sudo access

## 🎮 Service Management

### Check Service Status

```bash
sudo systemctl status meshtastic-bridge
```

### View Live Logs

```bash
# Follow logs in real-time
sudo journalctl -u meshtastic-bridge -f

# View last 100 lines
sudo journalctl -u meshtastic-bridge -n 100

# View logs from today
sudo journalctl -u meshtastic-bridge --since today
```

### Control Service

```bash
# Start the service
sudo systemctl start meshtastic-bridge

# Stop the service
sudo systemctl stop meshtastic-bridge

# Restart the service
sudo systemctl restart meshtastic-bridge

# Enable auto-start on boot (default after installation)
sudo systemctl enable meshtastic-bridge

# Disable auto-start on boot
sudo systemctl disable meshtastic-bridge
```

## 🔧 How It Works

### Auto-Detection

The bridge automatically detects connected Meshtastic radios via USB:
1. Scans all USB serial ports
2. Tests each device to verify it's a Meshtastic radio
3. Connects to the first two radios found
4. Begins forwarding messages between them

### Message Forwarding

- Messages received on Radio 1 are forwarded to Radio 2
- Messages received on Radio 2 are forwarded to Radio 1
- Each message is tracked to prevent loops and duplicates
- Message history is kept for 10 minutes (configurable in code)

### Auto-Restart Behavior

The service is configured with intelligent restart policies:
- **Always restart**: Service restarts automatically after any failure
- **10-second delay**: Waits 10 seconds before restarting
- **Crash protection**: Allows up to 5 restarts within 60 seconds
- **Recovery**: If restart limit is reached, system attempts recovery

## 📦 What Gets Installed

The installer automatically:
1. ✅ Adds your user to the `dialout` group for USB access
2. ✅ Installs system dependencies (`python3-venv`, `python3-pip`)
3. ✅ Sets up Python virtual environment
4. ✅ Installs required packages (headless-only)
5. ✅ Configures systemd service for auto-start
6. ✅ Enables auto-restart on crash
7. ✅ Starts the service immediately

### Python Dependencies

- `meshtastic` >= 2.7.0 - Meshtastic communication library
- `pyserial` >= 3.5 - Serial port communication
- `rich` >= 14.2.0 - Enhanced logging output

**No GUI dependencies!** This is a pure headless server.

## 🛠️ Troubleshooting

### Service won't start

Check the logs for errors:
```bash
sudo journalctl -u meshtastic-bridge -n 50
```

Common issues:
- **Permission denied**: Make sure your user is in the `dialout` group
  ```bash
  sudo usermod -a -G dialout $USER
  # Then log out and log back in
  ```
- **No radios found**: Verify radios are connected via USB
  ```bash
  ./list-devices.sh
  ```
- **Port access denied**: Check that radios aren't being used by another program

### Can't find radios

List USB devices:
```bash
./list-devices.sh
# or
ls -la /dev/ttyUSB* /dev/ttyACM*
```

### Service keeps restarting

If the service is restarting frequently:
1. Check logs to identify the error
2. Verify both radios are connected and working
3. Test manually to isolate the issue:
   ```bash
   cd /path/to/meshtastic-bridge-headless
   source venv/bin/activate
   python3 bridge.py
   ```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│         Headless Meshtastic Bridge              │
│                                                 │
│  ┌───────────────┐       ┌──────────────────┐   │
│  │  Radio 1      │◄─────►│  Radio 2         │   │
│  │  (LongFast)   │       │  (LongModerate)  │   │
│  └───────────────┘       └──────────────────┘   │
│         │                         │             │
│         │                         │             │
│  ┌──────▼─────────────────────────▼──────────┐  │
│  │      Message Tracker & Forwarder          │  │
│  │  - Deduplication                          │  │
│  │  - Bidirectional forwarding               │  │
│  │  - Loop prevention                        │  │
│  └───────────────────────────────────────────┘  │
│                      │                          │
│                      ▼                          │
│          ┌───────────────────────┐              │
│          │  Logging & Monitoring │              │
│          │  (systemd journal)    │              │
│          └───────────────────────┘              │
└─────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
meshtastic-bridge-headless/
├── bridge.py                    # Core headless bridge logic
├── device_manager.py            # USB device detection
├── install-auto.sh              # Fully automated installer
├── install-headless.sh          # Interactive installer
├── list-devices.sh              # USB device listing utility
├── meshtastic-bridge.service    # Systemd service definition
├── requirements.txt             # Python dependencies
├── README.md                    # This file
├── QUICKSTART.md               # Quick reference guide
├── INSTALL.md                  # Detailed installation guide
└── .gitignore                  # Git configuration
```

## 🚀 Performance

The headless bridge is lightweight and efficient:
- **Memory**: ~50-100 MB RAM
- **CPU**: Minimal (<1% on modern systems)
- **Network**: Uses only the Meshtastic radio network
- **Storage**: Minimal (logs rotate automatically via systemd)

## 🔒 Security

Security features enabled by default:
- Runs as non-root user
- Minimal file system access
- Private /tmp directory
- No network listening (only USB serial)
- No privilege escalation
- Isolated process tree

## 📊 Monitoring & Health Checks

### Health Status File

The bridge automatically writes health status to `/tmp/meshtastic-bridge-status.json` every 30 seconds:

```bash
# View current status
cat /tmp/meshtastic-bridge-status.json

# Monitor with jq
watch -n 5 'jq . /tmp/meshtastic-bridge-status.json'
```

### Health Check Script

Run the health check script for monitoring integration:

```bash
# Manual check
./check-bridge-health.sh
# Output: OK: Bridge healthy - Uptime: 1h 30m - Errors: R1=0 R2=0

# Nagios/Icinga compatible (exit codes: 0=OK, 1=WARNING, 2=CRITICAL)
./check-bridge-health.sh && echo "Healthy!" || echo "Problem detected!"

# Add to cron for periodic checks
*/5 * * * * /path/to/check-bridge-health.sh || /usr/bin/send-alert.sh
```

### Failure Notifications (Optional)

Set up automatic alerts when the service fails:

1. Edit `send-failure-alert.sh` to configure your notification method:
   - Email (mail/mailx)
   - Slack webhook
   - Discord webhook
   - Telegram bot
   - Pushover
   - ntfy.sh
   - Custom webhooks

2. Install notification service:
   ```bash
   sudo cp meshtastic-bridge-failure-notify@.service /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

3. Enable in main service file (uncomment line in `meshtastic-bridge.service`):
   ```ini
   OnFailure=meshtastic-bridge-failure-notify@%n.service
   ```

## 📚 Documentation

- **[IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md)** - Technical details of v2.0 improvements
- **[CODE_REVIEW.md](CODE_REVIEW.md)** - Complete code review and security analysis
- **[QUICKSTART.md](QUICKSTART.md)** - Quick start guide (2 minutes to running)
- **[INSTALL.md](INSTALL.md)** - Complete installation guide with troubleshooting
- **README.md** - This file (overview and features)

## 🔄 Updating

### Easy One-Command Update ⚡

The easiest way to update (recommended):

```bash
cd /path/to/meshtastic-bridge-headless
./update.sh
```

This script automatically:
- ✅ Creates a backup of your current installation
- ✅ Checks for and installs updates
- ✅ Updates Python dependencies
- ✅ Updates systemd service file if needed
- ✅ Restarts the service
- ✅ Provides a rollback script if anything goes wrong

### Check for Updates Without Installing

```bash
./check-version.sh
```

Shows your current version and lists available updates.

### Check Current Version

```bash
python3 bridge.py --version
# or
cat VERSION
```

### Manual Update (Advanced)

If you prefer to update manually:

```bash
cd /path/to/meshtastic-bridge-headless
git pull
source venv/bin/activate
pip install --upgrade -r requirements.txt
sudo systemctl restart meshtastic-bridge
```

### Rollback to Previous Version

If an update causes issues, the update script creates a rollback script in `~/.meshtastic-bridge-backups/`:

```bash
# Find your backup
ls -la ~/.meshtastic-bridge-backups/

# Run the rollback script
~/.meshtastic-bridge-backups/backup_<version>_<timestamp>/rollback.sh
```

## 🗑️ Uninstallation

To completely remove the bridge:

```bash
# Stop and disable service
sudo systemctl stop meshtastic-bridge
sudo systemctl disable meshtastic-bridge
sudo rm /etc/systemd/system/meshtastic-bridge.service
sudo systemctl daemon-reload

# Remove installation directory
cd ~
rm -rf /path/to/meshtastic-bridge-headless
```

## 💡 Use Cases

Perfect for:
- **Raspberry Pi deployments** - Headless operation with auto-start
- **Dedicated servers** - Always-on bridge with crash recovery
- **Remote installations** - Survives reboots and power outages
- **Network extension** - Bridge different channel configurations
- **Reliable repeater** - Automatic recovery from failures

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation

## 📄 License

MIT License - Feel free to use and modify as needed.

## 🆘 Support

- **Issues**: https://github.com/IceNet-01/meshtastic-bridge-headless/issues
- **Documentation**: See [INSTALL.md](INSTALL.md) for detailed help
- **Logs**: `sudo journalctl -u meshtastic-bridge -f`

---

**Ready to deploy?** Run the one-command installer and you're live in 2 minutes! 🚀

```bash
git clone https://github.com/IceNet-01/meshtastic-bridge-headless.git && cd meshtastic-bridge-headless && ./install-auto.sh
```
