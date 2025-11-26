#!/data/data/com.termux/files/usr/bin/bash

set -e

# --- CONFIG ---
UBUNTU_DIR="$HOME/ubuntu"
ROOTFS_URL="https://partner-images.canonical.com/core/jammy/current/ubuntu-jammy-core-cloudimg-arm64-root.tar.gz"
ENTER_SCRIPT="$HOME/enter-ubuntu.sh"

echo "[+] Installing Termux dependencies..."
pkg update -y
pkg install -y proot tar curl

echo "[+] Creating Ubuntu directory..."
mkdir -p "$UBUNTU_DIR"
cd "$UBUNTU_DIR"

echo "[+] Downloading Ubuntu 22.04 (jammy) rootfs..."
curl -L "$ROOTFS_URL" -o ubuntu.tar.gz

echo "[+] Extracting rootfs safely..."
tar --no-same-owner --no-same-permissions --numeric-owner -xzf ubuntu.tar.gz
rm ubuntu.tar.gz

echo "[+] Creating necessary mount points..."
mkdir -p "$UBUNTU_DIR"{/dev,/proc,/sys,/run}

echo "[+] Creating chroot launch script..."
cat > "$ENTER_SCRIPT" <<'EOF'
#!/system/bin/sh
UBUNTU_DIR="$HOME/ubuntu"

# Mount necessary filesystems as root
su -c "mount -t proc /proc \$UBUNTU_DIR/proc"
su -c "mount --rbind /dev \$UBUNTU_DIR/dev"
su -c "mount --rbind /sys \$UBUNTU_DIR/sys"
su -c "mount --rbind /run \$UBUNTU_DIR/run"

HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
chroot "$UBUNTU_DIR" /bin/bash

# Unmount when exiting
su -c "umount \$UBUNTU_DIR/proc"
su -c "umount -l \$UBUNTU_DIR/dev"
su -c "umount -l \$UBUNTU_DIR/sys"
su -c "umount -l \$UBUNTU_DIR/run"
EOF

chmod +x "$ENTER_SCRIPT"

echo "[+] Installing Python 3.10 inside Ubuntu..."
"$ENTER_SCRIPT" <<'EOF'
apt update
apt install -y python3.10 python3.10-venv python3.10-dev python3-pip
EOF

echo ""
echo "====================================================="
echo "[✓] Ubuntu 22.04 installed successfully!"
echo "[✓] Python 3.10 installed!"
echo "-----------------------------------------------------"
echo "To enter Ubuntu at any time, run:"
echo ""
echo "     ./enter-ubuntu.sh"
echo ""
echo "====================================================="

echo "P.S. Antonio, You owe me"
echo "Because i fucked cpython for you! 😆"
