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

# Install tools (arm-profiles provides base device/edition configs)
pacman -Sy --noconfirm manjaro-arm-tools qemu-user-static arm-profiles

# Setup QEMU for chrooting into ARM rootfs
# In containers, manually register binfmt handler
set +e
echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OC" > /proc/sys/fs/binfmt_misc/register 2>/dev/null
set -e
if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "==> QEMU aarch64 binfmt registered"
else
    echo "Warning: qemu-aarch64 binfmt not registered, chroot may fail"
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

# Setup profiles
PROFILE_DIR="/usr/share/manjaro-arm-tools/profiles"
# Copy our custom profile to both locations:
# 1. Root profiles dir (custom profile with [profile] section)
# 2. arm-profiles/devices dir (where buildarmimg scans for available devices)
cp "$REPO_ROOT/profiles/uconsole-cm4.conf" "$PROFILE_DIR/"
cp "$REPO_ROOT/profiles/uconsole-cm4.conf" "$PROFILE_DIR/arm-profiles/devices/"

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
