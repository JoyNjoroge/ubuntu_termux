# VERIFIED ARM64 DEBIAN ROOTFS
TARBALL_URL="https://images.linuxcontainers.org/images/debian/bookworm/arm64/default/20250115_04:50/rootfs.tar.xz"
TARBALL_NAME="debian12-arm64-rootfs.tar.xz"

download_rootfs() {
    progress "Downloading verified Debian 12 ARM64 rootfs..."

    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$DOWNLOAD_DIR/$TARBALL_NAME" "$TARBALL_URL" \
            || fail "Download failed. Check your connection."
    else
        curl -fsSL -o "$DOWNLOAD_DIR/$TARBALL_NAME" "$TARBALL_URL" \
            || fail "Download failed via Curl."
    fi

    success "Download complete."
}

verify_architecture() {
    progress "Verifying rootfs architecture..."

    # Extract only /bin/bash for architecture check
    mkdir -p "$DOWNLOAD_DIR/verify"
    tar -xJf "$DOWNLOAD_DIR/$TARBALL_NAME" -C "$DOWNLOAD_DIR/verify" ./bin/bash \
        || fail "Rootfs tarball seems corrupted or incomplete."

    FILE_OUTPUT=$(file "$DOWNLOAD_DIR/verify/bin/bash")

    if echo "$FILE_OUTPUT" | grep -q "aarch64"; then
        success "Rootfs is valid ARM64 (aarch64)."
    else
        fail "Rootfs is NOT ARM64. Wrong CPU architecture — cannot continue."
    fi

    rm -rf "$DOWNLOAD_DIR/verify"
}

extract_rootfs() {
    progress "Extracting Debian rootfs..."
    mkdir -p "$DEBIANPATH"
    tar -xJf "$DOWNLOAD_DIR/$TARBALL_NAME" -C "$DEBIANPATH" \
        || fail "Extraction failed."
    success "Rootfs successfully extracted to $DEBIANPATH"
}
