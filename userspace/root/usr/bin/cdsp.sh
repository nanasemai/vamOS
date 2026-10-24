#!/bin/sh
# cdsp - Compute DSP 启动（mainline remoteproc 接口）
#
# 原来的实现：
#   if [ -f /sys/kernel/boot_cdsp/boot ]; then echo 1 > ...
#   else echo "File not found!"
# 那个 boot_cdsp 是 Qualcomm 下行内核的 boot_<name> sysfs 驱动。上游内核里
# qcom_q6v5_pas.c 完全没有这个属性（全树 grep 无匹配），所以这个脚本每次开机
# 都只会打一条 "File not found! : /sys/kernel/boot_cdsp/boot"，然后 exit 0 ——
# CDSP 从来不会被它启动。
#
# 真正能用的接口见 /usr/bin/rproc-boot.sh 头部的说明。

exec /usr/bin/rproc-boot.sh cdsp start
