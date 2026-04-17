# vamOS
a new operating system for comma 3X and comma four

[![fast](docs/fast.png)](https://discord.com/channels/469524606043160576/1262118077017882715/1482214461740683385)

## Usage

```
./vamos setup              # init submodules and udev rules
./vamos build kernel       # build boot.img (comma device)
./vamos build kernel oneplus6  # build boot.img for OnePlus 6/6T
./vamos build system       # build system.img
./vamos flash kernel       # flash boot.img to comma device via EDL (--legacy for legacy)
./vamos flash kernel oneplus6  # flash OnePlus 6/6T boot.img via fastboot
./vamos flash system       # flash system.img via EDL
./vamos flash all          # flash gpt + firmware + kernel + system (comma devices)
./vamos fastboot boot oneplus6  # alternative: flash kernel via fastboot
./vamos profile diff A B   # diff two rootfs profiles
```

### OnePlus 6/6T Flashing Instructions

1. Power off your OnePlus 6/6T
2. Hold **Volume Up + Power** to enter fastboot mode
3. Connect USB cable to your computer
4. Run: `./vamos flash kernel oneplus6`

## Supported Devices

### comma Devices
- comma 3/3X
- comma four
- comma mici

### Third-party Devices
- **OnePlus 6 (enchilada)** - Full camera support (IMX371, IMX519, IMX376K)
- **OnePlus 6T (fajita)** - Same camera configuration as OnePlus 6

## Kernel Patches

Patches in `kernel/patches/` are applied in order to the Linux kernel tree. They follow this naming convention:

```
NNNN-SUBSYSTEM-description.patch
```

- `NNNN` — sequential number, zero-padded (0001, 0002, …)
- `SUBSYSTEM` — the area of the kernel being modified:
  - `defconfig` — kernel configuration files
  - `dts` — device tree sources
  - `driver` — driver changes
  - `core` — core kernel subsystem changes
- `description` — short kebab-case summary of the change

Example: `0001-defconfig-add-vamos.patch`

## TODO

comma threex:
- [x] ufs
- [x] display
- [ ] i2c
  - [ ] TODO: look at device tree
- [x] wifi
  - [ ] testing (set benchmarks, test case)
- [x] usb
- [x] modem
- [ ] sound
- [x] SPI
- [ ] GPS
- [ ] cameras (OX03C10)
  - [ ] kernel wiring
  - [ ] ISP
  - [ ] openpilot
- [x] graphics
  - [x] gpu
- [ ] opencl - via rusticl / msm_drm
- [ ] Venus? (video encode/decode)

comma four:
- [x] ufs
- [x] display
- [ ] i2c (IMU/temp/...)
- [x] wifi
  - [ ] testing (set benchmarks, test case)
- [x] usb
- [x] modem
- [ ] sound
- [x] SPI
- [ ] GPS
- [ ] cameras (OS04C10)
  - [ ] kernel wiring
  - [ ] ISP
  - [ ] openpilot
- [x] graphics
  - [x] gpu
- [ ] opencl - via rusticl / msm_drm
- [ ] Venus (video encode/decode)

openpilot support:
- [ ]

tinygrad support:
- [ ] msm_drm

validation:
- [ ] dmesg is clean (background in https://github.com/commaai/agnos-builder/issues/325)
- [ ] test_onroad passes
- [ ] testing closet
