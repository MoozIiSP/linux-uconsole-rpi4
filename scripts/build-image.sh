#!/bin/bash
# Build a Manjaro ARM image using manjaro-arm-tools
# Usage: ./scripts/build-image.sh <kernel_pkg_dir> <output_dir>

set -e

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PKG_DIR="$1"
OUT_DIR="$2"

if [ -z "$PKG_DIR" ] || [ -z "$OUT_DIR" ]; then
    echo "Error: Usage $0 <kernel_pkg_dir> <output_dir>"
    exit 1
fi

echo "==> Setting up environment for manjaro-arm-tools..."

# Install tools
pacman -Sy --noconfirm manjaro-arm-tools qemu-user-static

# Setup arm-profiles (device/edition/service configs from Manjaro ARM)
mkdir -p /usr/share/manjaro-arm-tools/profiles/arm-profiles
cp -r "$REPO_ROOT/arm-profiles/"* /usr/share/manjaro-arm-tools/profiles/arm-profiles/

# Setup QEMU for chrooting into ARM rootfs
# binfmt handlers already registered by docker/setup-qemu-action on the runner
if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "==> QEMU aarch64 binfmt already registered (from runner)"
else
    echo "Warning: qemu-aarch64 binfmt not available, chroot will fail"
    exit 1
fi

# Setup local repo to include our custom kernel package
REPO_DIR="/tmp/local-uconsole-repo"
mkdir -p "$REPO_DIR"
cp "$PKG_DIR"/linux-clockworkpi-uc4-*.pkg.tar.zst "$REPO_DIR/"
cd "$REPO_DIR"
repo-add local-uconsole-repo.db.tar.gz *.pkg.tar.zst
cd -

# Configure pacman to use local repo
cat >> /etc/pacman.conf <<EOF
[local-uconsole]
Server = file:///tmp/local-uconsole-repo
SigLevel = Never
EOF

echo "==> Building Image..."
# buildarmimg -d device -e edition -v (verbose)
# The profile name matches the 'name' in the conf file
buildarmimg -d uconsole-cm4 -e minimal -v

echo "==> Packaging Image..."
mkdir -p "$OUT_DIR"

# Find the generated image
IMG_FILE=$(ls /var/cache/manjaro-arm-tools/images/Manjaro-ARM-minimal-raspberrypi-4-*.img | head -1)

if [ -z "$IMG_FILE" ]; then
    echo "Error: Image not found in /var/cache/manjaro-arm-tools/images/"
    ls -la /var/cache/manjaro-arm-tools/images/
    exit 1
fi

# Compress with high compression ratio (xz -9)
# This takes longer but significantly reduces download size
BASENAME=$(basename "$IMG_FILE" .img)
xz -9 -T0 "$IMG_FILE" -c > "$OUT_DIR/${BASENAME}.img.xz"

echo "==> Success! Image: $OUT_DIR/${BASENAME}.img.xz"
