#!/bin/bash
# ==============================================================================
# 一加6 boot.img 打包
#
# 和 tools/build/build_kernel.sh 产出的 boot.img 有三处**结构性不同**，
# 所以单独一个脚本、不复用参数化，免得变成两个设备的 flag 矩阵：
#
#   Vamos (comma)                          一加6
#   --base 0x80000000                      --base 0x00000000
#   --ramdisk_offset 0x8000                --ramdisk_offset 0x01000000
#   --ramdisk /dev/null（无 initramfs）     --ramdisk initrd.cpio.gz（真 initramfs）
#   VBLE 签名（tools/build/vble-qti.key）   **不签名**（原厂 ABL 不校验 boot 镜像）
#   cmdline 里 console=…/androidboot.*     cmdline 里 root=/dev/sda17 rootwait
#   两个 dtb 拼接                          单个 dtb
#
# 不签名这一点不是偷懒：vble-qti.key 是 Comma ABL 的校验密钥，一加6 的原厂 ABL
# 根本不看签名，签名了也是浪费 2048 字节。
#
# 用法：./vamos build oneplus6
# 依赖：先跑 tools/build/build_kernel_oneplus6.sh（产出 build/out/Image.gz + dtb
#       + build/out/.config + build/rootfs/boot-workdir/kernel-dtb）
#
# 参考实现：ubuntu-sdm845-mainline/tools/build/build_bootimg.sh
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
OUT_DIR="${BUILD_DIR}/out"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
BOOT_WORKDIR="${ROOTFS_DIR}/boot-workdir"
# boot.img 落在 build/output/，和 build_kernel_oneplus6.sh 的 build/out/ 分开
# （out 是 kbuild 的输出目录，里面全是中间产物；output 只放最终镜像）。
# tools/flash/oneplus6.sh 从这里读 boot.img。
OUTPUT_DIR="${BUILD_DIR}/output"

DEVICE="${DEVICE:-enchilada}"
# 根设备：ref 写死 /dev/sda17（= stock GPT 的 userdata）。
# 如果决定改用 by-partlabel，改这里。
ROOT_DEV="${ROOT_DEV:-/dev/sda17}"

BOOT_IMG="${OUTPUT_DIR}/${DEVICE}-boot.img"
KERNEL_DTB="${BOOT_WORKDIR}/kernel-dtb"
IMAGE_GZ="${OUT_DIR}/arch/arm64/boot/Image.gz"
DTB="${OUT_DIR}/arch/arm64/boot/dts/qcom/sdm845-oneplus-${DEVICE}.dtb"
MKBOOTIMG="${PROJECT_ROOT}/tools/bin/mkbootimg"

# initramfs 来源：优先用 submodule（可复现），退回联网 clone（分支固定）
INITRD_DIR="${PROJECT_ROOT}/kernel/initrd"
INITRD_URL="${INITRD_URL:-https://github.com/nanasemai/initrd.git}"
INITRD_BRANCH="${INITRD_BRANCH:-oneplus6-initrd}"

BUILD_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${BUILD_DIR}/logs/bootimg_${DEVICE}_${BUILD_TIMESTAMP}.log"
mkdir -p "${BUILD_DIR}/logs" "${BOOT_WORKDIR}" "${OUTPUT_DIR}"
: > "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[INFO] Log file: ${LOG_FILE}"
echo "[INFO] DEVICE=${DEVICE} ROOT_DEV=${ROOT_DEV}"

# ------------------------------------------------------------------------------
# Step 1: initramfs
#
# 参考实现每次构建都联网 clone（分支固定，不 pin 提交）。分支可能被 force-push，
# 而且 Vamos 的构建容器是离线的。所以：submodule 优先，clone 兜底。
# 无论走哪条，都把实际用到的 commit 写进日志 —— 不 pin 提交时这是唯一的追溯链。
# ------------------------------------------------------------------------------
echo "Step 1: 准备 initramfs ..."
if [ -f "${INITRD_DIR}/build.sh" ]; then
  echo "  [submodule] ${INITRD_DIR}"
else
  rm -rf "${BUILD_DIR}/initrd-clone"
  INITRD_DIR="${BUILD_DIR}/initrd-clone"
  for attempt in $(seq 1 3); do
    echo "  [clone] 尝试 ${attempt}/3 (branch ${INITRD_BRANCH}) ..."
    git clone -b "${INITRD_BRANCH}" "${INITRD_URL}" "${INITRD_DIR}" && break
    rm -rf "${INITRD_DIR}"
  done
  [ -d "${INITRD_DIR}" ] || { echo "ERROR: clone initrd 失败"; exit 1; }
fi

if [ ! -f "${INITRD_DIR}/build.sh" ]; then
  echo "ERROR: ${INITRD_DIR}/build.sh 不存在"
  exit 1
fi
INITRD_COMMIT="$(git -C "${INITRD_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "  initrd: ${INITRD_BRANCH} @ ${INITRD_COMMIT}"

# build.sh 的签名是 `build.sh [输出路径]`。不传的话它把 initrd.cpio.gz 写到
# **当前目录**，也就是子模块根目录 —— 会弄脏 kernel/initrd 的工作区，而且
# 下次构建前 `git submodule update` 可能把它清掉、也可能留着上次产物。
# 所以显式传绝对路径。
INITRD_CPIO="${BOOT_WORKDIR}/initrd.cpio.gz"
rm -f "${INITRD_CPIO}"
( cd "${INITRD_DIR}" && bash build.sh "${INITRD_CPIO}" )
if [ ! -f "${INITRD_CPIO}" ]; then
  echo "ERROR: build.sh 没产出 ${INITRD_CPIO}"
  exit 1
fi
echo "  initrd.cpio.gz: $(stat -c %s "${INITRD_CPIO}") 字节"

# ------------------------------------------------------------------------------
# Step 2: 校验 kernel-dtb
# ------------------------------------------------------------------------------
echo ""
echo "Step 2: 校验 kernel-dtb ..."
for f in "${IMAGE_GZ}" "${DTB}" "${KERNEL_DTB}" "${OUT_DIR}/.config"; do
  if [ ! -f "${f}" ]; then
    echo "ERROR: 缺少 ${f}"
    echo "       先跑 tools/build/build_kernel_oneplus6.sh"
    exit 1
  fi
done

# 防打进过期产物。kernel-dtb 是 `cat Image.gz <dtb>` 拼的，所以判据可以是**内容**：
# 它的 md5 必须等于当前这两个文件拼起来的 md5。
#
# 不比较 mtime：`cp -a` 会保留时间戳、时钟会跳、产物会从别处拷回来 —— mtime 判断
# 会假阳性地判成"最新的"，于是静默打进一个新旧混合的 boot.img，刷进设备才发作。
# 内容判据没有这种假阳性，代价只是读一遍 Image.gz（20MB，可忽略）。
EXPECTED_MD5="$({ cat "${IMAGE_GZ}" "${DTB}"; } | md5sum | awk '{print $1}')"
ACTUAL_MD5="$(md5sum "${KERNEL_DTB}" | awk '{print $1}')"
if [ "${ACTUAL_MD5}" != "${EXPECTED_MD5}" ]; then
  echo "ERROR: kernel-dtb 与当前 Image.gz + DTB **内容不一致**（不是时间戳判断）。"
  echo "  kernel-dtb  : md5 ${ACTUAL_MD5}"
  echo "  拼接结果    : md5 ${EXPECTED_MD5}"
  echo "说明内核重编过而 bundle 没重生成。重新跑 build_kernel_oneplus6.sh。"
  exit 1
fi
echo "  [OK] kernel-dtb 逐字节一致 (md5 ${ACTUAL_MD5})"

# ------------------------------------------------------------------------------
# Step 3: 启动关键路径校验
#
# 这一关查的是**内核配置**，不是产物。它拦的是这类问题：某个 UFS/时钟/调节器
# 驱动被编成了 =m。initramfs 里没有 .ko、init 用 mdev 而非 udev（mdev 不按 alias
# 自动加载模块），所以 switch_root 之前只有内置驱动可用。
# 一旦 /dev/sda17 出不来，而 init 又不检查 mount 返回值，就会静默 switch_root
# 到空目录 -> init 死亡 -> panic -> ABL 两个槽判失败 -> 回 fastboot，**全程零报错**。
# ------------------------------------------------------------------------------
echo ""
echo "Step 3: 校验启动关键驱动是否内置 ..."
python3 "${SCRIPT_DIR}/check_boot_path.py" "${OUT_DIR}/.config" || {
  echo ""
  echo "ERROR: 启动关键路径校验未通过，不打包。修好配置后重新构建。"
  exit 1
}

# ------------------------------------------------------------------------------
# Step 4: 打包
# ------------------------------------------------------------------------------
echo ""
echo "Step 4: 打包 boot.img ..."
if [ ! -f "${MKBOOTIMG}" ]; then
  echo "ERROR: mkbootimg 不存在: ${MKBOOTIMG}"
  exit 1
fi

CMDLINE="earlyprintk=serial root=${ROOT_DEV} rootfstype=ext4 rootwait=30 loglevel=7 fbcon=font:16x16 consoleblank=0"

"${MKBOOTIMG}" \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 \
  --pagesize 4096 \
  --second_offset 0x00f00000 \
  --ramdisk "${BOOT_WORKDIR}/initrd.cpio.gz" \
  --cmdline "${CMDLINE}" \
  --kernel "${KERNEL_DTB}" \
  --output "${BOOT_IMG}"

echo ""
echo "=========================================="
echo "OK: ${BOOT_IMG} ($(stat -c %s "${BOOT_IMG}") 字节)"
echo "=========================================="
echo "SHA256: $(sha256sum "${BOOT_IMG}" | awk '{print $1}')"
echo ""
echo "刷机: ./vamos flash oneplus6 --yes"
