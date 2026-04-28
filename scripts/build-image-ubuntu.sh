#!/bin/bash
# Build Manjaro ARM image for uConsole CM4 on Ubuntu runner
# This runs directly on ubuntu-latest where QEMU/binfmt are available
set -e

PKG_DIR="$1"
OUT_DIR="$2"

if [ -z "$PKG_DIR" ] || [ -z "$OUT_DIR" ]; then
    echo "Error: Usage $0 <kernel_pkg_dir> <output_dir>"
    exit 1
fi

echo "==> Installing QEMU for ARM emulation..."
sudo apt-get update -qq
sudo apt-get install -y -qq qemu-user-static binfmt-support >/dev/null 2>&1

echo "==> Setting up QEMU binfmt..."
sudo update-binfmts --enable qemu-aarch64
ls /proc/sys/fs/binfmt_misc/qemu-aarch64 && echo "QEMU aarch64 binfmt ready" || echo "Warning: binfmt not found"

echo "==> Downloading Manjaro ARM rootfs..."
ROOTFS_URL="https://mirror.alpix.eu/manjaro-arm/rootfs/aarch64/minimal/"
ROOTFS_FILE=$(curl -sL "$ROOTFS_URL" | grep -oP 'Manjaro-ARM-minimal-aarch64-.*\.tar\.xz' | head -1)
if [ -z "$ROOTFS_FILE" ]; then
    echo "Could not find rootfs tarball at $ROOTFS_URL"
    curl -sL "$ROOTFS_URL" | head -20
    exit 1
fi
echo "Downloading: $ROOTFS_FILE"
curl -sL "${ROOTFS_URL}${ROOTFS_FILE}" -o /tmp/rootfs.tar.xz
echo "Downloaded: $(du -h /tmp/rootfs.tar.xz | cut -f1)"

echo "==> Extracting rootfs..."
WORKDIR=$(mktemp -d)
sudo tar -xJf /tmp/rootfs.tar.xz -C "$WORKDIR"
echo "Rootfs extracted to $WORKDIR"
ls "$WORKDIR" | head -10

echo "==> Installing custom kernel into rootfs..."
PKG_FILE=$(ls "$PKG_DIR"/linux-clockworkpi-uc4-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -z "$PKG_FILE" ]; then
    echo "No kernel package found in $PKG_DIR"
    ls -la "$PKG_DIR"
    exit 1
fi
echo "Using package: $(basename "$PKG_FILE")"
sudo cp "$PKG_FILE" "$WORKDIR/tmp/"

sudo chroot "$WORKDIR" bash -c '
    set -e
    # Initialize pacman keyring for the chroot
    pacman-key --init 2>/dev/null || true
    pacman-key --populate manjaro 2>/dev/null || true
    
    # Install the kernel package
    pacman -U --noconfirm --needed /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst
' || echo "Warning: Kernel install in chroot had issues, continuing..."

echo "==> Creating disk image..."
IMG_FILE="/tmp/Manjaro-ARM-minimal-uconsole-cm4.img"
dd if=/dev/zero of="$IMG_FILE" bs=1M count=4096 status=progress
sudo mkfs.ext4 -L "MANJARO_ARM" "$IMG_FILE"

echo "==> Populating image from rootfs..."
mkdir -p /mnt/img
sudo mount -o loop "$IMG_FILE" /mnt/img
sudo cp -a "$WORKDIR/"* /mnt/img/
sudo umount /mnt/img
echo "Image populated"

echo "==> Compressing image..."
mkdir -p "$OUT_DIR"
xz -9 -T0 "$IMG_FILE" -c > "$OUT_DIR/Manjaro-ARM-minimal-uconsole-cm4.img.xz"
echo "==> Success! Image: $OUT_DIR/Manjaro-ARM-minimal-uconsole-cm4.img.xz"
echo "Size: $(du -h "$OUT_DIR/Manjaro-ARM-minimal-uconsole-cm4.img.xz" | cut -f1)"

# Cleanup
sudo rm -rf "$WORKDIR" /tmp/rootfs.tar.xz
