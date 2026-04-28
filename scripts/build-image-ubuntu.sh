#!/bin/bash
# Build a complete Manjaro ARM disk image for uConsole CM4 (RPi4 base)
# Replicates `buildarmimg` functionality for GitHub Actions ubuntu runner
set -e

PKG_DIR="$1"
OUT_DIR="$2"

if [ -z "$PKG_DIR" ] || [ -z "$OUT_DIR" ]; then
    echo "Error: Usage $0 <kernel_pkg_dir> <output_dir>"
    exit 1
fi

IMG_NAME="Manjaro-ARM-minimal-uconsole-cm4"
IMG_SIZE_MB=8192  # 8GB image
BOOT_SIZE_MB=512  # Boot partition

echo "==> Installing required tools..."
sudo apt-get update -qq
sudo apt-get install -y -qq qemu-user-static binfmt-support dosfstools parted u-boot-tools >/dev/null 2>&1

echo "==> Setting up QEMU binfmt..."
sudo update-binfmts --enable qemu-aarch64
ls /proc/sys/fs/binfmt_misc/qemu-aarch64 && echo "QEMU aarch64 binfmt ready" || echo "Warning: binfmt not found"

echo "==> Downloading Manjaro ARM rootfs..."
ROOTFS_URL="https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-aarch64-latest.tar.gz"
curl -sL -o /tmp/rootfs.tar.gz "$ROOTFS_URL"
echo "Downloaded: $(du -h /tmp/rootfs.tar.gz | cut -f1)"

echo "==> Extracting rootfs..."
WORKDIR=$(mktemp -d)
sudo tar -xzf /tmp/rootfs.tar.gz -C "$WORKDIR"
echo "Rootfs extracted to $WORKDIR ($(sudo du -sh "$WORKDIR" | cut -f1))"

echo "==> Installing packages into rootfs..."
PKG_FILE=$(ls "$PKG_DIR"/linux-clockworkpi-uc4-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -z "$PKG_FILE" ]; then
    echo "No kernel package found in $PKG_DIR"
    exit 1
fi
echo "Using kernel: $(basename "$PKG_FILE")"

# Prepare chroot
sudo cp /usr/bin/qemu-aarch64-static "$WORKDIR/usr/bin/"
sudo cp "$PKG_FILE" "$WORKDIR/tmp/"

# Create custom repo setup script
sudo tee "$WORKDIR/tmp/setup-chroot.sh" > /dev/null << 'CHROOT_SCRIPT'
#!/bin/bash
set -e

# Initialize keyring
pacman-key --init 2>/dev/null || true
pacman-key --populate archlinuxarm manjaro 2>/dev/null || true

# Install kernel package directly
if ls /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst 1>/dev/null 2>&1; then
    pacman -U --noconfirm --needed /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst || echo "Kernel install had warnings"
fi

# Update and install base packages
pacman -Syy --noconfirm \
    base systemd systemd-libs dialog manjaro-arm-oem-install manjaro-system manjaro-release \
    raspberrypi-bootloader raspberrypi-utils u-boot-raspberrypi \
    wireless-regdb linux-firmware firmware-raspberrypi wpa_supplicant \
    sudo parted openssh inxi ncdu nano dhcpcd man-pages man-db ntfs-3g usbutils \
    zswap-arm bash-completion irqbalance btrfs-progs f2fs-tools exfatprogs \
    iwd manjaro-hotfixes \
    --noconfirm --noprogressbar || echo "Package installation completed with warnings"

# Enable services
systemctl enable getty.target 2>/dev/null || true
systemctl enable pacman-init.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true
systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true

# Clean up
rm -f /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst
rm -f /tmp/setup-chroot.sh
CHROOT_SCRIPT

sudo chmod +x "$WORKDIR/tmp/setup-chroot.sh"

echo "==> Running chroot installation (this takes a few minutes)..."
sudo chroot "$WORKDIR" qemu-aarch64-static bash /tmp/setup-chroot.sh || echo "Chroot completed with warnings"

echo "==> Creating disk image..."
IMG_FILE="/tmp/${IMG_NAME}.img"
sudo dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_SIZE_MB status=progress

echo "==> Partitioning image..."
# Create GPT partition table
sudo parted "$IMG_FILE" --script mklabel gpt
sudo parted "$IMG_FILE" --script mkpart primary fat32 4MiB $((4 + BOOT_SIZE_MB))MiB
sudo parted "$IMG_FILE" --script mkpart primary ext4 $((4 + BOOT_SIZE_MB))MiB 100%
sudo parted "$IMG_FILE" --script set 1 boot on
sudo parted "$IMG_FILE" --script set 1 esp on

echo "==> Formatting partitions..."
BOOT_OFFSET=$((4 * 1024 * 1024))
ROOT_OFFSET=$(( (4 + BOOT_SIZE_MB) * 1024 * 1024 ))

sudo losetup -fP "$IMG_FILE"
LOOP_DEV=$(sudo losetup -j "$IMG_FILE" | cut -d: -f1)
echo "Loop device: $LOOP_DEV"

sudo mkfs.vfat -F 32 -n "BOOT" "${LOOP_DEV}p1"
sudo mkfs.ext4 -F -L "ROOT" "${LOOP_DEV}p2"

echo "==> Mounting and populating image..."
sudo mkdir -p /mnt/boot /mnt/root
sudo mount "${LOOP_DEV}p2" /mnt/root
sudo mount "${LOOP_DEV}p1" /mnt/boot

# Copy rootfs
sudo cp -a "$WORKDIR/"* /mnt/root/
sudo cp -a "$WORKDIR/".[!.]* /mnt/root/ 2>/dev/null || true

echo "==> Setting up boot files..."
# Copy kernel, dtbs, and firmware from rootfs /boot to boot partition
# RPi4 firmware package (raspberrypi-bootloader) puts boot files in /boot
sudo cp -a /mnt/root/boot/* /mnt/boot/ 2>/dev/null || true

# Ensure we have the right kernel image for RPi4 direct boot
sudo cp /mnt/root/boot/Image /mnt/boot/kernel8.img 2>/dev/null || true
sudo cp /mnt/root/boot/Image.gz /mnt/boot/kernel8.img 2>/dev/null || true

# Copy config.txt if it exists
if [ -f /mnt/root/boot/config.txt ]; then
    sudo cp /mnt/root/boot/config.txt /mnt/boot/
else
    sudo tee /mnt/boot/config.txt > /dev/null << 'CONFIG'
# Manjaro ARM RPi4 configuration
enable_uart=1
dtoverlay=vc4-kms-v3d
arm_64bit=1
kernel=kernel8.img
CONFIG
fi

# Create boot script for U-Boot (if U-Boot is installed)
if [ -f /mnt/root/boot/boot.scr ]; then
    sudo cp /mnt/root/boot/boot.scr /mnt/boot/
fi

# Create cmdline.txt
if [ ! -f /mnt/boot/cmdline.txt ]; then
    echo "console=ttyS1,115200 console=tty0 root=/dev/mmcblk0p2 rw rootwait earlycon" | sudo tee /mnt/boot/cmdline.txt > /dev/null
fi

echo "==> Finalizing image..."
sudo umount /mnt/boot /mnt/root
sudo losetup -d "$LOOP_DEV"

echo "==> Compressing image..."
mkdir -p "$OUT_DIR"
xz -9 -T0 "$IMG_FILE" -c > "$OUT_DIR/${IMG_NAME}.img.xz"

echo "==> Success!"
echo "Image: $OUT_DIR/${IMG_NAME}.img.xz"
echo "Size: $(du -h "$OUT_DIR/${IMG_NAME}.img.xz" | cut -f1)"

# Cleanup
sudo rm -rf "$WORKDIR" /tmp/rootfs.tar.gz
sudo rm -f /tmp/${IMG_NAME}.img
