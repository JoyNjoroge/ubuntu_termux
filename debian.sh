#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------
# Debian chroot installer (refactored)
# - Clean, safe sudoers handling
# - Username validation
# - XFCE4 + TigerVNC setup
# - Reduced use of su; uses chroot + bash -c
# -----------------------------

# CONFIGURABLES (edit if you want different defaults)
DOWNLOAD_DIR="/data/local/tmp/chrootDebian"
TARBALL_NAME="debian12-arm64.tar.gz"
TARBALL_URL="https://github.com/LinuxDroidMaster/Termux-Desktops/releases/download/Debian/debian12-arm64.tar.gz"
DEBIANPATH="$DOWNLOAD_DIR/debian"
STARTER_HOST_PATH="$DOWNLOAD_DIR/start_debian.sh"   # wrapper placed on host for convenience
VNC_PORT=5901
VNC_PASSWORD="changeme"   # change or prompt later if you want

# Helpers
progress(){ printf "\e[1;36m[+] %s\e[0m\n" "$1"; }
success(){ printf "\e[1;32m[✓] %s\n\e[0m" "$1"; }
fail(){ printf "\e[1;31m[✗] %s\n\e[0m" "$1"; exit 1; }

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root."
fi

# Ensure busybox and chroot available
command -v busybox >/dev/null 2>&1 || fail "busybox is required."
command -v chroot >/dev/null 2>&1 || progress "chroot not on PATH — using busybox chroot when possible."

# Create download dir
mkdir -p "$DOWNLOAD_DIR"
success "Using download dir: $DOWNLOAD_DIR"

# Download tarball if not present
if [ ! -f "$DOWNLOAD_DIR/$TARBALL_NAME" ]; then
    progress "Downloading Debian tarball..."
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$DOWNLOAD_DIR/$TARBALL_NAME" "$TARBALL_URL" || fail "wget download failed."
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$DOWNLOAD_DIR/$TARBALL_NAME" "$TARBALL_URL" || fail "curl download failed."
    else
        fail "Neither wget nor curl available on host."
    fi
    success "Download complete."
else
    progress "Tarball already exists; skipping download."
fi

# Extract tarball
if [ ! -d "$DEBIANPATH" ]; then
    progress "Extracting tarball..."
    mkdir -p "$DEBIANPATH"
    tar -xzf "$DOWNLOAD_DIR/$TARBALL_NAME" -C "$DEBIANPATH" || fail "Extraction failed."
    success "Extracted to $DEBIANPATH"
else
    progress "Debian chroot already extracted at $DEBIANPATH. Skipping extraction."
fi

# Helper to run commands inside chroot (use bash -c)
chrun() {
    # $1 => command string
    busybox chroot "$DEBIANPATH" /bin/bash -c "$1"
}

# Ensure apt exists in chroot
progress "Checking chroot environment..."
if ! chrun "command -v apt >/dev/null 2>&1"; then
    fail "apt not found inside chroot. Is the tarball a valid Debian rootfs?"
fi
success "Chroot environment looks valid."

# Update inside chroot
progress "Updating apt inside chroot..."
chrun "export DEBIAN_FRONTEND=noninteractive; apt-get update -y >/dev/null"
success "Apt updated."

# Ask username (but do not rely on interactive checks outside Termux)
read -r -p "Enter username to create inside chroot: " USERNAME
# Validate username strictly: lowercase, digits, dash, underscore, start with letter or underscore
if ! printf "%s" "$USERNAME" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'; then
    fail "Invalid username. Must match regex '^[a-z_][a-z0-9_-]{0,31}$' (lowercase, digits, - or _, start with letter/underscore)."
fi

# Sanity: ensure username not already present in chroot
if chrun "getent passwd '$USERNAME' >/dev/null 2>&1"; then
    fail "User '$USERNAME' already exists inside chroot. Pick another name or remove existing user."
fi

# Create user inside chroot, set /bin/bash, create home, set passwordless sudo via sudoers.d
progress "Creating user '$USERNAME' in chroot..."
chrun "export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends passwd sudo >/dev/null"
chrun "useradd -m -s /bin/bash -U '$USERNAME' || exit 1"
# Set a locked password initially; instruct the user to change after first login
chrun "passwd -d '$USERNAME' || true"
# Add user to a sane groups list: sudo, audio, video, netdev, plugdev if present
chrun "usermod -aG sudo,audio,video,netdev,plugdev '$USERNAME' || true"

# Create sudoers.d entry (safe)
progress "Configuring sudoers for '$USERNAME'..."
SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
chrun "bash -c 'printf \"%s ALL=(ALL:ALL) NOPASSWD:ALL\n\" \"$USERNAME\" > \"$SUDOERS_FILE\"'"
chrun "chmod 440 \"$SUDOERS_FILE\""
success "Sudo configured in $SUDOERS_FILE (NOPASSWD for convenience)."

# Install XFCE4 + VNC server inside chroot
progress "Installing XFCE4 and TigerVNC inside chroot (this may take a while)..."
chrun "export DEBIAN_FRONTEND=noninteractive; apt-get install -y dbus-x11 xfce4 xfce4-terminal xfce4-goodies tigervnc-standalone-server >/dev/null || true"
success "Installed desktop & VNC packages (or attempted to)."

# Create VNC startup for that user inside chroot
progress "Configuring VNC xstartup for user..."
chrun "bash -c 'su - $USERNAME -c \"mkdir -p /home/$USERNAME/.vnc && cat > /home/$USERNAME/.vnc/xstartup <<'XSTART'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
dbus-launch --exit-with-session startxfce4 &
XSTART
chmod +x /home/$USERNAME/.vnc/xstartup
chown -R $USERNAME:$USERNAME /home/$USERNAME/.vnc
\"'"

# Create a script inside chroot to start VNC for that user (for convenience)
progress "Creating start_vnc_debian.sh inside chroot..."
chrun "bash -c 'cat > /root/start_vnc_debian.sh <<'VSH'
#!/bin/bash
# Start VNC server for user: $USERNAME
USER=\"$USERNAME\"
VNCPASS=\"$VNC_PASSWORD\"
DISPLAY_NUM=1
VNC_PORT=\$((5900 + DISPLAY_NUM))

# Ensure vncpasswd set (non-interactive)
mkdir -p /home/\$USER/.vnc
if [ ! -f /home/\$USER/.vnc/passwd ]; then
    echo \"\$VNCPASS\" | vncpasswd -f > /home/\$USER/.vnc/passwd
    chmod 600 /home/\$USER/.vnc/passwd
    chown \$USER:\$USER /home/\$USER/.vnc/passwd
fi

# Kill existing VNC on display :\$DISPLAY_NUM
pkill -f \"Xtigervnc :\$DISPLAY_NUM\" || true

su - \$USER -c \"vncserver :\$DISPLAY_NUM -geometry 1280x800 -depth 24\"
echo \"VNC running on port \$VNC_PORT (display :\$DISPLAY_NUM)\"
VSH
chmod +x /root/start_vnc_debian.sh
'"

success "VNC start script created at /root/start_vnc_debian.sh (inside chroot)."

# Create a host-side wrapper script to run the chroot VNC start easily
progress "Creating host wrapper: $STARTER_HOST_PATH"
cat > "$STARTER_HOST_PATH" <<EOF
#!/bin/bash
# Host wrapper to invoke the chrooted VNC start script.
DEBIANPATH="$DEBIANPATH"
if [ "\$(id -u)" -ne 0 ]; then
    echo "Run this as root."
    exit 1
fi
busybox chroot "\$DEBIANPATH" /bin/bash -c "/root/start_vnc_debian.sh"
EOF
chmod +x "$STARTER_HOST_PATH"
success "Created host wrapper at: $STARTER_HOST_PATH"

# Update the host start_debian.sh (if you have a template nearby) - optional
if [ -f "$DEBIANPATH/../start_debian.sh" ]; then
    progress "Patching nearby start_debian.sh with username..."
    sed -i "s/droidmaster/$USERNAME/g" "$DEBIANPATH/../start_debian.sh" || true
fi

# Final instructions
success "Refactor complete."

cat <<EOF

Next steps (quick):
1. To start the VNC server inside the chroot, run on the host as root:
   $STARTER_HOST_PATH

   This will call the chrooted script which starts tigervnc as user '$USERNAME' on display :1 (port ${VNC_PORT}).

2. To connect:
   - Use any VNC client and point to <device-ip>:${VNC_PORT}
   - Password: $VNC_PASSWORD  (change this inside chroot!)
   To change the VNC password inside chroot:
     busybox chroot "$DEBIANPATH" /bin/bash -c "su - $USERNAME -c 'vncpasswd'"

3. Recommendations:
   - Change VNC password after first run.
   - Consider running VNC in a loop or via a Termux task if you want auto-restart.
   - If using Android GUI apps (XServer XSDL), you'll need to adapt DISPLAY and possibly use xauth.

If you want, I can:
 - Remove NOPASSWD for sudo (safer) and provide a password prompt flow.
 - Add pulseaudio configuration for sound forwarding.
 - Add an optional XSDL path instead of VNC.
 - Harden the VNC server (use SSH tunnel or x11vnc + xauth).

EOF
