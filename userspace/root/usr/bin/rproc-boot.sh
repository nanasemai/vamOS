#!/bin/sh
# rproc-boot - 用 mainline remoteproc 接口启动/停止 Qualcomm DSP
#
# 用法: rproc-boot.sh <dsp> [start|stop|status]
#   <dsp> 是 /sys/class/remoteproc/<name>/name 内容里的**子串**。
#   那个 name 就是 DT 节点名，所以本分支里是：
#     remoteproc-adsp      （adsp_pas: remoteproc-adsp，sdm845.dtsi:903）
#     remoteproc-cdsp      （cdsp_pas: remoteproc-cdsp，sdm845.dtsi:1039）
#     remoteproc@5c00000   （slpi_pas，sdm845.dtsi:3511）—— 不带 "slpi" 字样，
#                           用 "5c00000" 才能匹配到。
#
# 为什么需要这个脚本
# ------------------
# Comma 主板那套脚本（/usr/bin/cdsp.sh、/usr/local/qr-linux/adsp-start.sh）
# 操作的全是 Qualcomm 下行内核的接口：
#   /sys/kernel/boot_adsp/boot   /sys/kernel/boot_cdsp/boot
#   /sys/bus/msm_subsys/devices/*/keep_alive|state
#   /sys/module/subsystem_restart/parameters/enable_debug
# 本分支用的是上游内核，这些**一个都不存在**：
#   * qcom_q6v5_pas.c 里没有 boot_* sysfs 属性（全树 grep 无匹配）
#   * msm_subsys 总线整个不存在，subsystem_restart 模块也不存在
#
# 上游的接口是 remoteproc 设备自己的 sysfs（drivers/remoteproc/remoteproc_sysfs.c
# 的 state_store()）：
#   /sys/class/remoteproc/<name>/state   写 start | stop | detach
#   /sys/class/remoteproc/<name>/name    读设备名
#   /sys/class/remoteproc/<name>/firmware 读期望的固件名
# 状态字符串来自 rproc_state_string[]：
#   offline | suspended | running | crashed | attached | detached
# 只有 running 才是真的起来了。
#
# 时机：qcom_q6v5_pas 的描述符里 ADSP/CDSP 都是 .auto_boot = true，probe 时就
# 通过 request_firmware_nowait() 去要 qcom/sdm845/OnePlus/enchilada/*.mbn。
# 但我们的 initramfs 是 1.9M 的 busybox，里面**没有 /lib/firmware** —— 固件只在
# rootfs 里（Dockerfile COPY 到 /lib/firmware/），要等 switch_root 之后才读得
# 到。所以 auto-boot 在 initramfs 阶段基本必然 ENOENT，而这个服务就是
# rootfs 就绪后补的那一次启动。
# 设备压根没注册出来就安静跳过 —— 原来每次开机都白打一条错误日志。

dsp="$1"
action="${2:-start}"

if [ -z "$dsp" ] || [ ! -d /sys/class/remoteproc ]; then
  echo "WARN: /sys/class/remoteproc 不存在，跳过（CONFIG_REMOTEPROC 没开？）"
  exit 0
fi

target=""
for d in /sys/class/remoteproc/remoteproc*; do
  [ -d "$d" ] || continue
  case "$(cat "$d/name" 2>/dev/null)" in
    *"$dsp"*) target="$d"; break ;;
  esac
done

if [ -z "$target" ]; then
  echo "WARN: 找不到 $dsp 的 remoteproc 设备，跳过"
  echo "      现有的：$(ls /sys/class/remoteproc/ 2>/dev/null | tr '\n' ' ')"
  exit 0
fi

name="$(basename "$target")"
fw="$(cat "$target/firmware" 2>/dev/null || echo '?')"

case "$action" in
  status)
    echo "$name: $(cat "$target/state" 2>/dev/null)"
    ;;
  start)
    # 已经在跑了就别再 boot —— rproc_boot() 对已运行设备返回 -EBUSY。
    if [ "$(cat "$target/state" 2>/dev/null)" = running ]; then
      echo "$name 已经是 running，跳过"
      exit 0
    fi
    echo -n "Starting $name (firmware=$fw): "
    if ! echo start > "$target/state" 2>/dev/null; then
      echo "写入 state 失败"
      exit 1
    fi
    n=0
    while [ $n -lt 200 ]; do
      if [ "$(cat "$target/state" 2>/dev/null)" = running ]; then
        echo "running"
        exit 0
      fi
      n=$((n + 1))
      sleep 0.05
    done
    echo "10s 内没到 running（现在 $(cat "$target/state" 2>/dev/null)）—— 看 dmesg"
    exit 1
    ;;
  stop)
    if echo stop > "$target/state" 2>/dev/null; then
      echo "$name stopped"
    else
      echo "WARN: 停止 $name 失败"
    fi
    ;;
  *)
    echo "Usage: $0 <dsp> [start|stop|status]" >&2
    exit 1
    ;;
esac
