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

# Setup QEMU for chrooting into ARM rootfs
update-binfmts --install qemu-aarch64 /usr/bin/qemu-aarch64-static

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

# Setup profiles
PROFILE_DIR="/usr/share/manjaro-arm-tools/profiles"
mkdir -p "$PROFILE_DIR"
cp "$REPO_ROOT/profiles/uconsole-cm4.conf" "$PROFILE_DIR/"

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
