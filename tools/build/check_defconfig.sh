#!/bin/bash
# 校验关键内核开关有没有在重新生成 .config 时被静默关掉 / 丢掉。
#
# 背景: kernel/configs/oneplus6/oneplus6_defconfig 是一份完整的 .config（不是片段）。
# 用一份旧 .config 跑 `make olddefconfig` 重新生成时，只有"符号本身还在"的项会被保留；
# 改名的符号（例如 INPUT_QCOM_SPMI_HAPTICS -> INPUT_QCOM_PMI8998_HAPTICS）会掉回默认 =n，
# 而 olddefconfig 不会报错、构建也不会失败 —— 只是设备上那个功能没了。
# 本脚本按 required_config.conf 逐项断言，作为生成/构建后的兜底检查。
#
# 用法:
#   tools/build/check_defconfig.sh                      # 默认检查 build/out/.config
#   tools/build/check_defconfig.sh /path/to/.config     # 检查指定 .config
#   tools/build/check_defconfig.sh kernel/configs/oneplus6/oneplus6_defconfig
# 退出码: 0 = 全部满足, 1 = 有缺失, 2 = 文件/清单不存在

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONF="${1:-${PROJECT_ROOT}/build/out/.config}"
LIST="${PROJECT_ROOT}/kernel/configs/oneplus6/required_config.conf"

if [ ! -f "${LIST}" ]; then
    echo "[ERROR] 找不到断言清单: ${LIST}"
    exit 2
fi

if [ ! -f "${CONF}" ]; then
    echo "[ERROR] 找不到 .config: ${CONF}"
    echo "        先跑 ./tools/build/build_kernel.sh，或显式传入 .config 路径"
    exit 2
fi

echo "=========================================="
echo "关键内核开关校验"
echo "  .config : ${CONF}"
echo "  清单    : ${LIST}"
echo "=========================================="

total=0
fail_y=0
fail_any=0

while read -r sym want _rest; do
    case "${sym}" in
        ''|'#'*) continue ;;
    esac
    total=$((total + 1))
    val="$(grep -m1 -E "^${sym}=" "${CONF}" 2>/dev/null | cut -d= -f2-)"
    [ -z "${val}" ] && val="n"
    case "${want}" in
        y)
            if [ "${val}" != "y" ]; then
                echo "[FAIL] ${sym} 期望 =y，实际 =${val}"
                fail_y=$((fail_y + 1))
            fi
            ;;
        y\|m)
            case "${val}" in
                y|m) ;;
                *) echo "[FAIL] ${sym} 期望 y|m（至少编成模块），实际 =${val}"
                   fail_any=$((fail_any + 1)) ;;
            esac
            ;;
        *)
            echo "[WARN] 清单项写错了: ${sym} 期望值='${want}'"
            ;;
    esac
done < "${LIST}"

echo "------------------------------------------"
echo "[INFO] 共检查 ${total} 项：必须=y 缺 ${fail_y} 项，必须已编出 缺 ${fail_any} 项"

if [ $((fail_y + fail_any)) -eq 0 ]; then
    echo "[OK] 关键开关齐全"
    exit 0
fi

echo "[ERROR] 关键开关有缺失。多半是重新生成 .config 时起点用错了（旧版本 / 旧符号名）。"
echo "        重新生成时请以当前 tree 的 .config 为起点，并核对改名符号（见 CLAUDE.md）。"
exit 1
