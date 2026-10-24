#!/bin/sh
# adsp-start.sh - Audio DSP 启动（mainline remoteproc 接口）
#
# 原来的这份 Qualcomm 脚本做的每件事，在上游内核里都做不到：
#
#   * 等 /firmware/image/adsp.mdt
#     我们既不挂 modem 分区到 /firmware（参考项目也一样不挂），固件也全是
#     unified .mbn 而不是 .mdt。所以它必然等满 10 秒后 "Can not find the
#     adsp's firmware" + exit 1。
#   * /sys/bus/msm_subsys/devices/*/name|state|keep_alive
#     msm_subsys 是行下内核的 subsystem manager 总线，上游整个不存在。
#   * /sys/module/subsystem_restart/parameters/enable_debug
#     行下模块，上游不存在。
#   * /sys/kernel/boot_adsp/boot
#     行下 boot_<name> sysfs，上游 qcom_q6v5_pas.c 里没有这个属性。
#
# 真正能用的接口见 /usr/bin/rproc-boot.sh 头部的说明。
# 留这个路径是为了 /etc/initscripts/adsp.sh 和 udev/文档里的既有引用不用改。

exec /usr/bin/rproc-boot.sh adsp start
