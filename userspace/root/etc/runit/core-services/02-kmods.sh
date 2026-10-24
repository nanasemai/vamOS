#!/bin/sh
# 显式加载 Qualcomm IPC 栈。
#
# 为什么需要这个脚本：本 rootfs 没有 udev。initramfs 用 mdev（不按 modalias
# 自动加载模块），userspace 也没装 eudev。所以 877 个 =m 模块不会自己起来，
# 必须在这里显式 modprobe。
#
# 为什么只列 Qualcomm IPC 栈、不铺满全部模块：
#   * USB DWC3 / DWC3_QCOM / DWC3_DUAL_ROLE 是 =y 内置，不需要模块；
#   * GPU (adreno)、camera (qcom_camss)、venus 全是 =y 内置；
#   * ath10k (WiFi) 也是 =y 内置，qcom_wcnss_ctrl 内置；
#   * qmi_helpers 是 =y 内置（CONFIG_QCOM_QMI_HELPERS=y）。
# 真正卡功能的只有 ADSP/SLPI 那条链：libssc 和 hexagonrpc 都要过
# qrtr -> qcom_smd -> APSS 的 QMI，qrtr-ns / rmtfs / tqftpserv / pd-mapper
# 这些 runit 服务也是。它们都在 stage-1 后面才起，所以模块必须比它们更早。
#
# 本脚本在 /etc/runit/1 里于 udevd 启动**之前**执行，顺序是确定性的；
# 剩下的杂项模块交给 eudev 按 modalias 自动加载（base_setup.sh 已装）。
#
# 每条 modprobe 都带 || true：某个模块在上游改名或消失时，这里只留一行 WARN，
# 不让 stage-1 整体失败。stage-1 没有 set -e，但把失败显式打印出来比静默强。

PATH=/sbin:/bin:/usr/sbin:/usr/bin

# 内核版本从 /proc 读，不硬编码。模块目录名和 boot.img 里的 krel 必须一致，
# 否则会 EREXEC 或者加载到错的内核的模块。
KREL="$(cat /proc/sys/kernel/osrelease 2>/dev/null || true)"
if [ -z "$KREL" ]; then
    echo "WARN: 读不到 osrelease，无法加载模块"
    exit 0
fi
if [ ! -s "/lib/modules/$KREL/modules.dep" ]; then
    echo "WARN: /lib/modules/$KREL/modules.dep 不存在，模块可能没打进镜像"
    echo "WARN:   现有目录: $(ls /lib/modules 2>/dev/null | tr '\n' ' ')"
    exit 0
fi

load() {
    mod="$1"
    if modprobe -k "$KREL" "$mod" 2>/dev/null; then
        echo "  [ok] $mod"
    else
        echo "  [WARN] $mod 加载失败（上游改名或缺失？检查 /lib/modules/$KREL）"
    fi
}

echo "=> Loading Qualcomm IPC modules ($KREL) ..."
# qrtr 核心 + SMD 传输（APSS <-> ADSP/SLPI）。libssc 和 qrtr-ns 都靠它。
load qrtr
load qrtr-smd
# MHI 总线 + MHI 网络（调制解调器的 MBIM/QMI 走这里）
load mhi
load mhi-net
# 熊猫板的 USB NCM 链路（controlsd 走这个口和 openpilot 通信）
load usbnet
load usb-net-cdc-ncm

echo "=> kmods done"
