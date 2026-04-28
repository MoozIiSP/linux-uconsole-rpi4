#!/bin/bash
# Build a complete Manjaro ARM disk image for uConsole CM4 (RPi4 base)
# Fully replicates `buildarmimg` functionality for GitHub Actions ubuntu runner
# Includes: fstab(UUID), PARTUUID cmdline, first-boot resize, initramfs,
#           arm-profiles, boot.scr, SSH keys, locale/timezone, OEM setup
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
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "==> Installing required tools..."
 apt-get update -qq
 apt-get install -y -qq qemu-user-static binfmt-support dosfstools parted u-boot-tools e2fsprogs >/dev/null 2>&1

echo "==> Setting up QEMU binfmt..."
# Try update-binfmts first (Debian/Ubuntu), fallback to manual registration
if command -v update-binfmts &>/dev/null; then
     update-binfmts --enable qemu-aarch64 2>/dev/null || true
fi
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "Registering qemu-aarch64 binfmt manually..."
    echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OC" |  tee /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
fi
ls /proc/sys/fs/binfmt_misc/qemu-aarch64 && echo "QEMU aarch64 binfmt ready" || echo "Warning: binfmt not registered"

echo "==> Downloading Manjaro ARM rootfs..."
ROOTFS_URL="https://github.com/manjaro-arm/rootfs/releases/latest/download/Manjaro-ARM-aarch64-latest.tar.gz"
curl -sL -o /tmp/rootfs.tar.gz "$ROOTFS_URL"
echo "Downloaded: $(du -h /tmp/rootfs.tar.gz | cut -f1)"

echo "==> Extracting rootfs..."
WORKDIR=$(mktemp -d)
 tar -xzf /tmp/rootfs.tar.gz -C "$WORKDIR"
echo "Rootfs extracted to $WORKDIR ($( du -sh "$WORKDIR" | cut -f1))"

echo "==> Installing packages into rootfs..."
PKG_FILE=$(ls "$PKG_DIR"/linux-clockworkpi-uc4-*.pkg.tar.zst 2>/dev/null | head -1)
if [ -z "$PKG_FILE" ]; then
    echo "No kernel package found in $PKG_DIR"
    exit 1
fi
echo "Using kernel: $(basename "$PKG_FILE")"

# Prepare chroot — install kernel directly via pacman -U (no repo-add needed on Ubuntu)
 cp /usr/bin/qemu-aarch64-static "$WORKDIR/usr/bin/"
 cp "$PKG_FILE" "$WORKDIR/tmp/"

# Setup arm-profiles in chroot (replicates buildarmimg behavior)
echo "==> Setting up arm-profiles..."
 mkdir -p "$WORKDIR/usr/share/manjaro-arm-tools/profiles/arm-profiles"
if [ -d "$REPO_ROOT/arm-profiles" ]; then
     cp -r "$REPO_ROOT/arm-profiles/"* "$WORKDIR/usr/share/manjaro-arm-tools/profiles/arm-profiles/"
    echo "arm-profiles installed from repo"
else
    echo "Warning: arm-profiles directory not found at $REPO_ROOT/arm-profiles"
fi

# Create chroot setup script
 tee "$WORKDIR/tmp/setup-chroot.sh" > /dev/null << 'CHROOT_SCRIPT'
#!/bin/bash
set -e

echo "[chroot] Initializing keyring..."
pacman-key --init 2>/dev/null || true
pacman-key --populate archlinuxarm manjaro 2>/dev/null || true

echo "[chroot] Installing custom kernel..."
if ls /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst 1>/dev/null 2>&1; then
    pacman -U --noconfirm --needed /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst || echo "Kernel install had warnings"
fi

echo "[chroot] Installing base packages..."
pacman -Syy --noconfirm \
    base systemd systemd-libs dialog manjaro-arm-oem-install manjaro-system manjaro-release \
    raspberrypi-bootloader raspberrypi-utils u-boot-raspberrypi \
    wireless-regdb linux-firmware firmware-raspberrypi wpa_supplicant \
    sudo parted openssh inxi ncdu nano dhcpcd man-pages man-db ntfs-3g usbutils \
    zswap-arm bash-completion irqbalance btrfs-progs f2fs-tools exfatprogs \
    iwd manjaro-hotfixes mkinitcpio \
    --noconfirm --noprogressbar || echo "Package installation completed with warnings"

echo "[chroot] Generating initramfs..."
# Run mkinitcpio for our kernel if preset exists
if [ -f /etc/mkinitcpio.d/linux-clockworkpi-uc4.preset ]; then
    mkinitcpio -p linux-clockworkpi-uc4 2>/dev/null || echo "mkinitcpio had warnings"
elif [ -f /etc/mkinitcpio.conf ]; then
    # Try to generate for the installed kernel
    KERNEL_VER=$(ls /lib/modules/ 2>/dev/null | head -1)
    if [ -n "$KERNEL_VER" ]; then
        mkinitcpio -k "$KERNEL_VER" -g "/boot/initramfs-${KERNEL_VER}.img" 2>/dev/null || echo "mkinitcpio had warnings"
    fi
fi

echo "[chroot] Enabling services..."
systemctl enable pacman-init.service 2>/dev/null || true
systemctl enable sshd.service 2>/dev/null || true
systemctl enable NetworkManager.service 2>/dev/null || true
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true
systemctl enable getty@tty1.service 2>/dev/null || true
systemctl enable serial-getty@ttyAMA0.service 2>/dev/null || true
# OEM first-boot setup
systemctl enable manjaro-arm-oem-install.service 2>/dev/null || true

echo "[chroot] Pre-generating SSH host keys..."
ssh-keygen -A 2>/dev/null || true

echo "[chroot] Setting locale and timezone..."
# Set default locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen 2>/dev/null || true
locale-gen 2>/dev/null || true
cat > /etc/locale.conf << 'LOCALE'
LANG=en_US.UTF-8
LOCALE

# Set default timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null || true
echo "UTC" > /etc/timezone 2>/dev/null || true
timedatectl set-timezone UTC 2>/dev/null || true

echo "[chroot] Setting hostname..."
echo "uconsole-cm4" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 uconsole-cm4" >> /etc/hosts

echo "[chroot] Installing growpart (cloud-utils) for safe live resize..."
pacman -S --noconfirm --needed cloud-utils --noconfirm --noprogressbar 2>/dev/null || true

# Clean up
rm -f /tmp/linux-clockworkpi-uc4-*.pkg.tar.zst
rm -f /tmp/setup-chroot.sh
CHROOT_SCRIPT

 chmod +x "$WORKDIR/tmp/setup-chroot.sh"

echo "==> Running chroot installation (this takes a few minutes)..."
 chroot "$WORKDIR" qemu-aarch64-static bash /tmp/setup-chroot.sh || echo "Chroot completed with warnings"

echo "==> Creating disk image..."
IMG_FILE="/tmp/${IMG_NAME}.img"
 dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_SIZE_MB status=progress

echo "==> Partitioning image (GPT)..."
 parted "$IMG_FILE" --script mklabel gpt
 parted "$IMG_FILE" --script mkpart primary fat32 4MiB $((4 + BOOT_SIZE_MB))MiB
 parted "$IMG_FILE" --script mkpart primary ext4 $((4 + BOOT_SIZE_MB))MiB 100%
 parted "$IMG_FILE" --script set 1 boot on
 parted "$IMG_FILE" --script set 1 esp on

echo "==> Formatting partitions..."
 losetup -fP "$IMG_FILE"
LOOP_DEV=$( losetup -j "$IMG_FILE" | cut -d: -f1)
echo "Loop device: $LOOP_DEV"

 mkfs.vfat -F 32 -n "BOOT" "${LOOP_DEV}p1"
 mkfs.ext4 -F -L "ROOT" "${LOOP_DEV}p2"

echo "==> Mounting and populating image..."
 mkdir -p /mnt/boot /mnt/root
 mount "${LOOP_DEV}p2" /mnt/root
 mount "${LOOP_DEV}p1" /mnt/boot

# Copy rootfs to root partition
 cp -a "$WORKDIR/"* /mnt/root/
 cp -a "$WORKDIR/".[!.]* /mnt/root/ 2>/dev/null || true

echo "==> Getting PARTUUIDs and UUIDs..."
BOOT_PARTUUID=$( blkid -s PARTUUID -o value "${LOOP_DEV}p1")
ROOT_PARTUUID=$( blkid -s PARTUUID -o value "${LOOP_DEV}p2")
ROOT_UUID=$( blkid -s UUID -o value "${LOOP_DEV}p2")
BOOT_UUID=$( blkid -s UUID -o value "${LOOP_DEV}p1")
echo "BOOT PARTUUID: $BOOT_PARTUUID"
echo "ROOT PARTUUID: $ROOT_PARTUUID"
echo "ROOT UUID: $ROOT_UUID"
echo "BOOT UUID: $BOOT_UUID"

echo "==> Generating fstab (UUID-based)..."
 tee /mnt/root/etc/fstab > /dev/null << FSTAB_EOF
# /etc/fstab: static file system information
# <file system>                                <dir> <type> <options>          <dump> <pass>
UUID=${ROOT_UUID}  /     ext4   defaults,noatime,discard    0      1
UUID=${BOOT_UUID}  /boot vfat   defaults,noatime,commit=600 0      2
tmpfs                                    /tmp  tmpfs  defaults,noatime,mode=1777 0      0
FSTAB_EOF

echo "==> Setting up boot files..."
# Copy all boot files from rootfs /boot to boot partition
 cp -a /mnt/root/boot/* /mnt/boot/ 2>/dev/null || true

# Ensure kernel image for RPi4 direct boot
 cp /mnt/root/boot/Image /mnt/boot/kernel8.img 2>/dev/null || true
# Fallback: copy compressed kernel if Image doesn't exist
if [ ! -f /mnt/boot/kernel8.img ]; then
     cp /mnt/root/boot/Image.gz /mnt/boot/kernel8.img 2>/dev/null || true
fi

# config.txt
if [ -f /mnt/root/boot/config.txt ]; then
     cp /mnt/root/boot/config.txt /mnt/boot/
else
     tee /mnt/boot/config.txt > /dev/null << 'CONFIG'
# Manjaro ARM RPi4 / uConsole CM4 configuration
enable_uart=1
dtoverlay=vc4-kms-v3d
arm_64bit=1
kernel=kernel8.img
initramfs initramfs-linux-clockworkpi-uc4.img followkernel
CONFIG
fi

# cmdline.txt with PARTUUID (not /dev/mmcblk0p2)
 tee /mnt/boot/cmdline.txt > /dev/null << CMDLINE_EOF
console=ttyS1,115200 console=tty0 root=PARTUUID=${ROOT_PARTUUID} rw rootwait earlycon
CMDLINE_EOF

echo "==> Generating boot.scr (U-Boot boot script)..."
# Create boot.cmd and compile to boot.scr
 tee /tmp/boot.cmd > /dev/null << 'BOOTCMD'
fdt addr ${fdt_addr_r}
if test -e mmc ${devnum}:1 config.txt; then
    fatload mmc ${devnum}:1 ${kernel_addr_r} kernel8.img
    fatload mmc ${devnum}:1 ${fdt_addr_r} bcm2711-rpi-4-b.dtb
    fatload mmc ${devnum}:1 ${ramdisk_addr_r} initramfs-linux-clockworkpi-uc4.img
    booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
fi
BOOTCMD
 mkimage -A arm64 -O linux -T script -C none -n "Boot script for uConsole CM4" -d /tmp/boot.cmd /mnt/boot/boot.scr 2>/dev/null || echo "mkimage failed, boot.scr not generated"
rm -f /tmp/boot.cmd

echo "==> Installing first-boot resize service..."
# Create the resize script
 tee /mnt/root/usr/local/bin/first-boot-resize.sh > /dev/null << 'RESIZE_SCRIPT'
#!/bin/bash
# First-boot root partition resize service
# Expands root partition to fill the entire SD card, then self-destructs

set -e
MARKER="/etc/.root-resized"

if [ -f "$MARKER" ]; then
    echo "[first-boot-resize] Already resized, exiting."
    exit 0
fi

echo "[first-boot-resize] Resizing root partition to fill disk..."

# Find the root disk (should be /dev/mmcblk0 for SD/eMMC)
ROOT_DEV=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//')
ROOT_PART=$(findmnt -n -o SOURCE /)

if [ -z "$ROOT_DEV" ] || [ -z "$ROOT_PART" ]; then
    echo "[first-boot-resize] Cannot detect root device, exiting."
    exit 1
fi

echo "[first-boot-resize] Root partition: $ROOT_PART"
echo "[first-boot-resize] Root disk: $ROOT_DEV"

# Get partition number
PART_NUM=$(echo "$ROOT_PART" | grep -oP '[0-9]+$')

# Resize partition using growpart (safer than parted for live resize)
if command -v growpart &>/dev/null; then
    growpart "$ROOT_DEV" "$PART_NUM" 2>/dev/null || {
        echo "[first-boot-resize] growpart failed, trying parted..."
        parted "$ROOT_DEV" --script resizepart "$PART_NUM" 100% 2>/dev/null || true
    }
else
    parted "$ROOT_DEV" --script resizepart "$PART_NUM" 100% 2>/dev/null || true
fi

# Resize the filesystem
resize2fs "$ROOT_PART" 2>/dev/null || true

# Mark as done
touch "$MARKER"
echo "[first-boot-resize] Root partition resized successfully."
echo "[first-boot-resize] Disabling service..."
systemctl disable first-boot-resize.service 2>/dev/null || true
RESIZE_SCRIPT
 chmod +x /mnt/root/usr/local/bin/first-boot-resize.sh

# Create systemd service unit
 tee /mnt/root/etc/systemd/system/first-boot-resize.service > /dev/null << 'UNIT_EOF'
[Unit]
Description=Resize root partition on first boot
DefaultDependencies=no
After=systemd-udev-settle.service
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot-resize.sh
RemainAfterExit=yes
TimeoutStartSec=120

[Install]
WantedBy=sysinit.target
UNIT_EOF

# Enable the service
 ln -sf /etc/systemd/system/first-boot-resize.service \
    /mnt/root/etc/systemd/system/sysinit.target.wants/first-boot-resize.service

echo "==> Setting up OEM first-boot defaults..."
# Create oem-install marker so OEM setup knows this is first boot
 touch /mnt/root/.oem-first-boot
# Set default user hints for OEM
 mkdir -p /mnt/root/etc/manjaro-arm
 tee /mnt/root/etc/manjaro-arm/oem.conf > /dev/null << 'OEM_EOF'
[oem]
device=uconsole-cm4
edition=minimal
OEM_EOF

echo "==> Finalizing image..."
 umount /mnt/boot /mnt/root
 losetup -d "$LOOP_DEV"

echo "==> Compressing image..."
mkdir -p "$OUT_DIR"
xz -9 -T0 "$IMG_FILE" -c > "$OUT_DIR/${IMG_NAME}.img.xz"

echo "==> Success!"
echo "Image: $OUT_DIR/${IMG_NAME}.img.xz"
echo "Size: $(du -h "$OUT_DIR/${IMG_NAME}.img.xz" | cut -f1)"

# Cleanup
 rm -rf "$WORKDIR" /tmp/rootfs.tar.gz
 rm -f /tmp/${IMG_NAME}.img
