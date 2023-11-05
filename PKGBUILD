# Contributor: Dave Higham <pepedog@archlinuxarm.org>
# Contributor: Kevin Mihelich <kevin@archlinuxarm.org>
# Contributor: Oleg Rakhmanov <oleg@archlinuxarm.org>
# Maintainer: Ray Sherwin <slick517d@gmail.com>

pkgbase=linux-uconsole-rpi4
_commit=8dcc16f0adc50f5cb8a11a6dde238131d0ca45a0
_srcname=linux-${_commit}
_kernelname=${pkgbase#linux}
_desc="Raspberry Pi 4 64-bit kernel for uConsole"
pkgver=6.1.58
pkgrel=6
arch=('aarch64')
url="http://www.kernel.org/"
license=('GPL2')
makedepends=('xmlto' 'docbook-xsl' 'kmod' 'inetutils' 'bc' 'git')
options=('!strip')
source=("https://github.com/raspberrypi/linux/archive/${_commit}.tar.gz"
        '0001-arm64-dts-uconsole-rpi-dts.patch'
        '0002-gpu-drm-panel-add-cwd686-cwu50-drivers.patch' 
        '0003-gpu-drm-vc4-vc4-dsi.patch'
        '0004-mfd-axp20x-add-uconsole-rpi-power-support.patch' 
        '0005-staging-vc04-bcm2835-audio.patch'
        '0006-video-backlight-add-ocp8178-driver.patch'
        'config'
        'linux.preset'
        '60-linux.hook'
        '90-linux.hook'
        'logo_linux_clut224.ppm'
)

md5sums=('b6d73bfb5b5b93062bf260c8e7212452'
         '03f084a2a758fd718b8cc509d7deafe5'
         '26268df39cf32b70a4dd9ea7b6ca8ae2'
         'f71d3dd3bbf205419c426de30a08326b'
         'c2618540125492c53a4632c3cd65506a'
         '43561c8bdc44ee4eb7f9a935f11baa39'
         '7c81d9dddf2a61518aa97fa6a360cb25'
         '1281ad07aea11941d4c20be0a5af4e56'
         '86d4a35722b5410e3b29fc92dae15d4b'
         'ce6c81ad1ad1f8b333fd6077d47abdaf'
         '0a98f67d3354d5a2f9fe1a62a0c0839c'
         '7f7ddadea6f4a7d3017380cb83b95b5e')

prepare() {
  cd "${srcdir}/${_srcname}"
  cat "${srcdir}/config" > ./.config

  # ClockworkPI uConsole RPi4 patches
  patch -Np1 -i "${srcdir}/0001-arm64-dts-uconsole-rpi-dts.patch"                       # DTS
  patch -Np1 -i "${srcdir}/0002-gpu-drm-panel-add-cwd686-cwu50-drivers.patch"           # LCD
  patch -Np1 -i "${srcdir}/0003-gpu-drm-vc4-vc4-dsi.patch"                              # 
  patch -Np1 -i "${srcdir}/0004-mfd-axp20x-add-uconsole-rpi-power-support.patch"        # Power/Battery/Charger
  patch -Np1 -i "${srcdir}/0005-staging-vc04-bcm2835-audio.patch"                       # Audio
  patch -Np1 -i "${srcdir}/0006-video-backlight-add-ocp8178-driver.patch"               # Backlight

  # add pkgrel to extraversion
  sed -ri "s|^(EXTRAVERSION =)(.*)|\1 \2-${pkgrel}|" Makefile

  # don't run depmod on 'make install'. We'll do this ourselves in packaging
  sed -i '2iexit 0' scripts/depmod.sh

  # Add Manjaro Mascot for cpu core count at boot
  cp ../logo_linux_clut224.ppm drivers/video/logo/
}

build() {
  cd "${srcdir}/${_srcname}"

  # get kernel version
  make prepare

  # load configuration
  # Configure the kernel. Replace the line below with one of your choice.
  #make menuconfig # CLI menu for configuration
  #make nconfig # new CLI menu for configuration
  #make xconfig # X-based configuration
  #make oldconfig # using old config from previous kernel version
  #make bcmrpi_defconfig # using RPi defconfig
  # ... or manually edit .config

  # Copy back our configuration (use with new kernel version)
  #cp ./.config /var/tmp/${pkgbase}.config

  ####################
  # stop here
  # this is useful to configure the kernel
  #msg "Stopping build"
  #return 1
  ####################

  #yes "" | make config

  make ${MAKEFLAGS} Image.gz modules dtbs
}

_package() {
  pkgdesc="The Linux Kernel and modules - ${_desc}"
  depends=('coreutils' 'kmod' 'initramfs'
           'firmware-raspberrypi' 'uconsole-rpi-overlays')
  optdepends=('wireless-regdb: Set the correct wireless channels of your country'
              'linux-firmware: Extra firmware that RPi or kernel does not provide')
  provides=('kernel26' "linux=${pkgver}")
  conflicts=('kernel26' 'linux' 'uboot-raspberrypi')
  install=${pkgname}.install
  replaces=('linux-raspberrypi-latest')

  cd "${srcdir}/${_srcname}"

  KARCH=arm64

  # get kernel version
  _kernver="$(make kernelrelease)"
  _basekernel=${_kernver%%-*}
  _basekernel=${_basekernel%.*}

# Temp disable
#  mkdir -p "${pkgdir}"/{boot/overlays,usr/lib/modules}
   mkdir -p "${pkgdir}"/{boot,usr/lib/modules}
   make INSTALL_MOD_PATH="${pkgdir}/usr" modules_install

  cp arch/$KARCH/boot/dts/broadcom/bcm2710-rpi-cm3.dtb "${pkgdir}/boot"
  cp arch/$KARCH/boot/dts/broadcom/bcm2711-rpi-cm4.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2711-rpi-cm4-io.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2711-rpi-cm4s.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2711-rpi-4-b.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2711-rpi-400.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2710-rpi-3-b-plus.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2710-rpi-3-b.dtb "${pkgdir}/boot"
  #cp arch/$KARCH/boot/dts/broadcom/bcm2710-rpi-zero-2-w.dtb "${pkgdir}/boot"
  cp arch/$KARCH/boot/Image.gz "${pkgdir}/boot/kernel8.img"

  # make room for external modules
  local _extramodules="extramodules-${_basekernel}${_kernelname}"
  ln -s "../${_extramodules}" "${pkgdir}/usr/lib/modules/${_kernver}/extramodules"

  # add real version for building modules and running depmod from hook
  echo "${_kernver}" |
    install -Dm644 /dev/stdin "${pkgdir}/usr/lib/modules/${_extramodules}/version"

  # remove build and source links
  rm "${pkgdir}"/usr/lib/modules/${_kernver}/{source,build}

  # now we call depmod...
  depmod -b "${pkgdir}/usr" -F System.map "${_kernver}"

  # sed expression for following substitutions
  local _subst="
    s|%PKGBASE%|${pkgbase}|g
    s|%KERNVER%|${_kernver}|g
    s|%EXTRAMODULES%|${_extramodules}|g
  "

  # install mkinitcpio preset file
  sed "${_subst}" ../linux.preset |
    install -Dm644 /dev/stdin "${pkgdir}/etc/mkinitcpio.d/${pkgbase}.preset"

  # install pacman hooks
  sed "${_subst}" ../60-linux.hook |
    install -Dm644 /dev/stdin "${pkgdir}/usr/share/libalpm/hooks/60-${pkgbase}.hook"
  sed "${_subst}" ../90-linux.hook |
    install -Dm644 /dev/stdin "${pkgdir}/usr/share/libalpm/hooks/90-${pkgbase}.hook"
}

_package-headers() {
  pkgdesc="Header files and scripts for building modules for linux kernel - ${_desc}"
  provides=("linux-headers=${pkgver}")
  conflicts=('linux-headers')
  replaces=('linux-raspberrypi-latest-headers')

  cd ${_srcname}
  local _builddir="${pkgdir}/usr/lib/modules/${_kernver}/build"

  install -Dt "${_builddir}" -m644 Makefile .config Module.symvers
  install -Dt "${_builddir}/kernel" -m644 kernel/Makefile

  mkdir "${_builddir}/.tmp_versions"

  cp -t "${_builddir}" -a include scripts

  install -Dt "${_builddir}/arch/${KARCH}" -m644 arch/${KARCH}/Makefile
  install -Dt "${_builddir}/arch/${KARCH}/kernel" -m644 arch/${KARCH}/kernel/asm-offsets.s
  # arch/$KARCH/kernel/module.lds

  cp -t "${_builddir}/arch/${KARCH}" -a arch/${KARCH}/include

  install -Dt "${_builddir}/drivers/md" -m644 drivers/md/*.h
  install -Dt "${_builddir}/net/mac80211" -m644 net/mac80211/*.h

  # http://bugs.archlinux.org/task/13146
  install -Dt "${_builddir}/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h

  # http://bugs.archlinux.org/task/20402
  install -Dt "${_builddir}/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
  install -Dt "${_builddir}/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
  install -Dt "${_builddir}/drivers/media/tuners" -m644 drivers/media/tuners/*.h

  # add xfs and shmem for aufs building
  mkdir -p "${_builddir}"/{fs/xfs,mm}

  # copy in Kconfig files
  find . -name Kconfig\* -exec install -Dm644 {} "${_builddir}/{}" \;

  # remove unneeded architectures
  local _arch
  for _arch in "${_builddir}"/arch/*/; do
    [[ ${_arch} == */${KARCH}/ ]] && continue
    rm -r "${_arch}"
  done

  # remove files already in linux-docs package
  rm -r "${_builddir}/Documentation"

  # remove now broken symlinks
  find -L "${_builddir}" -type l -printf 'Removing %P\n' -delete

  # Fix permissions
  #chmod -R u=rwX,go=rX "${_builddir}"

  # strip scripts directory
  local _binary _strip
  while read -rd '' _binary; do
    case "$(file -bi "${_binary}")" in
      *application/x-sharedlib*)  _strip="${STRIP_SHARED}"   ;; # Libraries (.so)
      *application/x-archive*)    _strip="${STRIP_STATIC}"   ;; # Libraries (.a)
      *application/x-executable*) _strip="${STRIP_BINARIES}" ;; # Binaries
      *) continue ;;
    esac
    /usr/bin/strip ${_strip} "${_binary}"
  done < <(find "${_builddir}/scripts" -type f -perm -u+w -print0 2>/dev/null)
}

_packageuconsole-rpi-overlays() {
  pkgdesc="Raspberry Pi overlays for uConsole RPi4"
  options=(!strip)
  conflicts=('rpi-overlays')

  cd "${srcdir}/${_srcname}"

  KARCH=arm64

  mkdir -p "${pkgdir}"/boot/overlays
  cp arch/$KARCH/boot/dts/overlays/*.dtb* "${pkgdir}/boot/overlays"
  cp arch/$KARCH/boot/dts/overlays/README "${pkgdir}/boot/overlays"
}

pkgname=("${pkgbase}" "${pkgbase}-headers" "uconsole-rpi-overlays")
for _p in ${pkgname[@]}; do
  eval "package_${_p}() {
    _package${_p#${pkgbase}}
  }"
done
