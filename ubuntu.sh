#!/data/data/com.termux/files/usr/bin/bash

set -e

# --- CONFIG ---
UBUNTU_DIR="/data/local/ubuntu"
ROOTFS_URL="https://partner-images.canonical.com/core/jammy/current/ubuntu-jammy-core-cloudimg-arm64-root.tar.gz"

echo "[+] Checking for root..."
if [ "$(id -u)" != "0" ]; then
    echo "[-] You MUST run Termux as root: 'tsu' or 'su'"
    exit 1
fi

echo "[+] Creating Ubuntu directory..."
mkdir -p $UBUNTU_DIR
cd $UBUNTU_DIR

echo "[+] Downloading Ubuntu 22.04 (jammy) rootfs..."
curl -L $ROOTFS_URL -o ubuntu.tar.gz

echo "[+] Extracting rootfs..."
tar -xzf ubuntu.tar.gz
rm ubuntu.tar.gz

echo "[+] Creating necessary mount points..."
mkdir -p $UBUNTU_DIR/{dev,proc,sys,run}

echo "[+] Creating chroot launch script..."
cat > /usr/local/bin/enter-ubuntu <<EOF
#!/system/bin/sh
UBUNTU_DIR="$UBUNTU_DIR"

mount -t proc /proc "\$UBUNTU_DIR/proc"
mount --rbind /dev "\$UBUNTU_DIR/dev"
mount --rbind /sys "\$UBUNTU_DIR/sys"
mount --rbind /run "\$UBUNTU_DIR/run"

HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
chroot "\$UBUNTU_DIR" /bin/bash

umount "\$UBUNTU_DIR/proc"
umount -l "\$UBUNTU_DIR/dev"
umount -l "\$UBUNTU_DIR/sys"
umount -l "\$UBUNTU_DIR/run"
EOF

chmod +x /usr/local/bin/enter-ubuntu

echo "[+] Installing Python 3.10 inside Ubuntu..."
enter-ubuntu <<'EOF'
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
echo "     su"
echo "     enter-ubuntu"
echo ""
echo "Antonio I hope this will help"
echo "====================================================="
