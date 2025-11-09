# Installation Guide - Meshtastic Bridge Headless Server

**The easiest way to install a production Meshtastic Bridge!**

---

## 🚀 Super Quick Install (Recommended)

### Option 1: One-Command Install (From GitHub)

```bash
git clone https://github.com/IceNet-01/meshtastic-bridge-headless.git && cd meshtastic-bridge-headless && ./install-auto.sh
```

That's it! The script will:
- ✅ Detect your system (Raspberry Pi, Linux, etc.)
- ✅ Install all dependencies automatically
- ✅ Set up Python environment
- ✅ Configure systemd service
- ✅ Enable auto-start on boot
- ✅ Enable auto-restart on crash
- ✅ Start the service immediately

**No prompts, no questions, just works!**

---

### Option 2: Interactive Install

If you already have the repository:

```bash
cd meshtastic-bridge-headless
./install-headless.sh
```

Or for fully automated (no prompts):

```bash
./install-headless.sh --auto
```

---

## 📋 What You Need

- **Hardware**: Two Meshtastic radios with USB cables
- **OS**: Linux with systemd (Ubuntu, Debian, Raspberry Pi OS, etc.)
- **Internet**: For downloading dependencies (only during install)

---

## 🎯 Installation Methods Comparison

| Method | Speed | Prompts | Best For |
|--------|-------|---------|----------|
| `install-auto.sh` | Fastest | None | Quick deployments, automation |
| `install-headless.sh --auto` | Fast | None | Local installs, automation |
| `install-headless.sh` | Medium | Few | Users who want to review steps |
| Manual | Slowest | Many | Advanced users, custom setups |

---

## 📦 Step-by-Step (What the Installer Does)

1. **Detects your system** - Raspberry Pi, Ubuntu, Debian, etc.
2. **Configures permissions** - Adds your user to `dialout` group for USB access
3. **Installs system packages** - `python3-venv`, `python3-pip`
4. **Creates Python environment** - Isolated virtual environment
5. **Installs Python packages** - `meshtastic`, `pyserial`, `rich`
6. **Sets up systemd service** - For auto-start and auto-restart
7. **Enables auto-start** - Service runs on boot
8. **Starts the service** - Bridge begins running immediately

Total time: **2-3 minutes** ⏱️

---

## ✅ After Installation

### Check if it's running:

```bash
sudo systemctl status meshtastic-bridge
```

You should see: **Active: active (running)** in green

### View live logs:

```bash
sudo journalctl -u meshtastic-bridge -f
```

Press `Ctrl+C` to exit

### Useful commands:

```bash
# Restart the service
sudo systemctl restart meshtastic-bridge

# Stop the service
sudo systemctl stop meshtastic-bridge

# Start the service
sudo systemctl start meshtastic-bridge

# Disable auto-start (service won't start on boot)
sudo systemctl disable meshtastic-bridge

# Enable auto-start (re-enable after disabling)
sudo systemctl enable meshtastic-bridge

# View last 100 log lines
sudo journalctl -u meshtastic-bridge -n 100

# View today's logs
sudo journalctl -u meshtastic-bridge --since today
```

---

## 🔧 Troubleshooting

### "Permission denied" on USB ports

You need to log out and log back in for group permissions to take effect:

```bash
logout
```

Then log back in and try again.

### Service won't start

Check the logs for errors:

```bash
sudo journalctl -u meshtastic-bridge -n 50
```

Common issues:
- Radios not connected (plug them in!)
- USB permission issues (log out/in)
- Wrong Python version (need 3.8+)

### Can't find radios

List USB devices:

```bash
ls -la /dev/ttyUSB* /dev/ttyACM*
```

Or use the built-in detector:

```bash
cd meshtastic-bridge-headless
./list-devices.sh
```

### Need to reinstall?

Just run the installer again - it's safe to run multiple times:

```bash
./install-auto.sh
```

or

```bash
./install-headless.sh --auto
```

---

## 🎓 Manual Installation (Advanced)

<details>
<summary>Click to expand manual installation steps</summary>

### 1. Clone repository

```bash
git clone https://github.com/IceNet-01/meshtastic-bridge-headless.git
cd meshtastic-bridge-headless
```

### 2. Configure permissions

```bash
sudo usermod -a -G dialout $USER
# Log out and log back in
```

### 3. Install system dependencies

```bash
sudo apt update
sudo apt install -y python3-venv python3-pip
```

### 4. Create Python environment

```bash
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### 5. Install systemd service

```bash
# Edit service file to match your paths
sudo nano meshtastic-bridge.service
# Change /home/mesh/meshtastic-bridge-headless to your actual path
# Change User=mesh to your username

# Copy service file
sudo cp meshtastic-bridge.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable meshtastic-bridge
sudo systemctl start meshtastic-bridge
```

### 6. Verify installation

```bash
sudo systemctl status meshtastic-bridge
sudo journalctl -u meshtastic-bridge -f
```

</details>

---

## 🌟 What Makes This Installation Painless?

✅ **Zero configuration** - Works out of the box
✅ **Auto-detection** - Finds your radios automatically
✅ **Idempotent** - Safe to run multiple times
✅ **Self-healing** - Fixes common issues automatically
✅ **System detection** - Optimizes for your OS
✅ **Pre-flight checks** - Validates before starting
✅ **Post-install validation** - Confirms everything works
✅ **Clear error messages** - Easy to troubleshoot

---

## 📚 Next Steps

After installation, see:
- **[QUICKSTART-HEADLESS.md](QUICKSTART-HEADLESS.md)** - Quick reference guide
- **[README.md](README.md)** - Complete documentation
- **[README.md](README.md)** - Full feature list

---

## 🎉 You're Done!

Your Meshtastic Bridge is now:
- ✅ Running in the background
- ✅ Auto-starting on boot
- ✅ Auto-restarting if it crashes
- ✅ Logging everything
- ✅ Ready to bridge your mesh network

**Enjoy your always-on Meshtastic Bridge!** 🚀

---

## 📞 Need Help?

- Check logs: `sudo journalctl -u meshtastic-bridge -f`
- Read docs: [README.md](README.md)
- Check GitHub issues: https://github.com/IceNet-01/meshtastic-bridge-headless/issues

---

**Installation takes 2-3 minutes. Your bridge runs forever.** ⚡
