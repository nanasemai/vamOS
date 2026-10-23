#!/bin/bash
# ==============================================================================
# 一加6 / 一加6T 内核构建
#
# 从 ubuntu-sdm845-mainline/tools/build/build_kernel.sh 移植，只改必须改的：
#
#   1. PATCHES_DIR   -> kernel/patches/oneplus6/
#      分支只服务一加6，补丁不再散在 kernel/patches 根目录，避免以后加别的东西
#      时被 `*.patch` 通配误抓（29 个 Comma 补丁已随本分支删掉）。
#
#   2. DTS 不处理
#      SDM845 的 dts/dtsi 在这个 kernel 树里就是上游的，`make dtbs` 直接产出
#      arch/arm64/boot/dts/qcom/sdm845-oneplus-{enchilada,fajita}.dtb。
#      Comma 那套 install_dts()（往树里塞自己的 dtsi + makefile patch）整个不要了。
#
#   3. 不做 VBLE 签名
#      vble-qti.key 是 Comma ABL 的校验密钥，一加6 原厂 ABL 不校验 boot 镜像。
#      该密钥文件也已从本分支删除。
#
#   4. 出 kernel-rootfs.tar + kernel-release
#      Vamos 的 tools/build/Dockerfile 里有 `ADD ./build/kernel-rootfs.tar /`，
#      这是模块和固件进入设备镜像的唯一入口，ref 没有这一步（它的 rootfs 是
#      Ubuntu 的 deb 体系，不靠 tar 拼装）。
#
# 保留（照抄，不要改）：
#   - check_defconfig.sh 门禁（defconfig 是完整 .config，不是片段，一次基线漂移
#     就能把多个符号静默打回 =n，构建照样成功）
#   - 内存约束的并行度换算 + docker_make 4 次重试（aarch64-none-elf-gcc 15.2
#     会瞬时 ICE，每次崩在不同文件上，重试靠 ccache 命中是便宜的）
#   - 固件/模块拷完在 host 上数一遍（`cp ... || true` 之后无条件报成功是这类
#     脚本最容易踩的坑：旧产物混进新镜像，只在设备上发作）
#   - .kernelrelease 落盘（下游按目录名比对 krel，现算会带/不带 -dirty 抖动）
#
# 用法：./vamos build oneplus6        （DEVICE=fajita 构建一加6T）
# 产出：build/out/{Image.gz,*.dtb,.config,.kernelrelease}
#       build/rootfs/{lib/modules,lib/firmware}
#       build/rootfs/boot-workdir/kernel-dtb   （给 build_bootimg_oneplus6.sh 用）
#       build/kernel-rootfs.tar               （给 Void 根文件系统的 Dockerfile）
#       build/kernel-release                  （krel 字符串，--build-arg KERNEL_RELEASE）
#
# 下游：
#   build_bootimg_oneplus6.sh   Image.gz + dtb + kernel-dtb -> build/output/<device>-boot.img
#   build_system.sh             kernel-rootfs.tar + kernel-release -> Void rootfs -> system.img
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
OUT_DIR="${BUILD_DIR}/out"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

KERNEL_DIR="${PROJECT_ROOT}/kernel/linux"
DEFCONFIG_FILE="${PROJECT_ROOT}/kernel/configs/oneplus6/oneplus6_defconfig"
PATCHES_DIR="${PROJECT_ROOT}/kernel/patches/oneplus6"

ARCH="arm64"
CROSS_COMPILE="aarch64-none-elf-"
HOST_OS="$(uname)"
HOST_ARCH="$(uname -m)"
CONTAINER_ID=""

DEVICE="${DEVICE:-enchilada}"
DTB_NAME="sdm845-oneplus-${DEVICE}.dtb"

SCRIPT_START_TIME=$(date +%s)

echo "=========================================="
echo "一加6 内核构建开始: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""
echo "Host:   ${HOST_OS} (${HOST_ARCH})"
echo "Target: ${ARCH} (${CROSS_COMPILE}gcc)"
echo "Device: ${DEVICE} (DTB: ${DTB_NAME})"
echo ""
echo "Project Root: ${PROJECT_ROOT}"
echo "Build Dir:    ${BUILD_DIR}"
echo "Kernel Dir:   ${KERNEL_DIR}"
echo ""

mkdir -p "${OUT_DIR}"
mkdir -p "${ROOTFS_DIR}/boot"
mkdir -p "${ROOTFS_DIR}/lib/firmware"
mkdir -p "${ROOTFS_DIR}/lib/modules"
mkdir -p "${ROOTFS_DIR}/boot-workdir"

LOG_DIR="${BUILD_DIR}/logs"
# 带时间戳，重跑不覆盖上一次。GCC ICE 每次崩在不同文件上，日志是唯一能复盘的
# 东西（哪几个 patch 应用失败、哪一步的 make 崩在哪），覆盖掉就没法查了。
BUILD_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/kernel_${DEVICE}_${BUILD_TIMESTAMP}.log"
mkdir -p "${LOG_DIR}"
: > "${LOG_FILE}"

# 整个脚本的输出都落盘。只给 docker exec 那几处加 tee -a 的话，前面 patch
# 应用 / check_defconfig / kernel-dtb 拼接的输出只进终端，一关就丢 —— 而
# "哪些 patch 打不上" 恰恰是需要追查的信息。
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[INFO] Log file: ${LOG_FILE}"

# ------------------------------------------------------------------------------
# Step 0: 前置检查
# ------------------------------------------------------------------------------
if [ ! -f "$KERNEL_DIR/Makefile" ]; then
    echo "[ERROR] 内核子模块未初始化: ${KERNEL_DIR}/Makefile 不存在"
    echo "[ERROR] 运行: ./vamos setup"
    exit 1
fi
echo "[OK] 内核 Makefile 存在: ${KERNEL_DIR}/Makefile"
echo "     内核提交: $(git -C "$KERNEL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [ ! -f "$DEFCONFIG_FILE" ]; then
    echo "[ERROR] 找不到 defconfig: ${DEFCONFIG_FILE}"
    exit 1
fi
echo "[OK] Defconfig 存在: ${DEFCONFIG_FILE}"

# ------------------------------------------------------------------------------
# Step 1: 应用补丁
#
# 顺序 = glob 字典序，这是**约定**。这 17 个补丁里有真实的顺序依赖：
#   imx519-min-vblank  -> imx519-preserve-vblank          (同文件，后者依赖前者的 vblank 逻辑)
#   rtc-pm8xxx-skip-ctrl-rw -> rtc-pm8xxx-write-unsupported (同文件)
#   adreno_opencl 同时改 adreno_gpu.c 和 msm_submitqueue.c
#   sdm845-oneplus-common.dtsi 被 4 个补丁叠加
# 已验证：在 pin e38405d01d1 上按此顺序应用 17/17 全部干净通过，且 13 个目标文件
# 与参考实现的工作区逐字节一致。改文件名前缀（加序号、改大小写）都会破坏这条链。
# ------------------------------------------------------------------------------
echo ""
echo "[1/7] 应用补丁 (${PATCHES_DIR}/) ..."
PATCH_COUNT=$(ls -1 "$PATCHES_DIR"/*.patch 2>/dev/null | wc -l)
if [ "${PATCH_COUNT}" -eq 0 ]; then
    echo "[ERROR] ${PATCHES_DIR}/ 下没有 *.patch"
    exit 1
fi
echo "[INFO] 共 ${PATCH_COUNT} 个补丁，按字典序应用"

cd "$KERNEL_DIR"
# 还原到 pinned 提交的干净状态。失败必须停：不干净的话 apply 会打在半脏的树上，
# 要么整个不生效、要么和已有改动叠成别的东西 —— 两种都不报错。
if ! git checkout -- . 2>/dev/null; then
    echo "[ERROR] git checkout -- . 失败，子模块没还原干净，中止。"
    echo "[ERROR] 此刻 apply patch 的结果不可信，硬编出来的内核可能是半套补丁。"
    exit 1
fi
PATCH_FAILED=0
for patch in "$PATCHES_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        echo "[INFO] 应用: $(basename "$patch")"
        # 两种失败分开报，且**都要中止**：
        #   --check 失败 = patch 跟当前树对不上（上游改了上下文 / 已合入）
        #   apply   失败 = 检查通过但写入失败
        # 不能 `|| echo "[WARN]"` 然后继续：补丁承载背光、RTC 可控时、
        # USB dual_role、相机 sensor/马达、GPU OpenCL 这些**功能**，丢一个在
        # 设备上表现为"驱动不对"，而构建显示成功，查起来极贵。
        if ! git apply --check "$patch"; then
            echo "[ERROR] patch 与当前子模块对不上: $(basename "$patch")"
            PATCH_FAILED=$((PATCH_FAILED + 1))
            continue
        fi
        if git apply "$patch"; then
            echo "[OK] 已应用: $(basename "$patch")"
        else
            echo "[ERROR] git apply 失败: $(basename "$patch")"
            PATCH_FAILED=$((PATCH_FAILED + 1))
        fi
    fi
done
cd - > /dev/null
if [ "${PATCH_FAILED}" -gt 0 ]; then
    echo ""
    echo "[ERROR] ${PATCH_FAILED} 个补丁没打上，中止构建。"
    echo "[ERROR] 继续编译的话产物里会静默缺掉这些功能，且构建显示成功。"
    echo "[ERROR] 处理：修好/更新该补丁，或确认已合入上游后删掉该文件。"
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: 清理上一次的产物
# ------------------------------------------------------------------------------
echo ""
echo "[2/7] 清理上次产物 ..."
rm -rf "${OUT_DIR}"/.tmp_versions 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/boot/"* 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/modules" 2>/dev/null || true
# 固件也一起清：不清的话，kernel/firmware 里**删掉**的文件会永久留在暂存树里、
# 继而被打进镜像。名字没变的话驱动会静默加载到一份早已作废的固件
# （GPU/venus/IPA 都吃这个），排查时会以为"固件明明在啊"。
rm -rf "${ROOTFS_DIR}/lib/firmware" 2>/dev/null || true
# 删除上一次的 Image.gz，否则构建失败时后面的 test -f 会被过期产物骗过
rm -f "${OUT_DIR}/arch/arm64/boot/Image.gz" 2>/dev/null || true
rm -f "${ROOTFS_DIR}/boot-workdir/kernel-dtb" 2>/dev/null || true
# 上次留下的 tar 也一起删：不清的话，这次编译到一半崩了，build_system.sh 仍会
# 拿着**上一次**的模块去拼 rootfs，产物看起来是好的，实际上是新旧混杂的镜像。
rm -f "${BUILD_DIR}/kernel-rootfs.tar" "${BUILD_DIR}/kernel-release" "${BUILD_DIR}/kernel-source-revision" 2>/dev/null || true
echo "[OK] 清理完成"

# ------------------------------------------------------------------------------
# Step 3: Docker builder 镜像
# ------------------------------------------------------------------------------
echo ""
echo "[3/7] Docker builder 镜像 ..."
if sudo docker image inspect alpine:3.23.3 >/dev/null 2>&1; then
    echo "[INFO] alpine:3.23.3 已在本地"
else
    echo "[INFO] 拉取 alpine:3.23.3 ..."
    sudo docker pull alpine:3.23.3
fi

echo "[INFO] Dockerfile: tools/build/Dockerfile.builder"
echo "[INFO] User: $(id -un) (UID: $(id -u), GID: $(id -g))"
export DOCKER_BUILDKIT=1
sudo docker build --network host -f tools/build/Dockerfile.builder -t sdm845-kernel-builder "$PROJECT_ROOT" \
    --build-arg UNAME="$(id -un)" \
    --build-arg UID="$(id -u)" \
    --build-arg GID="$(id -g)"

if sudo docker image inspect sdm845-kernel-builder:latest >/dev/null 2>&1; then
    echo "[OK] builder 镜像就绪"
else
    echo "[ERROR] builder 镜像构建失败"
    exit 1
fi

echo ""
echo "[4/7] 启动容器 ..."
CONTAINER_ID=$(sudo docker run -d \
    --network host \
    -u "$(id -u):$(id -g)" \
    -v "$PROJECT_ROOT":"$PROJECT_ROOT":rw \
    -v "${BUILD_DIR}/.ccache-kernel:/ccache" \
    -w "$PROJECT_ROOT" \
    "sdm845-kernel-builder:latest")
echo "[INFO] Container ID: ${CONTAINER_ID}"

trap 'echo "[CLEANUP] 停止容器 ${CONTAINER_ID}..."; sudo docker container rm -f "${CONTAINER_ID:-}" >/dev/null 2>&1 || true; echo "[CLEANUP] 完成"' EXIT

if sudo docker ps -q --filter "id=${CONTAINER_ID}" | grep -q .; then
    echo "[OK] 容器已启动"
else
    echo "[ERROR] 容器启动失败"
    exit 1
fi

sudo docker exec -i "$CONTAINER_ID" bash -c "test -f ${KERNEL_DIR}/Makefile && echo '[OK] 容器内可见内核源码'"
sudo docker exec -i "$CONTAINER_ID" bash -c "test -f ${DEFCONFIG_FILE} && echo '[OK] 容器内可见 defconfig'"

# ------------------------------------------------------------------------------
# Step 4: 固件
# ------------------------------------------------------------------------------
echo ""
echo "[5/7] 拷贝固件到 rootfs 暂存树 ..."
FIRMWARE_COUNT=$(find "${PROJECT_ROOT}/kernel/firmware" -type f 2>/dev/null | wc -l)
echo "[INFO] 源固件文件数: ${FIRMWARE_COUNT}"
if [ "${FIRMWARE_COUNT}" -eq 0 ]; then
    echo "[ERROR] ${PROJECT_ROOT}/kernel/firmware 里一个文件都没有"
    echo "[ERROR] 拷不出固件的话 GPU/venus/IPA/wlan 在设备上全是 probe 失败，"
    echo "[ERROR] 而这里只会显示成功。"
    exit 1
fi
mkdir -p "${ROOTFS_DIR}/lib/firmware"
# 不 `cp ... || true` 之后无条件报成功：拷贝失败（路径不对、挂载丢失、磁盘满）
# 会被完全吞掉，紧接着报成功。真拷 + host 侧断言。
cp -a "${PROJECT_ROOT}/kernel/firmware/." "${ROOTFS_DIR}/lib/firmware/" || {
    echo "[ERROR] 固件拷贝失败（kernel/firmware -> ${ROOTFS_DIR}/lib/firmware）"
    exit 1
}
FIRMWARE_COUNT_HOST=$(find "${ROOTFS_DIR}/lib/firmware" -type f 2>/dev/null | wc -l)
echo "[OK] 固件已拷贝，host 暂存树 ${FIRMWARE_COUNT_HOST} 个文件"
if [ "${FIRMWARE_COUNT_HOST}" -lt "${FIRMWARE_COUNT}" ]; then
    echo "[ERROR] host 暂存树固件数（${FIRMWARE_COUNT_HOST}）少于源目录（${FIRMWARE_COUNT}）"
    exit 1
fi

# 固件不进内核镜像：CONFIG_FIRMWARE_IN_KERNEL 在本 defconfig 里是 unset，所以
# CONFIG_EXTRA_FIRMWARE 那串清单是**空转**的，全部走运行时 request_firmware()
# 从 /lib/firmware 读。这也解释了为什么 initramfs 之前不 mount /firmware 也能开
# 机 —— GPU/venus/ADSP/wlan 都要等 rootfs 挂上才有固件。
FIRMKV=$(grep -c '^CONFIG_FIRMWARE_IN_KERNEL=y' "${DEFCONFIG_FILE}" || true)
if [ "${FIRMKV}" -gt 0 ]; then
    echo "[WARN] CONFIG_FIRMWARE_IN_KERNEL=y：固件会被嵌进 Image.gz，"
    echo "[WARN] EXTRA_FIRMWARE 清单里的每个文件都必须真实存在于 kernel/firmware/。"
fi

# ------------------------------------------------------------------------------
# Step 5: .config
# ------------------------------------------------------------------------------
echo ""
echo "[6/7] 生成 .config ..."
# oneplus6_defconfig 是**完整** .config（不是片段），直接 cp，不做 fragment merge。
# fragment merge 会引入"基线漂移就静默降级"的问题，这里是有意避免的。
sudo docker exec -i "$CONTAINER_ID" bash -c "cp ${DEFCONFIG_FILE} ${OUT_DIR}/.config"
sudo docker exec -i "$CONTAINER_ID" bash -c "test -f ${OUT_DIR}/.config && echo '[OK] .config 已生成'"

# 关键开关兜底校验。一旦有人拿别的分支的 .config 当基线重新生成，改名的符号会
# 静默掉成 =n（2026-10 掉过 PMI8998_HAPTICS / LC89821X / HW_RANDOM_QCOM），
# 构建本身不会报错。这里在编译前硬性核对。
echo "[INFO] 校验关键内核开关 ..."
if ! "${SCRIPT_DIR}/check_defconfig.sh" "${OUT_DIR}/.config"; then
    echo "[ERROR] 关键内核开关校验失败，构建中止。"
    echo "[ERROR] 清单: ${PROJECT_ROOT}/kernel/configs/oneplus6/required_config.conf"
    exit 1
fi
echo "[OK] 内核配置校验通过"

# ------------------------------------------------------------------------------
# Step 6: 编译
# ------------------------------------------------------------------------------
echo ""
echo "[7/7] 编译内核 ..."
echo "[INFO] Targets: Image.gz dtbs modules"
# 并行度必须受内存约束，不能只看核数。
# 内核编译单个 cc1 峰值可达 1~2GiB，-j4 时并发预留会顶到 CommitLimit；
# 本机 overcommit_memory=0（启发式拒绝），被拒的大块 mmap 在 cc1 里表现为
# 随机的 "internal compiler error"（预处理器段错误、optimizer ICE、Illegal
# instruction 都出现过，且每次都在不同文件上崩 —— 因为没有同一个"坏"文件）。
AVAIL_MEM_MB=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) / 1024 ))
MEM_JOBS=$(( AVAIL_MEM_MB / 2000 ))
[ "$MEM_JOBS" -lt 1 ] && MEM_JOBS=1
[ "$MEM_JOBS" -gt "$(nproc)" ] && MEM_JOBS=$(nproc)

PARALLEL_JOBS="${MEM_JOBS}"
JOBS_SOURCE="内存/核数自动换算"
if [ -n "${JOBS_OVERRIDE:-}" ]; then
    case "${JOBS_OVERRIDE}" in
        ''|*[!0-9]*)
            echo "[ERROR] JOBS_OVERRIDE 必须是正整数，收到：'${JOBS_OVERRIDE}'"
            exit 1 ;;
    esac
    if [ "${JOBS_OVERRIDE}" -lt 1 ]; then
        echo "[ERROR] JOBS_OVERRIDE 必须 >= 1，收到：'${JOBS_OVERRIDE}'"
        exit 1
    fi
    PARALLEL_JOBS="${JOBS_OVERRIDE}"
    JOBS_SOURCE="JOBS_OVERRIDE=${JOBS_OVERRIDE}"
    # JOBS_OVERRIDE 也要过同一道上限校验：它的存在意义是"环境变了、想手动调低"，
    # 很容易被当成"想快点编"而调高，而那正是上面会引发随机 ICE 的用法。
    if [ "${PARALLEL_JOBS}" -gt "${MEM_JOBS}" ] && [ "${ALLOW_HIGH_JOBS:-0}" != "1" ]; then
        echo "[WARN] JOBS_OVERRIDE=${JOBS_OVERRIDE} 超过内存能撑的 ${MEM_JOBS}"
        echo "[WARN]   直接这么跑会以随机 internal compiler error 的形式失败"
        echo "[WARN]   已压回 ${MEM_JOBS}。确实要试更大的值：ALLOW_HIGH_JOBS=1 JOBS_OVERRIDE=... "
        PARALLEL_JOBS="${MEM_JOBS}"
        JOBS_SOURCE="JOBS_OVERRIDE=${JOBS_OVERRIDE} -> 压回内存上限 ${MEM_JOBS}"
    fi
fi
echo "[INFO] 并行度: ${PARALLEL_JOBS} (${JOBS_SOURCE}; 核数 $(nproc), 可用内存 ${AVAIL_MEM_MB}MB, ~2000MB/job)"
echo "[INFO] 预计 10-30 分钟"
echo ""

# docker_make：本树在 aarch64-none-elf-gcc 15.2 上偶发 GCC ICE（编译器段错误）。
# 已确认是瞬时的：同一个 .o 在下一次 make 里能正常编过。ccache 复用已成功的
# 对象文件，所以重试很便宜 —— 失败多发生在晚期目标，重跑时前面的对象全部命中缓存。
# 注意必须 set -o pipefail：否则管道的退出码是 tee 的，make 失败会被吞掉。
docker_make() {
    local attempts="$1"
    local make_args="$2"
    local attempt
    for attempt in $(seq 1 "${attempts}"); do
        echo "[INFO] make 第 ${attempt}/${attempts} 次 ..."
        if sudo docker exec -i "$CONTAINER_ID" bash -c "set -o pipefail; cd ${KERNEL_DIR} && \
            make O=${OUT_DIR} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} ${make_args} 2>&1 | tee -a ${LOG_FILE}"; then
            return 0
        fi
        echo "[WARN] make 第 ${attempt} 次失败（大概率是瞬时 GCC ICE），重试 ..."
    done
    return 1
}

docker_make 4 "-j${PARALLEL_JOBS} Image.gz dtbs modules" || {
    echo "[ERROR] 内核编译在 4 次尝试后仍然失败"
    exit 1
}

IMAGE_GZ="${OUT_DIR}/arch/arm64/boot/Image.gz"
DTB="${OUT_DIR}/arch/arm64/boot/dts/qcom/${DTB_NAME}"
if sudo docker exec -i "$CONTAINER_ID" test -f "${IMAGE_GZ}"; then
    echo "[OK] 内核镜像: ${IMAGE_GZ}"
else
    echo "[ERROR] 内核镜像构建失败"
    exit 1
fi
if sudo docker exec -i "$CONTAINER_ID" test -f "${DTB}"; then
    echo "[OK] DTB: ${DTB_NAME}"
else
    echo "[ERROR] DTB 构建失败: ${DTB_NAME}"
    echo "[ERROR] 检查 arch/arm64/boot/dts/qcom/Makefile 是否包含该目标"
    exit 1
fi

echo ""
echo "[INFO] 安装内核模块 ..."
docker_make 2 "modules_install INSTALL_MOD_PATH=/tmp/kernel-rootfs" || {
    echo "[ERROR] modules_install 在 2 次尝试后仍然失败"
    exit 1
}

MODULES_COUNT=$(sudo docker exec -i "$CONTAINER_ID" find /tmp/kernel-rootfs/lib/modules -name '*.ko' 2>/dev/null | wc -l)
echo "[OK] 容器内 ${MODULES_COUNT} 个内核模块"

# 模块拷回 host。不 `cp ... || true` 之后无条件报成功：那样 host 暂存树里还是
# **上一次**的模块，后面所有步骤照样往下走 —— 典型的"静默不写"。
sudo docker exec -i "$CONTAINER_ID" cp -a /tmp/kernel-rootfs/lib/modules "${ROOTFS_DIR}/lib/" || {
    echo "[ERROR] 模块从容器拷到 host 失败（${ROOTFS_DIR}/lib/modules）"
    exit 1
}
MODULES_COUNT_HOST=$(find "${ROOTFS_DIR}/lib/modules" -name '*.ko' 2>/dev/null | wc -l)
echo "[OK] 模块已拷到 ${ROOTFS_DIR}/lib/modules（容器 ${MODULES_COUNT} / host ${MODULES_COUNT_HOST}）"
if [ "${MODULES_COUNT_HOST}" -eq 0 ] || [ "${MODULES_COUNT_HOST}" -lt "${MODULES_COUNT}" ]; then
    echo "[ERROR] host 暂存树的模块数少于容器内 —— 这次没真的拷过来"
    echo "[ERROR] 后续 build_rootfs 会把旧模块打进镜像，且不会报错。"
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 7: kernel-dtb bundle + 打包
# ------------------------------------------------------------------------------
echo ""
echo "[INFO] 生成 kernel-dtb bundle (Image.gz + DTB) ..."
sudo docker exec -i "$CONTAINER_ID" bash -c "
    cp ${IMAGE_GZ} ${ROOTFS_DIR}/boot-workdir/Image.gz
    cp ${DTB} ${ROOTFS_DIR}/boot-workdir/${DTB_NAME}
    if [ -f ${ROOTFS_DIR}/boot-workdir/Image.gz ] && [ -f ${ROOTFS_DIR}/boot-workdir/${DTB_NAME} ]; then
        cat ${ROOTFS_DIR}/boot-workdir/Image.gz ${ROOTFS_DIR}/boot-workdir/${DTB_NAME} > ${ROOTFS_DIR}/boot-workdir/kernel-dtb
        echo '[OK] kernel-dtb bundle 已生成'
    else
        echo '[ERROR] kernel-dtb bundle 生成失败'
        exit 1
    fi
"

# 写下本次真正的 krel。为什么不让下游自己 `make kernelrelease`：
#   1. 那要再起一次 kbuild，慢；
#   2. 更要紧的是 krel 会带 -dirty 后缀，取决于**查询那一刻**子模块的工作区状态。
#      本脚本开头 git checkout -- . 再 apply 补丁 —— 编译时是 dirty 的，所以镜像里
#      /lib/modules/<krel> 目录名带 -dirty；下游再查时子模块可能已被清干净，
#      同一条命令吐出另一个值，krel 一致性检查就会假报不匹配。
# 这里写下的是 kbuild 自己生成的文件，不存在算错的可能。
KREL_FILE="${OUT_DIR}/include/config/kernel.release"
if [ -f "${KREL_FILE}" ]; then
    cp -f "${KREL_FILE}" "${OUT_DIR}/.kernelrelease"
    KREL="$(cat "${OUT_DIR}/.kernelrelease")"
    echo "[OK] Kernel release: ${KREL}"
else
    echo "[WARN] ${KREL_FILE} 不存在，未能写下 ${OUT_DIR}/.kernelrelease"
    KREL="unknown"
fi

# ------------------------------------------------------------------------------
# Step 8: kernel-rootfs.tar（给 Void 根文件系统配方用）
# ------------------------------------------------------------------------------
# tools/build/Dockerfile 里有 `ADD ./build/kernel-rootfs.tar /`，它是模块和
# 固件进入设备镜像的**唯一**入口。这里在 host 上打包，而不是在容器里，因为
# build_system.sh 是直接在 host 上跑 `docker buildx build` 的。
#
# 固件为什么必须进这个包：Dockerfile 里的
#   COPY ./kernel/firmware/qcom/sdm845 /lib/firmware/qcom/sdm845
# 只覆盖了 qcom/sdm845 一棵子树。qcom/a630_sqe.fw 和 qcom/a630_gmu.bin
# 在 qcom/ 下、不在 sdm845/ 下，只有这个 tar 能带进来。少它们 GPU 起不来。
#
# 确定性 tar 选项：mtime/owner 归零 + 按名字排序。目的是让**内容相同**的两次
# 构建产出**字节相同**的 tar —— 这样 Docker 的 layer cache 才命中，重编内核
# 之外的小改动不用重跑整个 Void 构建。内容不一致时这里不会帮忙，也没想帮。
ROOTFS_TAR="${BUILD_DIR}/kernel-rootfs.tar"
( cd "${ROOTFS_DIR}" && \
    tar --sort=name \
        --mtime='UTC 1970-01-01' \
        --owner=0 --group=0 --numeric-owner \
        --pax-option='exthdr::=yes,delete=atime,delete=ctime' \
        -cf "${ROOTFS_TAR}" lib/modules lib/firmware )
tar -tf "${ROOTFS_TAR}" | grep -q "^lib/modules/${KREL}/modules.dep$" || {
    echo "[ERROR] ${ROOTFS_TAR} 里没有 lib/modules/${KREL}/modules.dep"
    echo "[ERROR] tar 内容是 ${MODULES_COUNT_HOST} 个 .ko 之外的东西，检查上面几步"
    exit 1
}
echo "[OK] ${ROOTFS_TAR} ($(stat -c %s "${ROOTFS_TAR}") 字节)"

# build_system.sh 用这个字符串传给 Dockerfile 的 KERNEL_RELEASE。
echo "${KREL}" > "${BUILD_DIR}/kernel-release"

# 本次编译用的内核提交。build_system.sh 拿它和**现在**的子模块 HEAD 比对：
# 子模块被更新过而内核没重编时，tar 里的模块是旧内核的，模块照样能 depmod
# 成功（vermagic 里 krel 字符串可能没变），但 insmod 会 EREXEC 或者静默
# 行为不一致。这个比对是唯一能在**设备启动之前**拦住它的东西。
KERNEL_REV="$(git -C "${KERNEL_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "${KERNEL_REV}" > "${BUILD_DIR}/kernel-source-revision"

# 下游契约。改路径前先改这几处：
#   ${BUILD_DIR}/kernel-rootfs.tar   -> tools/build/Dockerfile 的 ADD，build_system.sh 的预检
#   ${BUILD_DIR}/kernel-release      -> build_system.sh 读它，传 --build-arg KERNEL_RELEASE
#   ${BUILD_DIR}/output/${DEVICE}-boot.img -> tools/flash/oneplus6.sh
#   ${ROOTFS_DIR}/lib/modules/${KREL} / lib/firmware -> 本脚本第 8 步打进 tar 的源

SCRIPT_END_TIME=$(date +%s)
ELAPSED_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
MINUTES=$((ELAPSED_TIME / 60))
SECONDS=$((ELAPSED_TIME % 60))

echo ""
echo "=========================================="
echo "内核构建完成"
echo "=========================================="
echo "耗时: ${MINUTES}m ${SECONDS}s"
echo ""
echo "产物:"
echo "  Image.gz   : ${IMAGE_GZ} ($(stat -c %s "${IMAGE_GZ}") 字节)"
echo "  DTB        : ${DTB} ($(stat -c %s "${DTB}") 字节)"
echo "  模块       : ${ROOTFS_DIR}/lib/modules/${KREL} (${MODULES_COUNT_HOST} 个 .ko)"
echo "  kernel-dtb : ${ROOTFS_DIR}/boot-workdir/kernel-dtb"
echo "  固件       : ${ROOTFS_DIR}/lib/firmware (${FIRMWARE_COUNT_HOST} 个文件)"
echo "  krel       : ${OUT_DIR}/.kernelrelease"
echo ""
echo "下一步: ./vamos build boot    （打包 boot.img）"
echo "       或 ./vamos build all   （boot.img + 相机/IMU deb + rootfs + 验证）"
echo "日志: ${LOG_FILE}"
echo ""
echo "ccache 统计:"
sudo docker exec -i "$CONTAINER_ID" ccache -s 2>/dev/null || echo "  ccache 不可用"
