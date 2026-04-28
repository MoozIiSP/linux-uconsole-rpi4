#!/bin/bash
# Build Manjaro ARM image for uConsole CM4 on Ubuntu runner
# Runs directly on ubuntu-latest where QEMU/binfmt are available
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
ROOTFS_URL="https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-aarch64-latest.tar.gz"
echo "Downloading from: $ROOTFS_URL"
curl -sL -o /tmp/rootfs.tar.gz "$ROOTFS_URL"
echo "Downloaded: $(du -h /tmp/rootfs.tar.gz | cut -f1)"

echo "==> Extracting rootfs..."
WORKDIR=$(mktemp -d)
sudo tar -xzf /tmp/rootfs.tar.gz -C "$WORKDIR"
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

# Copy QEMU binary and package into rootfs
sudo cp /usr/bin/qemu-aarch64-static "$WORKDIR/usr/bin/"
sudo cp "$PKG_FILE" "$WORKDIR/tmp/"

# Run pacman inside rootfs using QEMU chroot
sudo chroot "$WORKDIR" qemu-aarch64-static bash -c '
    set -e
    pacman-key --init 2>/dev/null || true
    pacman-key --populate archlinuxarm manjaro 2>/dev/null || true
    pacman -U --noconfirm --needed /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst || echo "Package install had warnings"
    rm -f /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst
' || echo "Warning: Kernel install had issues, continuing..."

# === Image creation - all under sudo ===
echo "==> Creating disk image..."
IMG_FILE="/tmp/Manjaro-ARM-minimal-uconsole-cm4.img"
sudo dd if=/dev/zero of="$IMG_FILE" bs=1M count=4096 status=progress
sudo mkfs.ext4 -F -L "MANJARO_ARM" "$IMG_FILE"

echo "==> Populating image from rootfs..."
sudo mkdir -p /mnt/img
sudo mount -o loop "$IMG_FILE" /mnt/img
sudo cp -a "$WORKDIR/"* /mnt/img/
sudo umount /mnt/img
echo "Image populated"

echo "==> Compressing image..."
mkdir -p "$OUT_DIR"
# Move img to workspace first, then compress
sudo mv "$IMG_FILE" ./Manjaro-ARM-minimal-uconsole-cm4.img
sudo chown $(id -u):$(id -g) ./Manjaro-ARM-minimal-uconsole-cm4.img 2>/dev/null || true
xz -9 -T0 ./Manjaro-ARM-minimal-uconsole-cm4.img -c > "$OUT_DIR/Manjaro-ARM-minimal-uconsole-cm4.img.xz"
echo "==> Success! Image: $OUT_DIR/Manjaro-ARM-minimal-uconsole-cm4.img.xz"
echo "Size: $(du -h "$OUT_DIR/Manjaro-ARM-minimal-uconsole-cm4.img.xz" | cut -f1)"

# Cleanup
sudo rm -rf "$WORKDIR" /tmp/rootfs.tar.gz
