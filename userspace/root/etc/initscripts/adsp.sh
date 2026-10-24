#!/bin/sh
###############################################################################
#
# adsp - System V init wrapper for the Audio DSP
#
# runit 的 /etc/sv/adsp/run 调 `adsp.sh start`。
# 真正的动作在 /usr/bin/rproc-boot.sh（mainline remoteproc 接口）；原先写的
# /sys/kernel/boot_adsp/boot 在上游内核里不存在 —— 见
# /usr/local/qr-linux/adsp-start.sh 的注释。
#
# 注意去掉 set -e：`stop` 在 DSP 本来就没起来时返回 1 是正常情况，不该让
# 整个脚本非零退出（runit 的 run 脚本虽然不 set -e，但 SysV 语义下 exit 0 更稳）。
#
###############################################################################

case "$1" in
  start)
        /usr/local/qr-linux/adsp-start.sh
        rc=$?
        [ $rc -eq 0 ] && echo "adsp: up" || echo "WARN: adsp 没起来 (rc=$rc)，看 dmesg"
        ;;
  stop)
        /usr/bin/rproc-boot.sh adsp stop
        ;;
  restart)
        $0 stop
        $0 start
        ;;
  *)
        echo "Usage: $0 { start | stop | restart}" >&2
        exit 1
        ;;
esac

exit 0
