#!/bin/bash
# ==============================================================================
# 一加6 (enchilada) / 一加6T (fajita) 刷写 —— 纯 fastboot，不碰 EDL/GPT/ABL
#
# 和 tools/flash/{gpt,firmware,kernel,system}.sh 是两条完全独立的路径。
# 那四个是给 comma 硬件走的 EDL/QDL（qdl = 联网拉的第三方 JS）。
#
#   ⚠️ 绝不要对一加6 跑 `vamos flash all`。
#   firmware/ 里那 29 个 Comma 分区镜像（含 xbl/abl/tz/hyp/storsec）刷到一加6
#   上会直接不开机；gpt_main_0..5.img 是 Comma 的分区表，分区名和 LUN 分布都不同。
#
# 本脚本只写五个分区：boot_a, boot_b, userdata, vbmeta_a, vbmeta_b
# stock 的 ABL/XBL/modem/tz/hyp/aop/splash/devcfg/devinfo/storsec/GPT/persist
# 全部保持原厂不动 —— 所以这台设备随时能刷回官方固件，可逆。
#
# 用法：
#   ./vamos flash oneplus6                     # 默认 enchilada，需要 --yes 确认
#   ./vamos flash oneplus6 --yes               # 跳过确认
#   DEVICE=fajita ./vamos flash oneplus6 --yes # 刷一加6T
#   ROOT_PART=cache ./vamos flash oneplus6 --yes   # 根分区不是 userdata 时
#
# 参考实现：ubuntu-sdm845-mainline/flash.sh（逐条注释都保留了出处）
# 差异见文件末尾「与参考实现的差异」。
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DEVICE="${DEVICE:-enchilada}"              # enchilada = 一加6, fajita = 一加6T
ROOT_PART="${ROOT_PART:-userdata}"         # 根分区名。见 docs/oneplus6-retarget-plan §7
BUILD_DIR="${PROJECT_ROOT}/build"

BOOT_IMG="${BUILD_DIR}/output/${DEVICE}-boot.img"
# rootfs 由 tools/build/build_system.sh 产出：它先把 6G ext4 打在
# build/tmp-system/system.img，再用 img2simg 转成 Android sparse 落到
# build/system.img（OUT_IMAGE 变量）。sparse 镜像 fastboot 能直接识别
# ANDROFSEN 魔数并按 sparse 分块发送，不需要 host 侧再转一次。
#
# 注意它叫 system.img 不叫 rootfs.img —— 名字沿用 Comma 时代的分区名，
# 内容已经是 rootfs。要改名得同时改 build_system.sh 的 OUT_IMAGE。
ROOTFS_IMG="${ROOTFS_IMG:-${BUILD_DIR}/system.img}"
VBMETA_IMG="${PROJECT_ROOT}/tools/bin/vbmeta.img"

ASSUME_YES=0
for arg in "$@"; do
  case "${arg}" in
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "ERROR: 未知参数 '${arg}'（只用 --yes）"; exit 1 ;;
  esac
done

echo "=========================================="
echo "vamos flash oneplus6  (DEVICE=${DEVICE})"
echo "=========================================="

# ------------------------------------------------------------------------------
# Step 0: 预检
#
# 参考实现 2026-10-17 加过这一步，理由值得抄过来：
# 原来一上来就 `fastboot erase boot_a / boot_b`，而产物路径是后面才检查的。
# 路径打错、产物没编出来、或者 fastboot 半路失败时，两个 boot 槽已经被擦成 0，
# 「刷机失败」直接变成「没有内核可启」，设备掉在 fastboot 里 —— 比不刷更糟。
# 而且 erase 本身是多余的：`fastboot flash <part>` 就是整分区覆盖写，A/B 两个槽
# 各有各的镜像，刷完不存在残留旧内容的问题。
# 所以：boot 槽不 erase，改成像下面这样先把该有的文件都检查一遍。
# ------------------------------------------------------------------------------
echo "Step 0: 预检..."

for f in "${BOOT_IMG}" "${ROOTFS_IMG}" "${VBMETA_IMG}"; do
  if [ ! -f "${f}" ]; then
    echo "ERROR: 缺少产物 ${f}"
    echo "       boot/rootfs 镜像由 ./vamos build oneplus6 产出，先构建再刷。"
    exit 1
  fi
done

# 0 字节 / 截断的产物也能通过 -f 检查，但刷进去就是砖。
for f in "${BOOT_IMG}" "${ROOTFS_IMG}"; do
  size=$(stat -c %s "${f}")
  if [ "${size}" -lt 1048576 ]; then
    echo "ERROR: ${f} 只有 ${size} 字节，明显不是完整产物（构建被中断过？）"
    exit 1
  fi
done
echo "  [OK] 产物齐全 (boot $(stat -c %s "${BOOT_IMG}") B / rootfs $(stat -c %s "${ROOTFS_IMG}") B)"

if ! command -v fastboot >/dev/null 2>&1; then
  echo "ERROR: 找不到 fastboot（装 android-tools-fastboot 或 platform-tools）"
  exit 1
fi

# 设备识别：刷错设备不可逆。
# timeout 包住：没有设备时 fastboot 会一直打 "< waiting for any device >" 等下去，
# 不会自己返回。20 秒足够正常枚举（USB 握手是秒级）。
#
# 2026-10-17 实测坑（来自参考实现）：一加原厂 ABL 的 `fastboot getvar product`
# 返回的是 **SoC 名 `sdm845`**，不是设备代号。`getvar all` 里也只有
# `product:sdm845` / `variant:SDM UFS`；`fastboot oem device-info` 这类
# OnePlus 专属命令这条 bootloader 不支持（unknown command）。
# 所以把 `sdm845` 一并当合法值，设备到底是不是一加6/6T 由使用者物理确认。
PRODUCT="$(timeout 20 fastboot getvar product 2>&1 | sed -n 's/^product: *//p' | tr -d '\r' | head -1)" || true
if [ -z "${PRODUCT}" ]; then
  echo "ERROR: 读不到设备 product（设备没进 fastboot？USB 没接？）"
  echo "       手动确认：fastboot devices"
  exit 1
fi
case "${PRODUCT}" in
  enchilada|fajita) echo "  [OK] product=${PRODUCT}" ;;
  sdm845)          echo "  [OK] product=sdm845（一加 ABL 报的 SoC 名，按一加6/6T 处理）" ;;
  *) echo "ERROR: product=${PRODUCT}，不是一加6(enchilada)/6T(fajita)，拒绝刷机。"; exit 1 ;;
esac

echo ""
echo "Step 1: 刷 boot_a / boot_b ..."
# 必须显式刷两个槽。`fastboot flash boot` 只写当前槽（getvar current-slot: a），
# 另一个槽留着上一次的内容 —— A 槽启动失败时 ABL 回落 B 槽，于是启动的是个
# **版本对不上的旧内核**（rootfs 侧的东西全是新的），这种错很难查。
fastboot flash boot_a "${BOOT_IMG}"
fastboot flash boot_b "${BOOT_IMG}"

echo ""
echo "Step 2: 刷 ${ROOT_PART} ..."
# ⚠️ 这一步销毁设备上的全部数据。参考实现 2026-10-17 按要求把确认去掉了；
# 这里是有意保留的（见文件末尾「差异」），要同样行为就把下面四行删掉。
if [ "${ASSUME_YES}" -ne 1 ]; then
  echo "  ⚠️  即将 erase ${ROOT_PART} —— 设备上的全部用户数据会丢失。"
  read -r -p "  输入 yes 继续: " confirm
  if [ "${confirm}" != "yes" ]; then
    echo "  已取消。加 --yes 跳过确认。"
    echo "  只想试内核不碰数据：fastboot flash boot_a ${BOOT_IMG} && fastboot flash boot_b ${BOOT_IMG}"
    exit 1
  fi
fi
fastboot erase "${ROOT_PART}"
fastboot flash "${ROOT_PART}" "${ROOTFS_IMG}"

echo ""
echo "Step 3: 刷 vbmeta_a / vbmeta_b（关 dm-verity 和 AVB 校验）..."
# --disable-verity / --disable-verification 是 fastboot 在**发送前**改写 vbmeta
# header offset 120 处的 32 bit big-endian flags 字段：bit0 = hashtree(dm-verity)，
# bit1 = verification。两个都要带，只关一个等于没关。
# 设备实测：ABL 认 vbmeta_a / vbmeta_b 两个分区名（getvar partition-type:vbmeta_a/b = raw，
# has-slot:vbmeta = not found），所以必须用槽位名把两个槽都刷上，
# 只关当前槽的话另一个槽还会校验。
fastboot --disable-verity --disable-verification flash vbmeta_a "${VBMETA_IMG}"
fastboot --disable-verity --disable-verification flash vbmeta_b "${VBMETA_IMG}"

echo ""
echo "Step 4: 重启..."
fastboot reboot

echo ""
echo "=========================================="
echo "刷机完成。设备正在启动。"
echo "=========================================="

# ==============================================================================
# 与参考实现的差异（ubuntu-sdm845-mainline/flash.sh）
#
# 1. 产物路径：ref 用 build/output/{oneplus6-boot.img,rootfs.img}，
#    这里 boot 用 build/output/${DEVICE}-boot.img（enchilada 和 fajita 并存），
#    rootfs 用 build/system.img —— 那是 vamos build system（Void 配方）的
#    OUT_IMAGE，sparse ext4。ref 的 rootfs.img 是 Ubuntu 配方产物，本分支不用。
# 2. 根分区：ref 写死 userdata，这里用 ROOT_PART（默认 userdata）。
#    ref 的 fstab 只有 `/dev/sda17  /`，所以它必然是 userdata；
#    vamos 侧如果决定用 cache/system 分区，改一个环境变量就行。
# 3. `--yes` 确认：ref 在 2026-10-17 按要求去掉了。这里是有意保留 ——
#    erase userdata 是不可逆的，而这里没有 ref 那样的设备上下文（桌面环境、
#    已知就那台机器）。想要 ref 的行为：./vamos flash oneplus6 --yes，
#    或者删掉 Step 2 里那四行。
# 4. 没有 `fastboot erase boot_a/boot_b` —— 和 ref 一致（ref 2026-10-17 已删）。
# ==============================================================================
