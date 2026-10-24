#!/usr/bin/env python3
"""启动关键路径内置校验 —— 打包 boot.img 前跑。

背景（为什么这个检查值得单独存在）：
    build/initrd 里的 initramfs **没有任何 .ko 文件**，init 脚本用的是 mdev
    而不是 udev，所以 mdev 只会按 hotplug 建 /dev 节点，**不会按 alias 自动
    加载模块**。也就是说：init 脚本 exec switch_root 之前，内核里只有
    CONFIG_XXX=y 的驱动是真正可用的，=m 的一律死。

    一旦 UFS / 时钟 / 调节器这条链上有任何一环是 =m，/dev/sda17 就永远不会
    出现；而 initramfs 的 init 又不检查 mount 返回值，会照样往下 exec
    switch_root 到空目录，init 死掉 → 内核 panic → ABL 两个槽都判失败 →
    直接掉进 fastboot。整个过程没有任何错误信息，只有"卡在 fastboot"。

用法：
    python3 tools/build/check_boot_path.py [配置路径]
    默认核对 build/out/.config（build_kernel.sh 已把它和 defconfig 对齐）。

退出码：0 = 通过；1 = 有必须内置的项不是 =y；2 = 用法/文件错误。
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_CFG = os.path.join(ROOT, "build", "out", ".config")
# 一加6 单独一个打包脚本（工具链参数和 Comma 的三个结构性不同，见脚本头）。
# 两个都列着是为了同时支持 Comma 主板的 build_bootimg.sh —— 只留一个的话，
# 换一个设备构建时这条检查会静默变成空操作，而 root= 写错一个字符的表现
# 就是"卡在 fastboot"，全程零报错。
BOOTIMG_SH_CANDIDATES = [
    os.path.join(ROOT, "tools", "build", "build_bootimg_oneplus6.sh"),
    os.path.join(ROOT, "tools", "build", "build_bootimg.sh"),
]
FSTAB_CANDIDATES = [
    os.path.join(ROOT, "userspace", "root", "etc", "fstab"),
    os.path.join(ROOT, "userspace", "etc", "fstab"),
]

# 必须 =y。顺序即 init 的执行顺序，不是重要性排序。
# 注意：这棵 sdm845-next 树改过很多符号名，名字一律以 oneplus6_defconfig 为准。
MUST_BUILTIN = [
    # initramfs 自身与文件系统
    ("BLK_DEV_INITRD", "initramfs 解压"),
    ("DEVTMPFS", "自动建 /dev 节点"),
    ("DEVTMPFS_MOUNT", "内核启动时自动 mount devtmpfs 到 /dev"),
    ("PROC_FS", "init: mount proc"),
    ("SYSFS", "init: mount sysfs"),
    ("TMPFS", "fstab: /tmp /run"),
    ("CONFIGFS_FS", "init: mount configfs（USB gadget）"),
    ("EXT4_FS", "rootfs 文件系统"),

    # UFS -> /dev/sda
    ("SCSI", "块设备层"),
    ("SCSI_LOWLEVEL", "块设备层"),
    ("SCSI_UFSHCD", "UFS 主机控制器"),
    ("SCSI_UFSHCD_PLATFORM", "UFS 平台总线驱动"),
    ("SCSI_UFS_QCOM", "UFS QCOM 平台驱动"),
    ("SCSI_UFS_CRYPTO", "UFS 加密"),
    ("BLK_DEV_SD", "scsi 块设备 (/dev/sda)"),
    ("PHY_QCOM_QMP_UFS", "UFS PHY"),

    # 时钟控制器（UFS 的 clocks 全来自 &gcc，ref_clk 来自 &rpmhcc）
    ("COMMON_CLK_QCOM", "时钟框架"),
    ("SDM_GCC_845", "GCC 主时钟控制器 (qcom,gcc-sdm845)"),
    ("QCOM_CLK_RPMH", "RPMh 时钟 (qcom,sdm845-rpmh-clk)"),
    ("QCOM_GDSC", "GCC 的电源域"),
    ("SDM_GPUCC_845", "GPU 时钟"),
    ("SDM_DISPCC_845", "显示时钟"),
    ("SDM_CAMCC_845", "相机时钟"),

    # 调节器（UFS 的 vcc-supply、显示/相机/USB 供电）
    ("REGULATOR", "调节器框架"),
    ("REGULATOR_FIXED_VOLTAGE", "regulator-fixed 节点"),
    ("REGULATOR_QCOM_RPMH", "RPMh 调节器 (PM8998/PMI8998)"),
    ("REGULATOR_QCOM_SPMI", "SPMI PMIC 调节器"),
    ("REGULATOR_QCOM_LABIBB", "显示供电"),
    ("REGULATOR_QCOM_REFGEN", "PMIC refgen"),

    # QCOM 平台基础设施
    ("ARCH_QCOM", "SoC 支持"),
    ("QCOM_SCM", "固件接口"),
    ("QCOM_SMEM", "共享内存"),
    ("QCOM_SMP2P", "跨核中断"),
    ("QCOM_SMSM", "SMSM"),
    ("QCOM_RPMH", "RPMh 通信"),
    ("QCOM_RPMHPD", "RPMh 电源域"),
    ("QCOM_CPR", "时钟/电源请求"),
    ("QCOM_LLCC", "LLCC 内存端口"),
    ("QCOM_IRQ_COMBINER", "中断聚合"),
    ("RESET_CONTROLLER", "复位控制器框架"),
    ("REGMAP", "寄存器 map"),

    # SPMI / PMIC
    ("SPMI", "SPMI 总线"),
    ("SPMI_MSM_PMIC_ARB", "PMIC arbiter"),
    ("QCOM_PMIC_GLINK", "PMIC GLINK"),

    # GPIO / pinctrl
    ("GPIOLIB", "GPIO 框架"),
    ("GPIO_GENERIC", "GPIO 通用驱动"),
    ("PINCTRL", "pinctrl 框架"),
    ("PINCTRL_SDM845", "TLMM"),
    ("PINCTRL_QCOM_SPMI_PMIC", "PMIC GPIO"),

    # 串口控制台（唯一的调试出口）
    ("TTY", "tty 框架"),
    ("SERIAL_CORE", "串口框架"),
    ("SERIAL_CORE_CONSOLE", "串口控制台"),
    ("SERIAL_QCOM_GENI", "GENI 串口"),
    ("SERIAL_QCOM_GENI_CONSOLE", "GENI 串口控制台"),
    ("QCOM_GENI_SE", "GENI 串行引擎"),

    # USB 设备端（init 里 configfs gadget）
    ("USB", "USB 框架"),
    ("USB_DWC3", "DWC3 控制器"),
    ("USB_DWC3_QCOM", "DWC3 QCOM 包装"),
    ("USB_CONFIGFS", "configfs gadget"),
    ("USB_COMMON", "USB 公共类"),
    ("PHY_QCOM_QUSB2", "USB 2.0 PHY"),

    # 固件加载（remoteproc / GPU）
    ("FW_LOADER", "固件加载"),
    ("REMOTEPROC", "remoteproc 框架"),
    ("OF", "设备树"),

    # 看门狗 / 重启：这条不在 init 的执行顺序上，而是在 ABL 跳内核那一跳上。
    # =m 时模块还没加载，ABL 若已启动 APSS 看门狗就没人喂 -> SoC 复位 -> 卡在
    # fastboot 且零报错。qcom_defconfig 本来就是 =y。
    ("QCOM_WDT", "APSS 看门狗（watchdog@17980000）"),
    ("POWER_RESET_QCOM_PON", "PM8998 PON，/sys/power/{state,restart} 靠它"),
]

# 不是致命，但落在启动路径上、=m 时开机前完全不可用。只警告。
WARN_BUILTIN = [
    ("RESET_QCOM_PDC",
     "PDC 复位控制器。旧启动日志里 qcom-q6v5-mss 就报过 "
     "'failed to acquire pdc reset'；UFS 不走它（UFS 用 GCC 复位）"),
    ("REGULATOR_QCOM_USB_VBUS", "USB VBUS 调节器"),
]


def read_cfg(path):
    cfg = {}
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            m = re.match(r"^(CONFIG_[A-Z0-9_]+)=(.*)$", ln)
            if m:
                cfg[m.group(1)] = m.group(2)
                continue
            m = re.match(r"^# (CONFIG_[A-Z0-9_]+) is not set$", ln)
            if m:
                cfg[m.group(1)] = "n"
    return cfg


def _first_existing(candidates):
    for p in candidates:
        if os.path.isfile(p):
            return p
    return None


def _read_noncomment(path):
    """只读不带 # 的行：脚本头部注释里也写了 CMDLINE=（回滚示例），会抢先匹配。"""
    txt = "\n".join(l for l in open(path, encoding="utf-8").read().split("\n")
                    if not l.lstrip().startswith("#"))
    return txt


def _default_of(var, txt):
    """解析 VAR="${VAR:-/dev/sda17}" 这类间接引用，取 :- 后面的默认值。

    build_bootimg_oneplus6.sh 的 CMDLINE 里写的是 root=${ROOT_DEV}，
    ROOT_DEV 又是 "${ROOT_DEV:-/dev/sda17}"。不解析的话正则匹配不到 /dev/，
    这条检查会静默退化成空操作。
    """
    m = re.search(r'^%s="\$\{%s:-([^}"]+)\}' % (var, var), txt, re.M)
    return m.group(1) if m else None


def cmd_root_device():
    """从 bootimg 打包脚本的 CMDLINE 里取 root= 的设备名。"""
    sh = _first_existing(BOOTIMG_SH_CANDIDATES)
    if not sh:
        return None, None
    txt = _read_noncomment(sh)
    ms = re.findall(r'^CMDLINE="([^"]+)"', txt, re.M)
    if not ms:
        return os.path.relpath(sh, ROOT), None
    cmdline = ms[-1]
    r = re.search(r"root=(/dev/\S+)", cmdline)
    if r:
        return os.path.relpath(sh, ROOT), r.group(1)
    # root=${ROOT_DEV} 这种间接引用：顺着变量找默认值。
    m = re.search(r"root=(\$\{[A-Z_]+(?::-[^}]*)?\})", cmdline)
    if m:
        var = m.group(1)[2:]
        var = re.sub(r':-.*', '', var).rstrip('}')
        v = _default_of(var, txt)
        if v:
            return os.path.relpath(sh, ROOT), v
    return os.path.relpath(sh, ROOT), None


def fstab_root_device():
    p = _first_existing(FSTAB_CANDIDATES)
    if not p:
        return None, None
    for ln in open(p, encoding="utf-8"):
        ln = ln.split("#", 1)[0].strip()
        if not ln:
            continue
        f = ln.split()
        if len(f) >= 2 and f[1] == "/" and f[0].startswith("/dev/"):
            return os.path.relpath(p, ROOT), f[0]
    return os.path.relpath(p, ROOT), None


def main():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CFG
    if not os.path.isfile(cfg_path):
        print("[ERR] 找不到配置文件: %s" % cfg_path)
        return 2

    cfg = read_cfg(cfg_path)

    print("=" * 78)
    print("启动关键路径内置校验")
    print("  配置: %s" % os.path.relpath(cfg_path, ROOT))
    print("  规则: initramfs 无 .ko 且用 mdev（不按 alias 自动加载模块），")
    print("        所以 switch_root 之前只有 =y 的驱动可用")
    print("=" * 78)

    failed = []
    for sym, why in MUST_BUILTIN:
        v = cfg.get("CONFIG_" + sym)
        if v != "y":
            shown = {"n": "is not set", None: "符号不存在"}.get(v, v)
            failed.append((sym, why, shown))
    print("\n必须内置 %d 项: %s" % (len(MUST_BUILTIN),
                                  "全部 =y" if not failed else "缺 %d 项" % len(failed)))
    for sym, why, shown in failed:
        print("  [FAIL] CONFIG_%-26s = %-12s (%s)" % (sym, shown, why))

    warned = []
    for sym, why in WARN_BUILTIN:
        v = cfg.get("CONFIG_" + sym)
        if v != "y":
            shown = {"n": "is not set", None: "符号不存在"}.get(v, v)
            warned.append((sym, why, shown))
    print("\n开机前不可用但不致命 %d 项:" % len(warned))
    for sym, why, shown in warned:
        print("  [WARN] CONFIG_%-24s = %-12s %s" % (sym, shown, why))

    # root= 一致性：boot.img 的 CMDLINE 与 rootfs 的 fstab 必须指向同一块设备
    # 两边都报路径，好看出"读到的是哪一份"—— 之前只报设备名，读错文件也看不出来。
    cs, c = cmd_root_device()
    fs, f = fstab_root_device()
    print("\nroot= 一致性:")
    print("  CMDLINE(%s, root=%s)" % (cs or "没找到打包脚本", c or "?"))
    print("  fstab  (%s, /=%s)" % (fs or "没找到 fstab", f or "无 / 条目"))
    if c and f and os.path.basename(c) != os.path.basename(f):
        print("  [WARN] 两边设备名不一致。设备名错一个字符，mount 就静默失败，"
              "表现就是卡在 fastboot。")
    elif c and not f:
        # 不报警：oneplus6 的 fstab 是遗留的 Comma 表，rootfs 就在 userdata 上、
        # / 由 cmdline 挂，fstab 里本来就不会有 / 条目。但要说清楚，
        # 不能像以前那样笼统地"跳过"—— 笼统跳过就等于这个检查一直在空转。
        print("  [INFO] fstab 没有 / 条目：本分支根文件系统由 root= 挂载，"
              "fstab 是遗留的 Comma 表（含 /persist /dsp 等本分支不挂的条目）。"
              "因此只有 CMDLINE 一侧可验证：root=%s" % c)
    elif not c or not f:
        print("  [WARN] 读不到 CMDLINE 的 root= 设备名，这条一致性检查无法执行")

    print("\n" + "=" * 78)
    if failed:
        print("[FAIL] %d 项启动关键驱动不是内置 —— 打包出来的 boot.img 会卡在 fastboot"
              % len(failed))
        print("       把这些符号在 oneplus6_defconfig 里改成 =y 后重新生成"
              "（见 CLAUDE.md「内核配置更新方法」），再重建内核。")
        return 1
    print("[OK] 启动关键路径全部内置")
    return 0


if __name__ == "__main__":
    sys.exit(main())
