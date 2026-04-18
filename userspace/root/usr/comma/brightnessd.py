#!/usr/bin/env python3
import time
import os
import sys
import argparse

BL_OFF = 4

DEFAULT_ONEPLUS6_PATHS = {
    "bl_power": "/sys/class/backlight/panel0-backlight/bl_power",
    "brightness": "/sys/class/backlight/panel0-backlight/brightness",
    "max_brightness": "/sys/devices/platform/soc/soc:qcom,dsi-display@0/max_brightness_percent",
}

MAX_PERCENT = 90
MIN_PERCENT = 30
HOURLY_PERC_DECREASE = 5


def detect_backlight_device():
    backlight_dir = "/sys/class/backlight"
    if os.path.isdir(backlight_dir):
        devices = os.listdir(backlight_dir)
        if devices:
            primary = devices[0]
            return {
                "bl_power": f"/sys/class/backlight/{primary}/bl_power",
                "brightness": f"/sys/class/backlight/{primary}/brightness",
                "max_brightness": f"/sys/class/backlight/{primary}/max_brightness",
            }
    return DEFAULT_ONEPLUS6_PATHS


def read(path: str) -> int:
    try:
        with open(path) as f:
            return int(f.read())
    except Exception:
        return 0


def get_args():
    parser = argparse.ArgumentParser(description="Display brightness controller")
    parser.add_argument("--device", default="auto", choices=["auto", "oneplus6", "comma3"],
                        help="Device type for path configuration")
    return parser.parse_args()


def main():
    args = get_args()

    if args.device == "auto":
        paths = detect_backlight_device()
    elif args.device == "oneplus6":
        paths = DEFAULT_ONEPLUS6_PATHS
    else:
        paths = DEFAULT_ONEPLUS6_PATHS

    bl_power = paths["bl_power"]
    brightness = paths["brightness"]
    max_brightness = paths["max_brightness"]

    last_perc = None
    last_off_ts = time.monotonic()

    while True:
        try:
            bl_power_val = read(bl_power)
            brightness_val = read(brightness)

            if bl_power_val == BL_OFF or brightness_val == 0:
                last_off_ts = time.monotonic()

            uptime_hours = (time.monotonic() - last_off_ts) / (60*60)
            clipped_perc = MAX_PERCENT - (HOURLY_PERC_DECREASE * uptime_hours)
            clipped_perc = int(max(min(clipped_perc, MAX_PERCENT), MIN_PERCENT))

            if clipped_perc != last_perc:
                with open(max_brightness, 'w') as f:
                    f.write(f"{int(clipped_perc)}\n")
            last_perc = clipped_perc
        except Exception:
            pass

        time.sleep(5)


if __name__ == "__main__":
    main()