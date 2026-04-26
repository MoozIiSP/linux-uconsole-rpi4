# linux-uconsole-rpi4

Manjaro ARM kernel package for [ClockworkPi uConsole](https://clockworkpi.com/) with CM4 module.

## Structure

```
├── .github/workflows/build.yaml    # CI build workflow
├── PKGBUILDs/
│   ├── linux-clockworkpi-uc4/      # Kernel 6.6 + patches
│   ├── uconsole-4g-cm4/            # 4G module toggle utility
│   └── uconsole-cm4-post-install/  # Post-install config
└── devices/
    └── uconsole-cm4                # Device profile
```

## Kernel Patches

| # | Patch | Description |
|---|-------|-------------|
| 1 | OCP8178 backlight | 1-wire backlight driver for LCD |
| 2 | CWU50 DRM panel | JD9365D 720×1280 MIPI DSI panel driver |
| 3 | Simple amplifier switch | GPIO-controlled headphone amplifier |
| 4 | uConsole DTS overlay | Device tree overlay (PMU, backlight, panel, battery) |
| 5 | AXP22x PMU customize | IPSOUT current limit, charge LED config |
| 6 | AXP22x battery calibration | Fuel gauge, sysfs calibration interface |
| 7 | CWU50 DSI error status | Expose DSI error via sysfs |

## Build

```bash
cd PKGBUILDs/linux-clockworkpi-uc4
makepkg -s
```

On x86_64 hosts, the PKGBUILD auto-enables cross-compilation (`aarch64-linux-gnu-gcc` required).

## Hardware

- **Board**: ClockworkPi uConsole (CM4 variant)
- **SoC**: BCM2711 (Raspberry Pi CM4)
- **Display**: 5" 720×1280 MIPI DSI (JD9365D)
- **PMU**: AXP228 (I2C GPIO bit-bang)
- **Backlight**: OCP8178 (1-wire GPIO)
- **Battery**: 8000mAh
