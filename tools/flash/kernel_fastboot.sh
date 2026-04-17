#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)"
cd "$DIR"

BUILD_DIR="$DIR/build"

FASTBOOT="${FASTBOOT:-fastboot}"

check_fastboot_device() {
  if ! "$FASTBOOT" devices | grep -q .; then
    echo "Error: No fastboot device found!"
    echo "Please put your device in fastboot mode:"
    echo "1. Power off the device"
    echo "2. Hold Volume Up + Power button"
    echo "3. Connect USB cable to computer"
    exit 1
  fi
}

case "${1:-}" in
  oneplus6)
    BOOT_IMG="$BUILD_DIR/boot-oneplus6.img"
    if [ ! -f "$BOOT_IMG" ]; then
      echo "boot-oneplus6.img not found, building OnePlus 6 kernel..."
      "$DIR/vamos" build kernel oneplus6
    fi
    
    echo "Checking for fastboot device..."
    check_fastboot_device
    
    echo "Flashing boot-oneplus6.img to OnePlus 6..."
    "$FASTBOOT" flash boot "$BOOT_IMG"
    
    echo "Rebooting device..."
    "$FASTBOOT" reboot
    ;;
  *)
    echo "Usage: $0 <oneplus6>"
    echo ""
    echo "Supported devices:"
    echo "  oneplus6    Flash kernel to OnePlus 6/6T via fastboot"
    exit 1
    ;;
esac