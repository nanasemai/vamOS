# 让 vamOS 支持一加6 —— 移植分析与执行计划

日期：2026-10-23
范围：`/home/ubuntu/openpilot_oneplus/vamos-nana`（分支 `oneplus-mainline`）
参照：`/home/ubuntu/openpilot_oneplus/ubuntu-sdm845-mainline`（分支 `master-sdm845-next-20251013`，一加6 已完全跑通 Ubuntu + openpilot）
openpilot 侧：`/home/ubuntu/openpilot_oneplus/dragonpilot_nana`（分支 `oneplus6-0.11.1-20251018`，HEAD `2a9fb456`）

本文档只做分析与计划，未改任何代码。所有数字都是实测/实读文件得来的，不是估计。

---

## 0. 一句话结论

**这不是"加一个设备"，而是把Vamos 的硬件平面整体换掉。** 一加6 在Vamos 的仓库里 0% 存在
（全仓库 grep `enchilada|fajita|oneplus|enigma` 命中 0 次），且Vamos 当前内核 pin（Linux 7.2 tag）
**在结构上无法支持一加6 的相机和 IMU** —— 传感器驱动根本不存在于那个版本。

好消息是：
1. 两个仓库的内核是**同一条上游血脉**，Vamos pin 是 ref pin 的**祖先**（快进 16781 个提交）。
2. 一加6 的 DTS **已经在上游**，不用写一行 DTS。
3. ref 里超越上游的内核改动**只有 17 个补丁、13 个文件、~347 行**。
4. openpilot 侧（`dragonpilot_nana`）一加6 集成**已经写完**，缺的只是 OS 侧那层"契约"。
5. 刷写比 Vamos 现有路径简单一个量级：纯 fastboot，不碰 EDL / GPT / ABL。

坏消息是：
1. **initramfs** 是最大的结构性变化（Vamos 无 initramfs，ref 有且无 `.ko`）。
2. **Adreno OpenCL** 依赖一个 Ubuntu 构建的闭源 ICD `.deb`，在 Void 上能否工作**未验证** —— 这是全计划里
   唯一可能推翻方案选择的单点。
3. IMU 链（libssc / hexagonrpc / SLPI）在 Vamos 里**完全没有**，而 IMU 是 openpilot 的 P0
   （无 IMU → `sensorDataInvalid` = PERMANENT + NO_ENTRY，永远进不了 onroad）。

---

## 1. 两个仓库的真实身份

| | **vamos-nana** | **ubuntu-sdm845-mainline**（ref） |
|---|---|---|
| 目标设备 | comma 3X (mici) / comma four (tizi) | OnePlus 6 (enchilada) / 6T (fajita) |
| 发行版 | Void Linux aarch64（`void-aarch64-ROOTFS-20250202.tar.xz`，sha256 固定） | Ubuntu 24.04.4 |
| 服务管理 | **runit**（`etc/runit/{1,2,3}` + `etc/sv/*`） | systemd（11 个 unit） |
| 内核 | `torvalds/linux.git` @ `8d3ae59288f1` = **Linux 7.2 tag** | `nanasemai/sdm845-next.git` @ `e38405d01d1` = **`7.2.0-next-20260820`** |
| 内核 DTS | 仓库内 `kernel/dts/`，4 个 comma 文件，构建时拷进内核树 | 上游自带，零拷贝 |
| 相机栈 | **下游 Spectra**（`kernel/spectra-camera/`，out-of-tree，来自 `cameras-spectra-mainline-andi@391dedc7`） | **上游 mainline `qcom,camss`** + libcamera + v4l2loopback |
| initramfs | **无**（`mkbootimg --ramdisk /dev/null`） | 有（外部仓库 `nanasemai/initrd.git` 分支 `oneplus6-initrd`） |
| 根分区 | `system`（单分区，sparse ext4 + EROFS LZ4HC 双输出） | `userdata`（4.7 GB ext4，`root=/dev/sda17`） |
| 启动镜像 | 20 MB，**VBLE 签名**（`tools/build/vble-qti.key`，Comma ABL 校验） | 19.8 MB，**不签名**（设备原生 ABL 不校验） |
| 刷写 | **EDL/QDL 全程**（`tools/bin/qdl` = `bunx qdl.js`，`05c6:9008`/`3801:9008`） | **纯 fastboot** |
| 固件 | `firmware/*.img` 29 个 Comma 分区镜像（Git LFS） | `kernel/firmware/` 217 MB，一加6 那部分 70 MB |
| 内核配置 | 140 行 fragment 叠 `make defconfig` | **整份 10910 行 defconfig** + 154 行 `required_config.conf` |
| openpilot 身份标记 | `/TICI` + `/AGNOS` → `PC=False` | **`/ONEPLUS6`** → `PC=True` |
| openpilot 服务 | runit `sv/comma` → tmux → `comma.sh` → `/data/continue.sh`（常驻、respawn） | **无监督**，桌面图标手动启动，最后记录状态进程数 0 |
| openpilot 代码来源 | 镜像只装依赖；代码运行时从 `/data/openpilot` 走 `PYTHONPATH` | `git archive` 部署到 `/data/openpilot`（无 `.git`，必须有 `build.json`） |
| GPU 后端 | `CONFIG_DRM_MSM=y`，**无 KGSL**，README 里 `opencl` 是未勾选项 | Mesa OpenCL（`CL` 后端，无 `/dev/kgsl-3d0`）+ 闭源 Adreno ICD |
| openpilot 推理 | 相机走硬件 NV12 DMA-BUF 直达 tinygrad，实测 **29.5 ms**（bench） | **117 ms** 在栈内 / **55.9 ms** 隔离（CL 后端） |
| IMU | **完全没有** | libssc/hexagonrpc 全栈，**101.1 Hz** 实测 |
| 补丁数 | 29 个（编号 0001,0003,0005–0013,0016–0033） | **17 个** |
| 构建 | Docker `vamos-builder`（Alpine + `aarch64-none-elf-gcc` 交叉编译） | Docker（原生 aarch64） |
| CI | `.github/workflows/build.yml`（build-kernel / build-system / release 三 job） | 手工 `./build.sh` |

**关键理解**：Vamos 是一个"为 comma 硬件造的、以 openpilot 为唯一目的的 OS"，ref 是一个
"让开源 Ubuntu 在一加6 手机上跑起来的项目，openpilot 是它的一个应用"。两者对 openpilot 的
定位完全不同 —— Vamos 把 openpilot 当 OS 本体（runit 常驻、无桌面），ref 把 openpilot 当桌面应用。

---

## 2. 内核基线（第一优先级，不可绕过）

### 2.1 现状：两个 pin 是祖先关系

```
vamos pin  8d3ae59288f1  = Linux 7.2 tag（2026-08-16）
ref   pin  e38405d01d11  = 7.2.0-next-20260820（tag: sdm845-next-20260820-17）
关系：      v7.2 IS ancestor of ref pin，中间 16781 个提交
```

已实测：`git merge-base --is-ancestor 8d3ae59288f1 e38405d01d11` → 真。
所以 pin 迁移**不需要 rebase Vamos 自己的 29 个补丁**（它们改的是 comma DTS/驱动，和一加6 无交集）。

### 2.2 为什么必须迁移：v7.2 上结构上做不出来

在 Vamos pin（v7.2）上实测文件存在性：

| 组件 | v7.2（Vamos pin） | ref pin | 后果 |
|---|---|---|---|
| `drivers/media/i2c/imx519.c`（主摄） | **不存在** | 存在 | 主摄无法驱动 |
| `drivers/media/i2c/imx376.c`（超广角） | **不存在** | 存在 | 同上 |
| `drivers/media/i2c/imx371.c`（前置） | **不存在** | 存在 | 同上 |
| `drivers/media/i2c/lc89821x.c`（对焦马达） | **不存在** | 存在 | 对焦无法控制 |
| `arch/arm64/boot/dts/qcom/sdm845-oneplus-*.dts{,i}` | 存在（3 个） | 存在 | DTS 上游已有 ✓ |
| `drivers/media/platform/qcom/camss/camss.c` | 存在 | 存在 | ✓ |
| `drivers/media/platform/qcom/venus/core.c` | 存在 | 存在 | ✓ |

同一份 `sdm845-oneplus-common.dtsi`，两个 pin 的 blob 不同：

| | v7.2 | ref pin | 差值 |
|---|---|---|---|
| `sdm845-oneplus-common.dtsi` | 21818 B | 31882 B | **+528 / −11** |
| `sdm845-oneplus-enchilada.dts` | — | — | **+22** |

v7.2 版本里**完全没有** `&camss { ports }`、没有任何传感器实例、没有 `&q6cvp`/`&q6cvs`/`&q6mvm`
（ADSP/SLPI remoteproc 节点）。而一加6 的 IMU 走的是 SLPI → QMI → QRTR 这条路，**没有 q6c\*
节点就没有 IMU**。

v7.2 的 DTS 缺的具体内容（逐个确认）：

```
imx519  ×3   imx376 ×3   imx371 ×3      ← 三个传感器实例 + 端点
csiphy0 ×2   csiphy1 ×2   csiphy2 ×2     ← CSI-2 路由
q6cvp ×1     q6cvs ×1     q6mvm ×1       ← ADSP/SLPI remoteproc
```

`sdm845-oneplus-enchilada.dts` 那 22 行增量是：`main_cam_ois` 调压器（tlmm 40，2.864 V）+
`&rmi4_f12` 的 `syna,clip-y-high = <2280>` 和 `touchscreen-y-mm = <144>`。

**结论**：在内核 pin 上不做迁移，相机和 IMU 都是结构不可能，不是配置问题。这是硬前置条件。

### 2.3 ref 的内核"脏工作区"是可以复现的

ref 的 `kernel/linux` 工作区是脏的，13 个已修改文件：

```
arch/arm64/boot/dts/qcom/pm8998.dtsi                 +1 / -0
arch/arm64/boot/dts/qcom/sdm845-oneplus-common.dtsi  +42 / -14
arch/arm64/boot/dts/qcom/sdm845-wcd9340.dtsi         +4 / -0
arch/arm64/boot/dts/qcom/sdm845.dtsi                 +12 / -0
drivers/clk/qcom/camcc-sdm845.c                       +42 / -22
drivers/gpu/drm/msm/adreno/a6xx_gmu.c                  +8 / -1
drivers/gpu/drm/msm/adreno/adreno_gpu.c               +35 / -4
drivers/gpu/drm/msm/msm_submitqueue.c                 +17 / -0
drivers/media/i2c/imx519.c                            +28 / -6
drivers/power/supply/qcom_smbx.c                      +74 / -0
drivers/rtc/rtc-pm8xxx.c                              +37 / -10
drivers/video/backlight/qcom-wled.c                   +26 / -10
sound/soc/codecs/wcd934x.c                            +10 / -0
```

**这 13 个文件 = `kernel/patches/` 里 17 个补丁触及的文件集合，完全一一对应。**
即：ref 的"脏工作区"就是那 17 个补丁没提交而已，是可以用补丁集确定复现的。
（另外 540 个 `??` 未跟踪文件是内核树自带的文档/dts 碎片，与项目无关，忽略。）

**已实测验证（2026-10-23）**：把 17 个补丁从 ref 拷到 `kernel/patches/oneplus6/`，
在 pin `e38405d01d1`（tag `sdm845-next-20260820-17`）上取全部 13 个文件的 HEAD 原始版本，
按 `build_kernel.sh` 的 glob 顺序（字典序 = 数字序）逐条 `git apply --check --whitespace=error`
然后 `git apply`，结果 **17/17 应用成功，13/13 文件与 ref 工作区逐字节一致**。
所以内核基线是**可确定复现的**，不需要 rebase、不需要猜测顺序。

注意两个补丁改同一个文件的情况（测试时必须按顺序应用，不能对每个文件重新提取原始版本）：
- `drivers/media/i2c/imx519.c` ← `imx519-min-vblank` 然后 `imx519-preserve-vblank`
- `drivers/rtc/rtc-pm8xxx.c` ← `rtc-pm8xxx-skip-ctrl-rw` 然后 `rtc-pm8xxx-write-unsupported`
- `drivers/gpu/drm/msm/` ← `adreno_opencl` **一个补丁改两个文件**（`adreno_gpu.c` + `msm_submitqueue.c`）
- `arch/arm64/boot/dts/qcom/sdm845-oneplus-common.dtsi` ← 4 个补丁（gpu-gfx-power-domain、
  oneplus_backlight_wled、oneplus_cam_sub_vreg_fix、oneplus_otg_vbus）

`git apply --stat` 确认 17 个补丁 → 13 个文件映射：

```
a6xx-gmu-vote-opp-before-hfi           → adreno/a6xx_gmu.c
adreno_opencl                          → adreno/adreno_gpu.c + msm_submitqueue.c
clk-camcc-sdm845-round-shared-parent   → clk/qcom/camcc-sdm845.c
gpu-gfx-power-domain                   → dts/qcom/sdm845-oneplus-common.dtsi
imx519-min-vblank                      → media/i2c/imx519.c
imx519-preserve-vblank                 → media/i2c/imx519.c
oneplus_audio_mbhc                     → dts/qcom/sdm845-wcd9340.dtsi
oneplus_backlight_wled                 → dts/qcom/sdm845-oneplus-common.dtsi
oneplus_cam_sub_vreg_fix               → dts/qcom/sdm845-oneplus-common.dtsi
oneplus_otg_vbus                       → dts/qcom/sdm845-oneplus-common.dtsi
oneplus_rtc_allow_set_time             → dts/qcom/pm8998.dtsi
qcom-smbx-otg-vbus                     → power/supply/qcom_smbx.c
qcom-wled-ovp-irq-enable-balance       → video/backlight/qcom-wled.c
rtc-pm8xxx-skip-ctrl-rw                → rtc/rtc-pm8xxx.c
rtc-pm8xxx-write-unsupported           → rtc/rtc-pm8xxx.c
wcd934x-capture-mclk                   → sound/soc/codecs/wcd934x.c
```

16 个补丁里，**4 个是一加6 相机正确性的关键**：
- `imx519-preserve-vblank`：保住 `exposure max=3083` / `vblank=2035`。没有它曝光上限降到
  1148 行 / 18.4 ms，夜间不可用。
- `imx519-min-vblank`：`IMX519_MIN_VBLANK=100`，`frame_length = max(frame_length, mode->height + 100)`，
  修画面底部黑带。
- `oneplus_cam_sub_vreg_fix`：副摄子调压器。
- `clk-camcc-sdm845-round-shared-parent-rates`：808 MHz 分数 PLL 四舍五入成 `808000195 Hz`
  会重编程兄弟 RCG，必须改 round 行为。

**3 个是 GPU 稳定性的关键**（缺了会硬重启，不是降速）：
- `gpu-gfx-power-domain`：给 `&gpu` 加 `power-domains = <&rpmhpd SDM845_GFX>`。没有它
  `dev_pm_opp_set_opp()` 无处送 `opp-level`，`gfx.lvl` 停在 bootloader 级别，
  **a630 在 342 MHz 以上不稳定（UVLO 硬重启）**。这就是"GPU 电源域修复"。
- `a6xx-gmu-vote-opp-before-hfi`：先提电压再提时钟。顺序反了会出现"新频率配旧电压"窗口，
  a630 上致命。
- `adreno_opencl`：伪造 `MSM_PARAM_CHIP_ID`（`0x06030000 → 0x06030001`，注入 `revn=1`
  让闭源驱动 XML 表匹配）、`MSM_PARAM_MAX_FREQ=710000000`、**硬编码 `MSM_PARAM_PRIORITIES=2`**
  （注释：*"OpenCL priority adjustment for A630 family. Identify A630 via MSM_PARAM_CHIP_ID
  instead of including adreno_gpu.h"*）。**这个补丁是 CL 后端能跑起来的必要条件之一。**

其余 9 个：`qcom-wled-ovp-irq-enable-balance`（背光过压中断，**当前设备待修 bug**）、
`oneplus_otg_vbus` +
`qcom-smbx-otg-vbus`（OTG VBUS，panda 供电，**已编译未刷写**）、
`rtc-pm8xxx-*` ×3（RTC 写时间，`fix-time-sync` 依赖）、`oneplus_audio_mbhc`、`wcd934x-capture-mclk`。

### 2.4 ref 里有个已废弃的补丁需要知道

ref 当前 `kernel/patches/` **没有** `bt-hci-qca-ext-config.patch`，但设备上刷着的是
`boot.img #30`，**里面还带那个补丁**（它设 `HCI_QUIRK_EXTERNAL_CONFIG` 并在每次 power_on
清掉 public address）。所以当前设备蓝牙**两层都坏**：boot.img 内核层坏 + rootfs 的
`bootmac-bluetooth.service` 被禁用。

两层修复已经构建好了，`build/output/oneplus6-boot.img`（10-22 18:21，19.8 MB）和
`rootfs.img`（10-22 19:41，4.7 GB）都包含，**就差一次刷写**。

对Vamos 的含义：**移植 17 个补丁就够了，不要去找那个已删除的 bt 补丁。**

---

## 3. DTS：一行都不用写

上游已经有一加6 的 DTS，`nanasemai/sdm845-next` pin 上是完整的：

- `sdm845-oneplus-common.dtsi`（31882 B）
- `sdm845-oneplus-enchilada.dts`
- `sdm845-oneplus-fajita.dts`

关键内容（ref pin）：

```dts
model = "OnePlus 6";
compatible = "oneplus,enchilada", "qcom,sdm845";
qcom,board-id = <8 0 17819 22>;

&camss { ports { csiphy0(CPHY 0,1,2) → imx519; csiphy1(DPHY) → imx376k; csiphy2(DPHY) → imx371; } };
&cci_i2c0 { front_cam "sony,imx371" @0x10; rear_cam "sony,imx519" @0x1a (lens-focus → actuator @0x72); };
&cci_i2c1 { sub_cam "sony,imx376k" @0x10 (actuator @0x74); };
&venus { firmware-name = "qcom/sdm845/OnePlus/enchilada/venus.mbn"; };
&q6cvp / &q6cvs / &q6mvm { status = "okay"; };   // ADSP + SLPI，IMU 的前提
```

传感器身份（以 compatible 表为准，设备 i2c 实测 `16-001a=imx519` / `16-0010=imx371` / `17-0010=imx376k`）：

| 角色 | compatible | CSI | CCI |
|---|---|---|---|
| 后置主摄 | `sony,imx519` | csiphy0 | cci_i2c0 |
| **前置** | `sony,imx371` | csiphy2 | cci_i2c0 |
| **超广角** | `sony,imx376k` | csiphy1 | cci_i2c1 |
| 对焦马达 ×2 | `onnn,lc898217xc` @0x72 / @0x74 | | |

> ⚠️ 注意 ref 的 `docs/camera.md` 正文把"IMX376 前置 / IMX371 超广角"写反了，
> 以 compatible 表和 i2c 实测为准。

**这意味着 Vamos 需要做的是减法而不是加法**：删掉 `kernel/dts/sdm845-comma-*` 的 4 个文件
（`common.dtsi` 539 行、`tizi.dts` 185 行、`mici.dts` 179 行、`spectra.dtsi` 1487 行）不再
参与一加6 的构建，也不需要 `install_dts()` 拷贝步骤。comma 设备仍然需要它们，所以建议
**按设备参数化而不是删除**（见 §10）。

一个额外的确认：`qcom,sdm845/OnePlus/enchilada/venus.mbn` 这个固件路径**在 ref pin 的
上游 HEAD 里就已经是那样写的**，说明这个 pin 是真正的上游快照（不是有人手动改过 DTS），
pin 迁移可以放心。

---

## 4. 固件

### 4.1 一加6 需要 70 MB / 16 个文件

`kernel/firmware/qcom/sdm845/OnePlus/enchilada/`：

```
modem.mbn      60346576   (57.6 MiB)
adsp.mbn      11128744   (10.6 MiB)
slpi.mbn       6881468   (6.6 MiB)    ← IMU 走 SLPI，这个必须
wlanmdsp.mbn   3035424   (2.9 MiB)
cdsp.mbn       2831892   (2.7 MiB)
venus.mbn       898156   (877 KiB)    ← 硬件视频编解码
a630_zap.mbn     14256
ipa_fws.mbn      33088
mba.mbn         242400
adspr.jsn / adspua.jsn / cdspr.jsn / modemr.jsn / modemuw.jsn / slpir.jsn / slpius.jsn   ← 7 个 sidecar
```

加上 `qcom/a*_{pfp,pm4,gmu,sqe}*`、`ath10k/WCN3990/hw1.0/*`、`qca/OnePlus/enchilada/crnv21.bin`。

### 4.2 和Vamos 现有的几乎不重叠

| | Vamos `kernel/firmware` | ref `kernel/firmware` |
|---|---|---|
| 文件数 | 19 | 277 |
| 大小 | ~6 MB | 217 MB |
| 重叠 | **只有 6 个文件名**：`ath10k/WCN3990/hw1.0/{board-2.bin,firmware-5.bin,wlanmdsp.mbn}`、`qca/crbtfw21.tlv`、`regulatory.db{,.p7s}` | |
| 内容一致 | `wlanmdsp.mbn` **内容不同**（sha 前16位 `aa7a7b3e` vs `92e15012`） | |

有 4 个文件内容和 Vamos 完全一致（`mba.mbn`、`modemuw.jsn`、`modemr.jsn`、`adspr.jsn` 等 jsn
sidecar），这也解释了 ref 的 `openspec/project.md` 里那句"设备固件（从 vamOS 获取）"。

**结论：固件是全量拷贝，不是重命名。** 70 MB 进 Vamos 的 `kernel/firmware/`。

### 4.3 打包方式：两个地方都要有

ref 的 `build/out/.config`：

```
CONFIG_EXTRA_FIRMWARE="qcom/a630_sqe.fw qcom/a630_gmu.bin qcom/sdm845/OnePlus/enchilada/a630_zap.mbn \
  qcom/sdm845/OnePlus/enchilada/venus.mbn qcom/sdm845/OnePlus/enchilada/ipa_fws.mbn \
  qca/crbtfw21.tlv qca/OnePlus/enchilada/crnv21.bin regulatory.db regulatory.db.p7s \
  ath10k/WCN3990/hw1.0/board-2.bin ath10k/WCN3990/hw1.0/wlanmdsp.mbn"
CONFIG_EXTRA_FIRMWARE_DIR="/lib/firmware"          ← 绝对路径
```

`/lib/firmware` 是**绝对路径** → 这些固件被内嵌进内核镜像（供 initramfs 阶段用）。
同时 `build_kernel.sh` 步骤 `[5/8]` 还会把 `kernel/firmware/*` `cp -r` 进 rootfs 的 `/lib/firmware/`
（供运行期 remoteproc 加载 60 MB 的 `modem.mbn` 等，那些不在 EXTRA_FIRMWARE 里）。

> Vamos 现状用的是 `CONFIG_EXTRA_FIRMWARE_DIR="$DIR/kernel/firmware"`（构建机绝对路径）
> + `firmware_class.path=/lib/firmware/updates`（从 `/system` 读，不是 modem 分区）。
> 一加6 走 ref 的语义：**绝对路径 + rootfs 里也放一份**。

---

## 5. 启动链与 initramfs —— 最大的结构性变化

### 5.1 两个 boot 镜像的构造完全不同

| | Vamos | ref |
|---|---|---|
| ramdisk | **`--ramdisk /dev/null`（空）** | `initrd.cpio.gz`（来自 `nanasemai/initrd.git`） |
| `--base` | `0x80000000` | **`0x00000000`** |
| `--kernel_offset` | `0x8000` | `0x8000` |
| `--ramdisk_offset` | `0x8000` | **`0x01000000`** |
| `--tags_offset` | `0x100` | `0x100` |
| `--pagesize` | 4096 | 4096 |
| `--second_offset` | — | `0x00f00000` |
| kernel | `Image.gz + 2 个 dtb 拼接` | `Image.gz + sdm845-oneplus-enchilada.dtb`（单个） |
| 签名 | **VBLE RSA 签名**（`vble-qti.key`，SHA-256，签名补齐 2048 B 追加到末尾） | **不签名** |
| cmdline | `console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0xA84000 androidboot.hardware=qcom androidboot.console=ttyMSM0 ehci-hcd.park=3 lpm_levels.sleep_disabled=1 service_locator.enable=1 androidboot.selinux=permissive firmware_class.path=/lib/firmware/updates net.ifnames=0` | **`earlyprintk=serial root=/dev/sda17 rootfstype=ext4 rootwait=30 loglevel=7 fbcon=font:16x28 consoleblank=0`** |

ref 的 `build_bootimg.sh`（关键行）：

```sh
CMDLINE="earlyprintk=serial root=/dev/sda17 rootfstype=ext4 rootwait=30 loglevel=7 fbcon=font:16x28 consoleblank=0"
${MKBOOTIMG} --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 --pagesize 4096 --second_offset 0x00f00000 \
  --ramdisk "${BOOT_WORKDIR}/initrd.cpio.gz" --cmdline "${CMDLINE}" \
  --kernel "${KERNEL_DTB}" -o "${BOOT_IMG}"
```

`kernel-dtb = cat Image.gz sdm845-oneplus-enchilada.dtb`，并且**用内容 md5 校验新鲜度**
（明确拒绝用 mtime 判断 —— 注释解释了 mtime 会被误判的原因）。这是个值得直接抄的细节。

### 5.2 ref 的 initramfs 是无 `.ko` 的

`mdev` + 全部启动关键驱动**必须 `=y` 内建**。`check_boot_path.py` 的断言清单就是这件事的
可执行化：

```
BLK_DEV_INITRD, EXT4_FS, SCSI_*, SCSI_UFS_QCOM, BLK_DEV_SD, PHY_QCOM_QMP_UFS
SDM_GCC_845, QCOM_CLK_RPMH, QCOM_GDSC
SDM_GPUCC_845, SDM_DISPCC_845, SDM_CAMCC_845
REGULATOR_QCOM_{RPMH,SPMI,LABIBB,REFGEN}
QCOM_{SCM,SMEM,SMP2P,SMSM,RPMH,RPMHPD,CPR,LLCC,IRQ_COMBINER}
SPMI_MSM_PMIC_ARB, QCOM_PMIC_GLINK, PINCTRL_SDM845
SERIAL_QCOM_GENI(_CONSOLE), USB_DWC3(_QCOM), USB_CONFIGFS, PHY_QCOM_QUSB2
FW_LOADER, REMOTEPROC
QCOM_WDT                        ← 最关键
POWER_RESET_QCOM_PON
```

**失败模式是静默的**（`check_boot_path.py` docstring 原话）：UFS 链里任何一个不是 `=y` →
`/dev/sda17` 永远不出现 → initramfs 的 init 不检查 `mount` 返回值 → `switch_root` 到空目录 →
panic → ABL 两个槽都失败 → 回 fastboot，**全程零报错**。

`QCOM_WDT` 必须是内建的：ABL 在加载内核前就启动了 APSS watchdog，`=m` 的话在内核加载那个
模块之前就会喂不上 → 设备反复重启，看起来就是"卡在 fastboot"。
`RTC_DRV_PM8XXX` 同理必须内建（initramfs 里没有 `.ko`）。

> ⚠️ 这意味着"把 17 个补丁 + 154 行 required_config 抄过来"**不够**。
> 必须拿到 ref 的整份 defconfig（10910 行）作为基线，或者把 `check_boot_path.py`
> 的清单逐条加进 Vamos 的 fragment 并逐个验证 `=y`。
> **强烈推荐前者**：140 行 fragment 叠 `make defconfig` 的组合在这个场景下是错的，
> 因为 defconfig 里大量是 `=m`，而 initramfs 需要 `=y`。

### 5.3 initramfs 是外部依赖

`build_bootimg.sh:85-87`：

```sh
INITRD_URL="https://github.com/nanasemai/initrd.git"
INITRD_BRANCH="${INITRD_BRANCH:-oneplus6-initrd}"
```

它是分支固定的外部仓库，构建时 clone 并跑 `build.sh`，产物是 `initrd.cpio.gz`
（构建产物目录 `build/initrd/` 里已有一份）。`build_bootimg.sh` 会打印 clone 到的 commit
方便复现。

> **建议**：把 `initrd` 仓库作为**第三个 git submodule** 加进 Vamos，而不是构建时联网 clone。
> 理由：`build_bootimg.sh` 只 pin 了分支，分支可能被 force-push；而且 Vamos 的
> `tools/build/Dockerfile.builder` 是离线构建容器，联网 clone 不符合现有模式。

---

## 6. 刷写

### 6.1 ref 的路径极其简单，且不动任何 stock 分区

`flash.sh` 全文逻辑：

```sh
PRODUCT="$(timeout 20 fastboot getvar product 2>&1 | sed -n 's/^product: *//p')"
case "${PRODUCT}" in
  enchilada|fajita) ;;
  sdm845)           ;;        # 一加6 的 ABL 返回 SoC 名而不是设备代号
  *) 拒绝 ;;
esac

fastboot flash boot_a   build/output/oneplus6-boot.img
fastboot flash boot_b   build/output/oneplus6-boot.img
fastboot erase userdata
fastboot flash userdata build/output/rootfs.img
fastboot --disable-verity --disable-verification flash vbmeta_a tools/bin/vbmeta.img
fastboot --disable-verity --disable-verification flash vbmeta_b tools/bin/vbmeta.img
fastboot reboot
```

注释里两点必须保留：

1. **A/B 两个槽都要刷** —— ABL 有 slot failover，只刷当前槽会被 failover 覆盖回去。
2. **`vbmeta` 的 offset 120 处 32 bit big-endian flags**：bit0 = hashtree(dm-verity)，
   bit1 = verification。两个 flag 都要关掉，只关一个等于没关。fastboot 的
   `--disable-verity --disable-verification` 就是在发送前改写这个字段。
   设备实测 ABL 认 `vbmeta_a`/`vbmeta_b`（`getvar: partition-type:vbmeta_a/b = raw`，
   `has-slot:vbmeta = not found`），所以要用槽位名把两个都刷。

**不碰的分区**：ABL、XBL、XBL_CONFIG、modem、tz、hyp、aop、splash、devcfg、devinfo、
storsec、GPT、modemst、persist —— 全部保持 stock。这也意味着**设备随时能刷回官方固件，
零风险**。

### 6.2 和 Vamos 现有路径必须并存，不能替换

Vamos 的刷写是 EDL/QDL 全程：`tools/bin/qdl`（15 行 wrapper，`curl bun.sh/install` 后
`exec bunx --bun andiradulescu/qdl.js`），6 个脚本 `gpt.sh`/`firmware.sh`/`kernel.sh`/`system.sh`
+ `flash all = gpt → firmware → kernel → system`。它需要：
- 29 个 Comma 分区镜像（Git LFS）
- `reboot_edl.c`（`SYS_reboot` + `LINUX_REBOOT_CMD_RESTART2` + `"edl"`）+
  内核补丁 `0013-qcom-support-rebooting-into-edl` + DT 里
  `&{/firmware/scm} { qcom,dload-mode = <&tcsr_dload 0x13000> }`
- udev 规则 `05c6:9008`（Comma/Cintiq）/ `3801:9008`（Qualcomm）

**一加6 上这条链一步都走不通**：OEM 封存的手机通常不允许 AP 请求 EDL；
而且一加6 的分区布局/名字和 Comma 完全不同，`gpt_main_0..5.img` 那 6 个 24576 B 的
GPT 镜像刷上去是破坏性的。

**结论**：
- **不要**为"支持一加6"去改 `tools/flash/gpt.sh`、`firmware.sh`、`tools/bin/qdl`、
  `tools/build/vble-qti.key`。这些是 comma 硬件专用，保持原样。
- 新增 `tools/flash/oneplus6.sh`（照抄 ref 的 `flash.sh`，加上产品名守卫）。
- 新增 `tools/vamos flash oneplus6` 子命令。
- `tools/vamos setup` 里的 EDL udev 规则**继续保留**（comma 设备还需要）。

> 顺带说明：Vamos 的 `tools/flash/` 文件名和内容是错位的 —— `firmware.sh`（526 B）刷的是
> Qualcomm 固件分区（`AB_PARTS="abl aop bluetooth cmnlib cmnlib64 devcfg dsp hyp keymaster
> modem qupfw storsec tz xbl xbl_config"`），`gpt.sh`（207 B）跑的是 `qdl repairgpt`。
> CLI help 是对的，文件名是误导。改一加6 时别按文件名找脚本。

### 6.3 危险动作必须显式提示

`fastboot erase userdata` **会销毁设备上全部数据**。ref 的脚本没有二次确认。
搬进 Vamos 时建议加一个 `--yes-i-know-userdata-is-erased` 参数，或者至少把 erase 单独
拆成一步并打印警告（`vamos flash system` 现在也是这种语义，保持一致）。

---

## 7. 分区与 rootfs

### 7.1 一加6 的 root 在 userdata 上

| | Vamos（comma） | ref（一加6） |
|---|---|---|
| root 分区 | `system`（`/dev/disk/by-partlabel/system`） | `userdata`（`/dev/sda17`） |
| 文件系统 | sparse ext4（6 G）→ 另出 EROFS LZ4HC 只读镜像 | **ext4，4.7 GB，可写** |
| fstab | 8 行：`dsp_a→/dsp`(ro)、`modem_a→/firmware`(vfat,ro)、`persist→/persist`(squashfs,ro)、`userdata→/data`(rw)、`cache→/cache`、`tmpfs /var 128M`、`/tmp 150M`、`/rwtmp 100M` | **3 行**：`/dev/sda17 /`、两个 tmpfs |
| `/system` | 有（ro，EROFS） | **没有** |
| overlayfs | 有（`/home`：lower=`/usr/default/home`，upper=`/rwtmp/home_upper`） | **没有** |
| 设备节点 | `/dev/sda`（`sda2=persist`、`sda11=cache`、`sda12=userdata`）、`/dev/sde*` | `/dev/sda`，`sda17=userdata`，`mmcblk0p13=boot` |
| 扩容 | 无 | **`auto-resize-rootfs.service`** 首次启动自动撑满 userdata 分区 |

ref 的 `userspace/etc/fstab` 只有：

```
/dev/sda17  /       ext4  defaults,noatime,nodiratime
tmpfs       /tmp    tmpfs  defaults,noatime,nodiratime
tmpfs       /run    tmpfs  defaults,noatime,nodiratime
```

**这是两个世界**：Vamos 是"只读根 + 多个专用分区 + overlay"，ref 是"整个根就是 userdata
可写分区，没有 /system，没有 overlay"。

对Vamos 的两种走法：

- **走 ref 的方式**（root 在 userdata）：实现最简单，天然可写、天然可扩容、天然能被
  `fastboot erase`。但放弃了 Vamos 的 EROFS 只读根 + overlay 设计（那是 Vamos 的身份
  的一部分，也是 anti-砖/OTA 回滚的基础）。
- **保留 Vamos 的方式**：把 rootfs 塞进 `cache` 或 `system` 分区。一加6 stock 的 GPT 里
  `cache` 存在，`system` 也存在（Android 的 system 分区，通常较大）。这样 `boot.img`
  的 cmdline 可以是 `root=/dev/disk/by-partlabel/cache rootfstype=ext4`，
  Vamos 现有的 partlabel 机制直接可用，EDL 之外的路径也不用碰。

> **需要实测的一件事**：一加6 stock GPT 里 `cache`/`system` 分区的实际大小。
> rootfs 4.7 GB，如果 `cache` 只有几百 MB 就不够，只能走 userdata。
> 这个数决定了 rootfs 方案，**是 §11 阶段 0 必须拿到的数据**。
> 命令：`fastboot getvar all`（看分区名），`lsblk`（看大小，需要设备已开机）。

---

## 8. userspace：openpilot 的 OS 侧契约

openpilot 在一加6 上要求 OS 提供这些东西。**Vamos 目前一样都没有。**

| 契约 | ref 里怎么满足 | Vamos 现状 |
|---|---|---|
| `/ONEPLUS6` 标记文件 | `rootfs_userspace_container.sh:474` `touch ${ROOTFS_ROOT}/ONEPLUS6` + 立即断言存在 | 有 `/TICI` 和 `/AGNOS`（**反了**） |
| **不**创建 `/TICI`、`/AGNOS` | 同一行注释明写"那两个会把 openpilot 带进 comma 专用分支" | `userspace/base_setup.sh:8-10` 主动 `touch` |
| `/data`、`/data/media/0/realdata`、`/data/params` | `rootfs_userspace_container.sh:457-469`，属主必须是 `ubuntu`，并断言 | 有 `/data`（但那是 userdata 挂载点，不是 openpilot 目录） |
| `libssc.so.0` + `libssc` deb | `userspace/prebuilt/libssc_0.2.2+git4b176d4+onepilot1_arm64.deb` + `userspace/libssc/patches` | **无** |
| `hexagonrpcd` 二进制 + deb | `hexagonrpc_0.5.0+gitda7a374+onepilot1_arm64.deb` + `userspace/hexagonrpc/patches` + `hexagonrpcd-sdsp.service` | **无** |
| 传感器固件 deb | `oneplus6-sensor-firmware_arm64.deb`（含 LSM6DS3 hex 固件） | **无** |
| QRTR / libqrtr / pd-mapper / qrtr-ns | `libqrtr1`、`qrtr`、`pd-mapper` deb | **有 `qrtr-ns`**（但作为 runit 服务，无 python 侧） |
| `libqmi-glib5 1.35.2` | apt（`oneplus6gpsd` 依赖） | **无** |
| `libusb1` | apt + `93-panda.rules` | 有 `pyusb`/`paramiko`（provisioning），无 `libusb1` |
| USB host role 服务 | `oneplus6-usb-role.service`（每 2 s 从 `/etc/oneplus6-usb-role.conf` 纠正 DWC3 role） | **无**（Vamos 的 role 是 DT 里写死的 `dr_mode="host"`） |
| OTG VBUS（给 panda 供电） | 内核补丁 `qcom-smbx-otg-vbus` + `oneplus_otg_vbus`（**已编译未刷写**） | **无** |
| 相机桥接 + 4 条 v4l2loopback | `oneplus6-camera_0.1.0_arm64.deb`（装 `/opt/oneplus6-camera`，含 `oneplus6-camera-bridge`、conf、modprobe.d `video_nr=42,43,44,45`、udev、systemd、wireplumber、gst、snapshot-wrapper） | **无**（Vamos 是 Spectra + request-manager 直连） |
| Adreno OpenCL | `qcom-adreno-cl1_1.838.5~1+repack3-0ubuntu1_arm64.deb` + `qcom-adreno-cl-dev` + `qcom-libdmabufheap_1.1.0+250131` + `qcom-property-vault` + **`/etc/OpenCL/vendors/qcom.icd` 只有一行**（ref 里 49 B，已核实）`/usr/lib/aarch64-linux-gnu/libOpenCL_adreno.so.1` | **无 vendor ICD**（Void 有 `libOpenCL.so.1.0.0` + `libgsl.so` + `opencl-headers`，但 README 里 `opencl` 是未勾选项） |
| `clinfo` | deb 1.838.5 / 3.0.23 | 无 |
| 11 个 systemd unit | 见下 | Vamos 是 runit，需翻译成 `/etc/sv/*` |
| 3 个 udev 规则 | `81-libssc-oneplus-enchilada.rules`、`93-panda.rules`、`99-iio-sensor-proxy-accel.rules` | 有 16 个 udev 规则但全为 comma |
| GPU 频率不封顶 | `oneplus6-optimize.service` → `/usr/local/bin/oneplus6-optimize.sh`：**若 DT 里有 `power-domains` 就不封顶，否则把 `max_freq` 压到 342000000** | **无** |

ref 的 11 个 unit：`auto-resize-rootfs`、`bootmac-bluetooth`、`fix-hardware`、`fix-time-sync`、
`hexagonrpcd-sdsp`、`oneplus6-console`、`oneplus6-firmware-reprobe`、`oneplus6-optimize`、
`oneplus6-usb-role`、`wifi-mac`（+ targets）。**没有 `openpilot.service`** —— openpilot
不在 ref 的镜像里，是独立部署到 `/data/openpilot` 后从桌面图标启动的。

`userspace/etc/systemd/system/` 下**没有** `.wants` 符号链接（启用是在镜像构建时的
`systemctl enable` 里做的，`rootfs_userspace_container.sh:531-533` 有一张
`wants_path:unit` 映射表）。

### 8.1 一个必须先验证的单点：Adreno OpenCL 在 Void 上能不能用

这是全计划里**唯一可能推翻"保留 Vamos 身份"这个方案**的点。

现状：
- ref 的 OpenCL 靠 `qcom-adreno-cl1_1.838.5~1+repack3-0ubuntu1_arm64.deb`
  （Qualcomm 闭源 Adreno ICD，从 Ubuntu 仓库来的），加一个只有一行的
  `/etc/OpenCL/vendors/qcom.icd` 指向 `/usr/lib/aarch64-linux-gnu/libOpenCL_adreno.so.1`。
- Vamos 的 Void rootfs 里 `opencl` 是 README TODO 未勾选项，没有 vendor ICD。

**没有这个 ICD，`Device.get_available_devices()` 就只剩 `['CPU']`，openpilot 完全不能推理。**
（在 ref 上它是 `['CL','CPU']`，CL 是 Mesa 的 ICD loader 派发到闭源 Adreno 的。）

可行的解法（按代价从低到高）：
1. **`dpkg -x` 解包那 16 个 .deb，把文件直接塞进 Void rootfs。** 这些 deb 都是 glibc
   ABI 的 aarch64 包，不需要 Void 的 xbps 包装器。风险是它们链了 Ubuntu 特定版本的
   `libglib-2.0`/`libsystemd` 等，需要用 `ldd` 逐条核对 Void 里的 soname 版本是否满足。
2. 在构建容器里从源码重编（`userspace/libssc/patches`、`userspace/hexagonrpc/patches`
   已经在 ref 里，libssc/hexagonrpc 本身是开源的）。Adreno OpenCL ICD 是闭源的，
   只能走方案 1。
3. 换 Mesa 自带的 Adreno OpenCL 后端（如果这个内核版本可用）。**不确定，需实测。**

> **建议阶段 0 就做一个 1 小时 spike**：起一个 Void aarch64 容器，`dpkg -x` 那 3 个
> OpenCL 相关的 deb，写上 `qcom.icd`，跑 `clinfo`。看到 A630 设备出现 → 方案 A 成立；
> 看不到 → 必须重新评估 rootfs 选择。这个 spike 的结论决定后面所有工作，**别跳过**。

---

## 9. openpilot 侧：`dragonpilot_nana` 已经就绪的部分

分支 `oneplus6-0.11.1-20251018`，HEAD `2a9fb456`，47 个文件提到 `oneplus6`。
设备上跑的是较老的 archive `76306e95`。

### 9.1 已经完成的

- `system/hardware/__init__.py:9-12`：`ONEPLUS6 = os.path.isfile('/ONEPLUS6')`，`PC = not TICI`
- `class OnePlus6(HardwareBase)`：HAL 子类
- 3 个新守护进程：`oneplus6monitord:151`、`oneplus6gpsd:153`、`oneplus6focusd:159`
  （`always_run, enabled=ONEPLUS6, restart_if_crash=True`）
- `timed:113`、`sensord:119` 改为 `enabled=(not PC) or ONEPLUS6`
- 关掉（`not ONEPLUS6`）：`manage_athenad`、`loggerd`、`encoderd`、`stream_encoderd`、
  `proclogd`、`journald`、`micd`、`dmonitoringmodeld`、`dmonitoringd`、`statsd`、
  `feedbackd`、`bridge`、`webrtcd`、`webjoystick`；`_pandad` 硬关；`camerad` 靠 `USE_WEBCAM=1` 关
- `TICI_DOS=1` 链路：`launch_chffrplus.sh:234` → `target_mod = "panda_tici"`
  → `process_config.py:17` `USE_PANDA_TICI = TICI_DOS or ONEPLUS6` → `card.py:19-22`
- 相机配置 `scripts/oneplus6-camera-road.conf`：`[road]`，`camera=/base/soc@0/cci@ac4a000/i2c-bus@0/camera@1a`，
  `loopback=/dev/oneplus6-camera-road`，`resolution=1280x720`，**`focus=192`（用户钦定，不可改）**，
  **`vblank=2035`**，`exposure-mode=long`，`sharpen=0.5`
- `common/transformations/camera.py`：`DEVICE_CAMERAS[("oneplus6","unknown")] = CameraConfig(1280, 720, 1640.0)`
  （f≈1640 对应**中心裁切**；若改成满视野 `capture=2324x1748` 缩放则 f≈900）
- `selfdrive/modeld/SConscript:43-48`：`elif 'CL' in available and os.path.exists('/ONEPLUS6')`
  → `tg_backend='CL'`，`tg_flags='DEV=CL IMAGE=1 FLOAT16=1 JIT_BATCH_SIZE=0 OPENPILOT_HACKS=1'`
- `cereal/log.capnp:186` `oneplus6 @8`、`:526-597` `OnePlus6DeviceStatus @0x9f2e7b41c6d8a350`、
  `:2602` service `@152`；`cereal/services.py:29-30`；`common/params_keys.h:147,168`
- 部署脚本：`scripts/deploy_oneplus6.sh`、`scripts/launch_oneplus6.sh`、
  `scripts/verify_oneplus6_sensors.sh`、`scripts/oneplus6-focus.sh`、
  `tools/recover_black_panda.py`、`tools/oneplus6_thermal_log.py`

### 9.2 openpilot 侧的依赖：`dragonpilot_nana` 的 pyproject

49 个依赖，`requires-python = ">=3.12.3,<3.13"`（和 Vamos 一致 ✓）。
相对 Vamos 的 stub 多出来的关键项：`av`（相机解码）、`libusb1`（libusb 传输）、
`libusb @ git+...commaai/dependencies@release-libusb`、`acados`（**不是 casadi**，
openpilot 已换 acados）、`gcc-arm-none-eabi`（刷 panda 固件用）、`xvfb`。

**注意**：`dragonpilot_nana` 的 pyproject **没有 `[tool.uv.sources]` 段**。
而 Vamos 的 `userspace/uv/pyproject.toml` 靠那段把 6 个 submodule pin 成 git source
（`msgq-ipc`、`tinygrad` 在 `dorapilot/*@liberation-day-7.2`，
`opendbc`/`pandacan`/`rednose`/`teleoprtc` 在 `commaai/*@master`）。
所以 `./vamos sync` 搬过来时需要**手工合并**这两部分。

sensor 栈的 python 侧**不需要** libssc/hexagonrpc 的 python binding ——
IMU 数据走 hexagonrpcd 守护进程 → udev/IIO → `sensord`，GPS 走 libqmi-glib（C 库）。

### 9.3 openpilot 侧的已知约束（不要重新讨论）

- **CL-only 是用户定的**：*"CL 后端是唯一选项，本项目是 CL-only，KGSL 不在选项内"*。
  所以"移植 KGSL 提速"这条路已排除。
- **推理上限**：栈内 **117 ms / ~7 Hz**，隔离 **55.9 ms / 17.9 Hz**。
  慢的根因不是相机也不是配置，是主线内核无 KGSL → tinygrad QCOM 后端打不开 `/dev/kgsl-3d0`
  → 退回 Mesa OpenCL。62 ms 的栈开销差额**仍未定位**（rlog 已排除 dmonitoringmodeld、
  热节流、相机 GPUISP、`_blob_cache` miss）。
- **不要动 thermal**（用户 2026-10-23 确认）。注意 GPU 热区**有** 85/90/110 °C trip
  且已绑 `devfreq-5000000.gpu`；**只有 CPU 热区缺 cooling-map**。
  纯 modeld 压测 GPU 只到 58 °C，之前那个 86-95 °C 是整栈烧出来的。
  14.8 分钟 soak：CPU 峰值 88.3 °C，GPU 64.2 °C，无降频。
- **`encoderd` 已经关了**（`enabled=not ONEPLUS6`）：它走 FFmpeg 软编，
  均值 200.2% / 峰值 522.7% CPU。选 `enabled=` 而不是改 `only_onroad` 是故意的 ——
  保住 `loggerd`（rlog 是 loggerd 写的）。
- **只用主摄**，约束落在 dragonpilot 侧（`launch_oneplus6.sh` 只设 `ROAD_CAM`，
  `tools/webcam/camerad.py:13-15` 用 `WIDE_CAM`/`DRIVER_CAM` 门控）。
  系统相机配置三条链路保持原样（GNOME 相机里 front/wide 都在）。
- **IMU 是 P0**：无 IMU → `sensorDataInvalid` = `PERMANENT + NO_ENTRY + SOFT_DISABLE`。
  B1-B4 代码完成并在 bench 验证过；`inputsOK` 还需要真车的 `liveCalibration`。
- **不要创建 `/persist`**（PC 模式下 Python 和 C++ 的 persist 都解析到同一个
  `~/.comma/persist`）。

### 9.4 运行时契约细节（这些是 openpilot 会崩的点）

- **VisionIPC buffer 必须是 modeld 的对齐 NV12**：`stride=ALIGN(W,128)`，
  `uv_offset=stride*ALIGN(H,32)`，通过 `get_nv12_info()`。packed buffer 会让 modeld
  读错 UV 行。
- **时间戳必须单调且 `0 < eof - sof < 50 ms`**（`test_onroad` 的判据）。
  fork 里用的是 `eof = time.monotonic_ns()`，`sof = eof - 33_000_000`（写死）。
- `camerad.py` 的合成 `sof = eof - 33_000_000`，`"exposureValPercent": 50.0` 硬编码，
  `Ratekeeper(20, None)`。
- 因为 `dmonitoringmodeld` 关了，`modeld.py` 的
  `is_rhd = dp_dev_is_rhd if LITE else sm["driverMonitoringState"].isRHD` 读到的是
  default-False 的消息 —— 对 LHD 中国车是对的，**不要"修"它**。
- `1280x720` 必须编进 `selfdrive/modeld/SConscript` 的 CAMERA_CONFIGS。

---

## 10. 构建系统逐文件改造清单

### 10.1 需要新增的

| 文件 | 来源 | 说明 |
|---|---|---|
| `kernel/patches/*`（17 个） | ref `kernel/patches/` 直接拷 | 命名从 `NNNN-subsys-desc` 改为 ref 的裸 kebab-case，或者统一成 Vamos 风格 |
| `kernel/configs/oneplus6_defconfig` | ref 的整份 defconfig（10910 行） | **必须整份，不能用 fragment 叠 defconfig** |
| `kernel/configs/oneplus6/required_config.conf` | ref 同名（154 行） | 必 `=y` 断言清单 |
| `kernel/firmware/qcom/sdm845/OnePlus/enchilada/`（70 MB） | ref 同名 | 全量拷贝 |
| `kernel/firmware/qcom/a*_{pfp,pm4,gmu,sqe}*` | ref | Adreno GPU |
| `kernel/firmware/ath10k/WCN3990/hw1.0/` | ref（`wlanmdsp.mbn` 内容不同，用 ref 的） | Wi-Fi |
| `kernel/firmware/qca/OnePlus/enchilada/crnv21.bin` | ref | 蓝牙校准 |
| `tools/build/check_boot_path.py` | ref `tools/build/` | initramfs 关键驱动 `=y` 断言 |
| `tools/build/check_defconfig.sh` | ref | required_config 断言 |
| `tools/build/build_bootimg_oneplus6.sh` | 改写自 ref `build_bootimg.sh` | 见 §10.3 |
| `tools/flash/oneplus6.sh` | 改写自 ref `flash.sh` | fastboot 路径 |
| `tools/bin/vbmeta.img` | ref `tools/bin/` | vbmeta 空壳 |
| `userspace/prebuilt/*.deb`（16 个） | ref `userspace/prebuilt/` | 见 §8 |
| `userspace/libssc/patches`、`userspace/hexagonrpc/patches` | ref | 源码构建用 |
| `userspace/etc/OpenCL/vendors/qcom.icd` | 新写，一行 | `/usr/lib/.../libOpenCL_adreno.so.1` |
| `userspace/etc/udev/rules.d/81-libssc-oneplus-enchilada.rules`、`93-panda.rules`、`99-iio-sensor-proxy-accel.rules` | ref | |
| `/etc/sv/{hexagonrpcd,openpilot-usb-role,openpilot-camera-bridge,openpilot,optimize,...}` | 从 ref 的 systemd unit **翻译成 runit** | Vamos 是 runit，不是 systemd |
| `kernel/initrd/`（第三个子模块） | `nanasemai/initrd.git` 分支 `oneplus6-initrd` | 建议 vendor 成 submodule 而非构建时 clone |

### 10.2 需要修改的

| 文件 | 改动 |
|---|---|
| `.gitmodules` | `kernel/linux` 的 url 从 `torvalds/linux.git` 改为 `nanasemai/sdm845-next.git`（分支 `sdm845-next`，pin `e38405d01d1`）；新增 `kernel/initrd` |
| `kernel/linux` submodule pin | `8d3ae59288f1` → `e38405d01d11` |
| `tools/build/build_kernel.sh` | `DTS_FILES`（`:17-21`）按设备参数化；`install_dts()`（`:284-293`）一加6 路径下跳过（DTS 在内核里）；`BASE_DEFCONFIG`（`:14-15`）按设备选整份 defconfig 而非 `defconfig`+fragment；`make Image.gz <dtb> modules` 的 dtb 列表；**跳过** `kernel/spectra-camera` out-of-tree 构建（`:197-219`）；**跳过 VBLE 签名**（`:247-252`，一加6 的 ABL 不校验，且我们没有它的 key）；cmdline（`:239`）按设备选 |
| `tools/build/Dockerfile` | 模块断言（`:86-88`）现在硬查 `spectra_camera mc videodev camcc_sdm845 venus_core venus_enc venus_dec` —— 一加6 上 Spectra 不存在，必须按设备放宽；固件 COPY（`:71-75`）加 OnePlus 目录；runit 服务列表（`:97-110`）加新增服务；加 `.deb` 解包步骤 |
| `tools/build/build_system.sh` | `ROOTFS_IMAGE_SIZE`（`:36`，现在 6 G）；`HOST`（`:125`，现在 `comma`）；EROFS/overlay 逻辑按设备 |
| `tools/build/Dockerfile.builder` | 无需大改（Alpine 工具链通用） |
| `tools/vamos` | 加 `build/boot` 子命令分支（comma 用 `build_kernel.sh`，一加6 用新脚本）；`flash` 加 `oneplus6` 子命令 |
| `userspace/base_setup.sh` | **删掉 `:8-10` 的 `touch /TICI` 和 `touch /AGNOS`，改成 `touch /ONEPLUS6`**（按设备参数化）；`USERNAME`/`PASSWD`（`:4-5`，现在 `comma`）；包列表加 `libqmi-glib5`、`libusb-1.0-0`、`python3-clang` 等 |
| `userspace/uv/pyproject.toml` | 依赖基线从 `dorapilot/openpilot@liberation-day-7.2` 换成 `dragonpilot_nana@oneplus6-0.11.1-20251018`（49 个依赖）+ 保留 Vamos 自己的 `[tool.uv.sources]` 6 个 git pin + 加 `av`/`libusb1`/`acados` |
| `tools/sync/openpilot.sh` | `REPO` 默认值从 `dorapilot/openpilot` 改为 `dragonpilot_nana`；`REF` 默认值改为 `oneplus6-0.11.1-20251018` |
| `userspace/root/etc/fstab` | partlabel 表（`:1-14` 注释里记的是 `sda12=userdata`、`sde4=modem_a`、`sde9=dsp_a`）按一加6 GPT 重写；`dsp_a→/dsp`、`modem_a→/firmware`、`persist→squashfs` 这三条一加6 上没有对应分区（modem 分区保持 stock 不动，`/dsp`/`/persist` 不挂） |
| `userspace/root/etc/runit/1` | **`:53-65` 硬编码 `while [ ! -b /dev/sde4 ] → mount -t vfat -o ro /dev/sde4 /firmware`** —— 一加6 上没有 `sde4`。有界循环（5 s）后 WARN 继续，**不卡启动**，但白等 5 秒且 `/firmware` 挂不上。必须按设备分支或删除 |
| `userspace/root/etc/runit/core-services/` | Vamos 里这个目录**不存在**，但 `etc/runit/1:67` 和 `:138` 引用了它（dangling）。一加6 的启动脚本该放这里 |
| `userspace/root/etc/sv/*` | 一加6 上不需要的：`gpio`（导出 tlmm 30/49/134/41/50/116/124/34/33/32/52，全为 comma 板）、`lte`（Comma C16 `05c6:9330` + Quectel `2c7c:*`）、`adsp`/`cdsp`（改由 remoteproc 自动管理）、`ipa_fws`（改由 firmware class）、`init-qcom`、`irsc_util`（`/etc/sec_config` 在仓库里不存在，实际走 fallback 默认规则）、`ncm-param-watcher`、`avahi-ssh-publish` |
| `userspace/root/etc/udev/rules.d/78-modem.rules` | 设备 ID `05c6:9330`/`2c7c:0125`/`2c7c:6007` 是 Comma/Quectel 手机模组专用 |
| `userspace/root/etc/udev/rules.d/98-panda.rules` | `bbaa:ddee`/`bbaa:ddcc`/`0483:df11` + `spidev MODE=0666`（内部 SPI panda）—— 一加6 是 USB panda，走 `93-panda.rules` |
| `userspace/root/etc/udev/rules.d/90-camera.rules`、`60-persistent-v4l.rules` | Spectra 专用（`cam-req-mgr`、`cam-*`）—— 一加6 走 libcamera + v4l2loopback，不用 |
| `userspace/root/etc/initscripts/qseecomd` | 引用 `/dev/sde20`，一加6 没有 |
| `README.md` | 加一加6 章节 |

### 10.3 新 bootimg 脚本的骨架

```sh
# tools/build/build_bootimg_oneplus6.sh（改写自 ref，保留它的两个好设计：内容 md5 校验 + 分支 commit 打印）
CMDLINE="earlyprintk=serial root=/dev/disk/by-partlabel/<待实测> rootfstype=ext4 rootwait=30 loglevel=7"
cat Image.gz arch/arm64/boot/dts/qcom/sdm845-oneplus-enchilada.dtb > kernel-dtb
${MKBOOTIMG} --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 --pagesize 4096 --second_offset 0x00f00000 \
  --ramdisk initrd.cpio.gz --cmdline "${CMDLINE}" --kernel kernel-dtb -o oneplus6-boot.img
```

三点和 Vamos 现有脚本必须不同：
1. **`--base 0x00000000`**（不是 `0x80000000`），**`--ramdisk_offset 0x01000000`**（不是 `0x8000`）
   —— 一加6 的原生 ABL 按 Android 标准布局解，不是 Comma ABL 的布局。
2. **不签名**。VBLE 签名是 Comma ABL 的校验；一加6 的 ABL 不校验 boot 镜像。
3. **单 dtb**，不是两个。`sdm845-oneplus-enchilada.dtb` 一个；如果同时构建 6T 就出两个镜像。

---

## 11. 分阶段执行计划

### 阶段 0：数据与 spike（1 天，零代码风险）

必须先拿到的数据：

- [ ] **一加6 stock GPT 分区表与大小**：`fastboot getvar all`（分区名），
      开机后 `lsblk` / `cat /proc/partitions`（大小）。
      决定 rootfs 放 `userdata` 还是 `cache`/`system`。
- [ ] **`adb reboot bootloader` 后 `fastboot getvar product` 的返回值**：
      ref 记录的是 `sdm845`（SoC 名，不是设备代号）+ `variant:SDM UFS`。
      确认产品名守卫的匹配条件。
- [ ] **Adreno OpenCL spike（1 小时，决定方案）**：Void aarch64 容器里 `dpkg -x` 那 3 个
      OpenCL deb + 写 `qcom.icd` + 跑 `clinfo`。A630 设备出现 → 方案 A 成立。
- [ ] **`nanasemai/initrd.git` 分支 `oneplus6-initrd` 的可获取性**：能否作为 submodule 引入，
      内容是什么（mdev 规则集、init 脚本、有没有 `.ko`）。
- [ ] **`verify_oneplus6_sensors.sh` 在 ref 设备上跑一遍**，拿到 22 PASS 的当前基线。

**验收**：上面 5 条全部有答案。特别是第 3 条 —— 如果 OpenCL 在 Void 上不可用，
整个"保留 Vamos"的方案要重新评估（见 §13 决策 1）。

### 阶段 1：内核基线迁移（1-2 天）

- [ ] `.gitmodules`：`kernel/linux` url → `nanasemai/sdm845-next.git`，pin `e38405d01d1`
- [ ] `git submodule update --init --depth 1 kernel/linux`
- [ ] 拷 17 个补丁到 `kernel/patches/`，`git apply --check --whitespace=error` 全绿
- [ ] 拷 `required_config.conf`（154 行）
- [ ] 拷整份 defconfig
- [ ] 拷固件 70 MB + Adreno + ath10k + qca
- [ ] 新增 `kernel/initrd` submodule
- [ ] 确认 ref 内核的"脏工作区"= 17 个补丁确定复现（用 `git apply --stat` 逐条核对行数）

**验收**：在干净容器里 `git reset --hard && git clean -fd && 17 补丁全 apply` 成功，
且 `git diff --stat` 出来的 13 个文件 + 行数与 §2.3 的表格逐行一致。

### 阶段 2：内核能编出 boot.img（2-3 天）

- [ ] 改 `build_kernel.sh`：整份 defconfig、跳过 DTS 拷贝、跳过 Spectra、跳过 VBLE
- [ ] `make Image.gz qcom/sdm845-oneplus-enchilada.dtb modules` 成功
- [ ] `check_boot_path.py` + `check_defconfig.sh` 全绿
- [ ] 编 initramfs（`initrd/build.sh`）
- [ ] 拼 `boot.img`（20 MB 左右，和 ref 的 19.8 MB 对得上）
- [ ] **VBLE 不签名**：确认一加6 ABL 能接受未签名的 boot.img（ref 已验证，但要在 Vamos 产物上再验一次）

**验收**：`fastboot flash boot_a boot_b oneplus6-boot.img && fastboot reboot` →
设备进 initramfs，串口/console 能看到 mdev 起、`/dev/sda17` 出现。
**到这一步即使根分区是空的也应该能 boot 到 initramfs shell**（这是验证 UFS 链的最短路径，
不需要先做阶段 4）。

### 阶段 3：刷写工具（0.5 天）

- [ ] `tools/flash/oneplus6.sh`：产品名守卫 `enchilada|fajita|sdm845`，boot_a/boot_b，
      userdata erase（带显式确认参数），userdata flash，vbmeta_a/b 双 flag
- [ ] `tools/vamos flash oneplus6`
- [ ] **保留** `tools/flash/gpt.sh`、`firmware.sh`、`tools/bin/qdl`、`vble-qti.key` 原样（comma 专用）

**验收**：`./vamos flash oneplus6` 能把阶段 2 的产物刷上，设备能进 initramfs。

### 阶段 4：rootfs（2-4 天，取决于阶段 0 的 spike 结果）

- [ ] 决定 root 分区（`userdata` 4.7 G / `cache` / `system`）
- [ ] 加 `.deb` 解包机制到 `Dockerfile`（`dpkg -x` → 目标路径，逐条 `ldd` 校验 soname）
- [ ] `base_setup.sh`：`/TICI`+`/AGNOS` → `/ONEPLUS6`（按设备）；`/data`、`/data/media/0/realdata`、`/data/params`，属主校验
- [ ] `etc/runit/1`：删掉/分支化 `:53-65` 的 `/dev/sde4` 等待（不卡启动，但白等 5 s 且 `/firmware` 挂不上）
- [ ] 服务翻译：ref 的 11 个 systemd unit → `/etc/sv/*`
      （`hexagonrpcd-sdsp`、`oneplus6-usb-role`、`oneplus6-camera-bridge`、`oneplus6-optimize`、
      `oneplus6-firmware-reprobe`、`oneplus6-console`、`auto-resize-rootfs`、
      `fix-hardware`、`fix-time-sync`、`wifi-mac`、`bootmac-bluetooth`）
- [ ] udev：3 条新增 + 关掉 Spectra/comma 专用的那几条
- [ ] OpenCL：`qcom.icd` + `clinfo` 看到 A630

**验收**：`./vamos flash oneplus6` 全量刷 → 进桌面或 runit 登录，
`ls /dev` 里有 `/dev/dri/renderD128`、`/dev/videoN`、`/dev/dma_heap/system`，
`clinfo` 有 A630，`journalctl`（或 `sv status`）无 failed 服务。

### 阶段 5：传感器验证（1-2 天）

- [ ] **IMU**：hexagonrpcd 起 → libssc → 101 Hz，静止时 `|a| ≈ 9.8 m/s²`
      （ref 实测：101.1 Hz，`[−0.12, +0.45, +9.83]`，`verify_oneplus6_sensors.sh` 22 PASS）
- [ ] **相机**：libcamera 驱动 imx519，`oneplus6-camera-bridge` 起，
      `/dev/oneplus6-camera-road` 出 1280×720@20（`vblank=2035`，`focus=192`，`exposure-mode=long`）
- [ ] **GPU**：`oneplus6-optimize` 后 `cur_freq` 到 710 MHz（不是 342 MHz 封顶）
- [ ] **USB role**：`oneplus6-usb-role` 把 DWC3 pin 到 host，`xhci-hcd` 出现 Bus 001/002
- [ ] **GNSS**（可选）：`oneplus6gpsd` QMI LOC v2，`Start result=0`，1 Hz

**验收**：一个 `verify_oneplus6_sensors.sh` 风格的脚本全 PASS。
**IMU 是全阶段的最关键判据** —— 没有 IMU，openpilot 永远不会进 onroad。

### 阶段 6：openpilot（2-3 天）

- [ ] `userspace/uv/pyproject.toml` 切到 `dragonpilot_nana@oneplus6-0.11.1-20251018`
      + 合并 `[tool.uv.sources]`
- [ ] `tools/sync/openpilot.sh` 的 `REPO`/`REF` 默认值
- [ ] 新增 `/etc/sv/openpilot`（runit 监督，翻译自 ref 的桌面启动方式）
      —— 这是Vamos 相对 ref 的**明确优势**：Vamos 的 openpilot 是 runit 常驻 + respawn +
      cgroup 隔离，ref 那边是无监督桌面启动（最后记录状态进程数 0）
- [ ] 环境变量按 ref 的 `launch_oneplus6.sh`：`USE_WEBCAM=1`、`ROAD_CAM=/dev/oneplus6-camera-road`
      （回落 rear）、`ROAD_CAM_FLIP=0`、`TICI_DOS=1`、`SHOW_FPS=1`、`FPS=20`、
      `ONEPLUS6_FAKE_IGNITION=1`、`LOG_ROOT`、`PARAMS_ROOT`、`BIG=1`
- [ ] `PANDAFW_FLASH` **不要**开（外部 panda 默认不刷）

**验收**：
- `manager`、`ui`、`camerad`、`pandad`、`modeld`、`oneplus6monitord`、`oneplus6gpsd`、
  `oneplus6focusd`、`sensord` 全部在运行
- `roadCameraState` **20 Hz**
- 台架上必须写 demo CarParams 才会有推理（无 CAN → `card.py` 永远卡在
  `"Waiting for CAN messages..."` → 不写 CarParams → `modeld` 在
  `params.get("CarParams", block=True)` 里静默阻塞，**`modelV2` 恒为 0**）。
  这是 ref 踩过的坑，判据必须数 `modelV2` 帧数而不是进程数
- `modelV2` 6-8 Hz，`modelExecutionTime` 中位数 107-121 ms（和 ref 一致即正确）

### 阶段 7：真车（单独里程碑）

- [ ] 黑 panda 上 USB-OTG → 枚举 → `pandad_tici`（libusb 传输）→ CAN → fingerprint
- [ ] `liveCalibration` → `inputsOK` → 首次真车介入

**这条在两个仓库里都从未验证过**。`verify_oneplus6_sensors.sh` 只验到 bench 层。

---

## 12. 风险与地雷

### 12.1 会砖的（必须防）

1. **`fastboot erase userdata` 销毁全部数据**。ref 的脚本没有确认。
2. **`firmware/gpt_main_0..5.img` 绝不要刷到一加6**。那 6 个是 Comma 的分区表，
   一加6 的分区布局和名字完全不同。
3. **`firmware/` 里那 29 个 Comma 分区镜像绝不要刷**。`abl.img`/`xbl.img`/`xbl_config.img`/
   `tz.img`/`hyp.img` 是安全签名且按 SKU 绑定的，刷上去设备直接不开机。
4. **A/B 两个槽必须都刷**，ABL 有 slot failover。
5. **vbmeta 两个 flag 都要关**（offset 120 处 bit0 + bit1），只关一个等于没关。
6. **黑 panda 刷写是单向的**：只能构建 DEBUG 固件（`certs/debug` 在，`certs/release` 不在），
   写 DEBUG app 必须和 DEBUG bootstub **成对写**，否则 panda 永远卡在 bootstub。
   且写 DEBUG bootstub 会覆盖出厂 release bootstub，**仓库里没有备份可以刷回来**
   （新 debug bootstub 仍校验 release 签名，所以将来有 release 固件能救回来）。
   手动路径：`tools/recover_black_panda.py --flash SERIAL`。
   **`PANDAFW_FLASH=1` 必须保持注释状态。**

### 12.2 会静默失败的（最难查）

7. **UFS 链任一驱动不是 `=y`** → `/dev/sda*` 不出现 → initramfs 的 init 不检查 mount 返回值 →
   `switch_root` 到空目录 → panic → 两个槽都失败 → fastboot，**零报错**。
   `check_boot_path.py` 就是防这个的，必须真跑。
8. **`QCOM_WDT = m`** → ABL 启动的 APSS watchdog 喂不上 → 反复重启，看起来像卡在 fastboot。
9. **`RTC_DRV_PM8XXX = m`** → initramfs 无 `.ko` → RTC 起不来 → 时间同步链条断。
10. **`etc/runit/1:53-65` 的 `/dev/sde4` 等待** → 一加6 上没有 `sde4`（那是 Comma 的
    `modem_a` vfat 分区）。循环**有界**：`:57` `while [ ! -b /dev/sde4 ] && [ $n -lt 50 ]`
    × `sleep 0.1` = 最多 **5 秒**，之后 `:64` 打 WARN 继续，**不会卡住启动**。
    真实代价是两条：每次开机白等 5 秒；`/firmware` 永远挂不上 → `:54` 注释里依赖的
    `/lib/firmware/updates -> /firmware/image` 符号链接悬空。一加6 不走
    `firmware_class.path=/lib/firmware/updates`（走 rootfs 里的 `/lib/firmware`，见 §4.3），
    所以功能上不致命，但必须按设备分支掉。
11. **`etc/runit/core-services/` 在 Vamos 里不存在**，但 `etc/runit/1:67` 和 `:138` 引用了它
    （dangling）。一加6 的启动脚本该放这里，否则 `:138` 那步是空转。
12. **`/TICI` 残留** → `PC=False` → `common/realtime.py` 调 `sched_setscheduler(SCHED_FIFO)`
    而无 `RLIMIT_RTPRIO` → `PermissionError` → `ui` 无限重启。
    所以 `base_setup.sh:8-10` 的 `touch /TICI` 必须删。
13. **`/data/openpilot` 没有 `build.json` 也没有 `.git`** →
    `system/version.py:get_build_metadata()` 抛 "invalid build metadata" → manager 静默退出。
    桌面症状是"点图标没反应"。
14. **无 CAN 时 `modelV2` 恒为 0** → 很容易误判为"设备跑起来了"。
    判据必须数 `modelV2` 帧数。
15. **`XAUTHORITY` 不能写死**：mutter 每个 session 重新生成
    （`~/.config/mutter/.mutter-Xwaylandauth.*`）。如果走 X11 桌面必须动态取最新的。
16. **USB role 的 `dwc3_set_mode()` 是排队执行的**，回读必须轮询最多 2 秒。
    不要"简化"成一次读。`oneplus6-usb-role.service` 每 2 秒从 conf 纠正一次，不能省。
17. **`v4l2loopback` 的 `video_nr=42,43,44,45` 只在 modprobe 时生效**，就地升级后
    必须重启或 `rmmod`+`modprobe` 才会有第 4 个节点。
18. **只有传感器能同时出一路**：libcamera 的 `MediaDevice::lock()` 是 **进程粒度** 的
    `fcntl` 字节锁（两个 bridge → `EBUSY` "Pipeline handler in use by another process"）；
    一个 bridge 带三个相机也不行（`simple` 的 `configure()` 会重建整个 media pipeline，
    废掉第一个相机的 request）。**解法是单一 bridge 守护进程持有所有 loopback，
    空闲时写黑帧，按 v4l2loopback 客户端使用事件切传感器。**
19. **`libcamera-qcom` 不需要**：libcamera 内置的 `simple` pipeline handler
    原生支持 `qcom-camss`（`simple.cpp:258-268`）。别去装 qcom 那套。
20. **输出是 YUYV 不是 MJPG**（`keep_format=1`）。OpenCV/`av` 解码没问题，
    但期待 MJPG 的会议软件会花屏。
21. **`carState`/`CarParams` 只能来自真实 CAN fingerprinting**，台架无法介入，
    bench 无法介入。`ONEPLUS6_FAKE_IGNITION=1` 只假点火。

### 12.3 用户已明确的约束（不要违反）

22. **CL-only**，KGSL 不在选项内（用户定）。
23. **`focus=192` 不可改**（用户 2026-10-22 视觉选定，DAC 0 位于机械限位
    超出无穷远处，30 m 处锐度只有峰值 30-37%；统计峰值 256-272）。
24. **不要动 thermal**（用户 2026-10-23 确认）。注意 `oneplus_cpu_thermal_cooling.patch`
    是"给 CPU 热区接上 cooling-map"的**修复**，不是调阈值 —— 但**它确实会让 CPU 在 90 °C
    开始节流**。**已按此决定删除该补丁**（2026-10-24），见 §15.4。
    后果：`cpu0-thermal`/`cpu4-thermal` 的 trips（`cpu0_alert0`/`cpu4_alert0` @ 90000 m°C）
    仍然存在，`thermal_zone` 会触发事件，但没有 `cooling-maps` 绑定到任何 cooling device，
    所以**框架不会主动降频**。如果以后要接回去，只需要把补丁加回来。
25. **`echo stop` 到 `4080000.remoteproc` 会炸**。
26. **不要创建 `/persist`**（PC 模式下 Python 和 C++ 的 persist 都解析到 `~/.comma/persist`）。
27. **不要装 `meson`/`ninja-build`**（ref 明确警告）。

### 12.4 结构性上限（别去优化）

28. **无 KGSL → tinygrad 退回 Mesa OpenCL → 栈内 ~117 ms / 7 Hz**。
    隔离测 55.9 ms / 17.9 Hz，62 ms 差额未定位（rlog 已排除 dmonitoringmodeld、
    热节流、相机 GPUISP、`_blob_cache` miss）。**CPU 侧没有优化空间**
    （modeld 只占 7.9% CPU，整机 56%）。
29. **相机路径有完整 CPU 软件开销**：IMX519 → libcamera softisp → YUYV loopback →
    OpenCV/PyAV 解码 → CPU BGR→NV12 repack → VisionIPC → tinygrad CL。
    对比 Vamos 现有 Spectra 路径（硬件 NV12 DMA-BUF 直达，29.5 ms bench）差 4 倍。
    **这条无法在不引入 Spectra 的情况下改善**，而引入 Spectra 就等于放弃主线 CAMSS。
30. **没有 HDR**（IMX519 线性 10-bit 单曝光，vs comma C3X 的 OX03C10），
    软件 ISP 无 LSC/降噪/锐化。结论是"能跑、可用的 ADAS 相机"，不是量产对等。
31. **电池计已放弃**：`bq27411` 是死的（`temp=-2731`、`voltage_now=0`、`capacity=65520`）。
    只能暴露充电器 + RRADC 值，`batteryPercentValid=false`。
32. **OTG VBUS 未验证**：`qcom-smbx-otg-vbus` + `oneplus_otg_vbus` 只在构建容器里编译过，
    `strings` dtb 确认符号在，**没刷过**。寄存器语义只有下游源码（LineageOS
    `OTG_BASE 0x1100`、`CMD_OTG_REG = 0x1140`、`OTG_EN_BIT = BIT(0)`、`OTG_STATUS 0x1109`）
    佐证，SPMI 写可能像 RTC 那次一样被 arbiter 拒；OTG 电流限制未知；回灌 VBUS 无过流保护。
    注意：**data-host 模式不需要这些补丁**（DT 里 `data-role="dual"` + DWC3
    `allow_userspace_control=true` 就能绕过 tcpm），只有**给无源配件供电**才需要。

---

### 12.5 构建/OTA 侧的 Comma 焊接点（二轮排查新增）

前 12.1–12.4 侧重内核与设备侧。这些是**构建工具和交付管线**里的焊接点，同样会让"支持一加6"
悄悄做不干净：

33. **`package_ota.py` 的分区表是硬编码的 Comma 名字**。`:22-27` 六个 `GPT(lun, 'gpt_main_0..5')`，
    `:32-55` 二十五个 `Partition(...)` —— `persist / systemrw / cache / devinfo / limits / logfs /
    splash / xbl / xbl_config / abl / aop / bluetooth / cmnlib64 / cmnlib / devcfg / dsp / hyp /
    keymaster / modem / qupfw / storsec / tz / boot / system`，其中 `system` 指向
    `build/system.erofs.img`。一加6 stock GPT 一个名字都对不上。**要么按设备出两套 manifest，
    要么明确"一加6 不产出 OTA"**（推荐后者：一加6 走 fastboot 全量刷，不需要 OTA 回滚）。
34. **两种 OTA 格式并存，用的是不同的 system 镜像**。`package_ota.py` 打
    `build/system.erofs.img`（EROFS），`package_update.py:8-9` 打
    `build/tmp-system/system.img`（**未 sparse 的 ext4**）。`upload_update.py:19-29` 只接受
    恰好 `boot`+`system` 两项、且 URL 必须是
    `https://github.com/{repo}/releases/download/{tag}/{name}.img.xz`。
    CI **从不跑** `package_update.py`/`upload_update.py` —— 那条路径纯手工。
35. **`abctl` 硬编码 Comma 的 UFS LUN 拓扑**：`userspace/root/usr/bin/abctl:36`
    `AB_DEVICES = ['/dev/sda', '/dev/sde']`、`:39-40` `BOOT_LUN_A=1` / `BOOT_LUN_B=2`、
    `:133` `open('/dev/sde','rb')`、`:234` 找 `/dev/sdb`（注释："XBL boot LUN"）。
    一加6 的 LUN 分布完全不同（boot 在 `mmcblk0p13`）。
    `comma.sh` 每次循环都调 `sudo abctl --set_success` —— **一加6 上这一步会失败**。
    如果 `sv/comma` 被 `/etc/sv/openpilot` 取代（见 §13 决策 4），这条自然消失。
36. **44 个启用的 runit 服务里 8 个在仓库里没有 `/etc/sv` 目录**：`qrtr-ns`、`tqftpserv`、
    `pd-mapper`、`rsyslogd`、`nftables`、`cnss_daemon`、`polkitd`、`sshd`。
    前几个来自 xbps 包，`sshd` 的 `run` 由 `Dockerfile:199-208` 现场生成。
    **`cnss_daemon` 和 `polkitd` 在 `base_setup.sh` 的 88 个包里找不到**（grep 只命中
    `avahi`/`dbus-devel`/`dhcpcd`），可能是传递依赖 —— 一加6 上没有 cnss-daemon 的意义
    （modem 保持 stock），`polkitd` 也没有（无桌面）。**按设备裁剪服务时这两条最该先删**。
37. **`runsvdir` 的 `runsvdir/2` 对悬空符号链接是硬失败**。`etc/runit/2` 把
    `/etc/runit/runsvdir/default/*` 的每个符号链接 `cp -a` 到 `/run/runit/service/<name>`。
    加一个指向不存在目录的 `ln -sf` 会让服务发现直接挂，不是跳过。
38. **`androidboot.serialno` 从来没有被写入 cmdline**。`build_kernel.sh` 的 `mkbootimg
    --cmdline` 里没有它，但 `usr/comma/get-serial.sh` 靠
    `sed -n 's/.*androidboot.serialno=\([^ ]*\).*/\1/p'` 提取，被
    `set-hostname.sh`（主机名 `comma-<serial>`）和 `set_ncm.sh`（gadget product 串）使用。
    目前这两处大概率产出空串。一加6 要接 USB gadget 的话得先补这个。
39. **`kernel/venus-enable/` 是死代码**。全仓库 grep `venus-enable|venus_enable`
    在 `tools/`、`userspace/`、`kernel/patches/` 里命中 0 次，没有任何构建脚本引用它。
    它自己的 README 就说已废弃（"new tizi device trees in this branch already enable the node"）。
    搬的时候**不用管它**，但别误以为是构建的一部分。
40. **`tools/bin/qdl` 在刷写时刻联网拉取第三方代码**：`curl -fsSL https://bun.sh/install | bash`
    后 `exec bunx --bun andiradulescu/qdl.js "$@"`。**未 pin 的第三方代码进了写路径**。
    一加6 不走这条，但 comma 路径上这是个供应链暴露面，值得单独处理。
41. **`kernel/spectra-camera` 不依赖任何 config 符号**。它用 `Kbuild`（`obj-m += spectra_camera.o`）
    而不是 `Makefile`，所以外部 `make M=…` 是无条件构建的。仓库里
    `CONFIG_SPECTRA_CAMERA` 根本不存在也不影响构建 —— 目录里的 `Makefile`/`Kconfig` 是残留。
    （顺带修正一个假设：不是"配置漏了"，是本来就不需要。）
42. **`Dockerfile:80-89` 的模块 ABI 硬门**要求
    `test -s /usr/include/media/cam_req_mgr.h` 且 `spectra_camera mc videodev camcc_sdm845
    venus_core venus_enc venus_dec` 六个模块的 `vermagic` 全部匹配，否则 `exit 1`。
    一加6 路径下 **Spectra 那四个模块不存在**，这条断言必须按设备放宽（不只是删掉 Spectra 构建）。
43. **`README.md` 的 Kernel Patches 章节是错的**：它写的 `defconfig|dts|driver|core` 子系统
    分类法和实际文件名完全不符（实际前缀是 `drm-panel`、`input-edt-ft5x06`、`wifi-ath10k`、
    `media-venus`、`ASoC-sdm845`、`clk-qcom-dispcc-sdm845`）。README 的 Usage 也没写
    `flash firmware`/`flash gpt`/`sync`。补一加6 章节时顺手修正。

## 13. 需要你拍板的决策

### 决策 1（最重要）：rootfs 走哪条路

| | 方案 A：保留 Vamos（Void + runit + EROFS/overlay） | 方案 B：采用 ref 的 Ubuntu 24.04 ext4 | 方案 C：一加6 走 userdata 单分区 |
|---|---|---|---|
| 身份 | **是Vamos** | 变成 Ubuntu 项目 | Vamos 的一个 profile |
| 工作量 | 高（16 个 .deb 解包 + soname 核对 + 11 个 unit 翻译成 runit + OpenCL ICD 未验证） | 低（`userspace/` 整棵搬过来） | 中 |
| 风险 | **OpenCL ICD 可能在 Void 上不可用**（决定成败的单点） | 丢掉 Void/EROFS/overlay/CI/OTA，两个 rootfs 栈并存 | 放弃只读根 + OTA 回滚，但最简单 |
| 刷写 | 同右 | 同右 | `fastboot erase userdata` 语义最简单，和 ref 一致 |
| openpilot 模型 | 镜像装依赖 + `/data/openpilot` 走 PYTHONPATH（comma 的原生模型） | `git archive` + `build.json` | 同右 |

**我的推荐**：先做阶段 0 的 OpenCL spike。
- spike 通过 → **方案 A**（保留Vamos 身份 + `.deb` 解包 overlay 机制）。
  理由：openpilot 本来就是Vamos 的存在目的，runit 常驻监督比 ref 的桌面手动启动好得多
  （ref 那边最后一次记录是进程数 0）。
- spike 不通过 → **方案 C**（放弃 EROFS/overlay，root 直接放 `userdata`，
  用 ref 的 rootfs 作为起点，把Vamos 的构建工具留作 comma 专用）。
  代价是最小的：等于接受"一加6 上跑的就是 Ubuntu"。

**无论选哪条，都要做的**：`base_setup.sh` 的 `/TICI`+`/AGNOS` → `/ONEPLUS6` 参数化、
`etc/runit/1` 的 `sde4` 等待分支化、`etc/sv/*` 按设备裁剪。

### 决策 2：enchilada 还是也构建 fajita

推荐**都构建**。6T 的 DTS 只差 `sdm845-oneplus-fajita.dts` 一个文件，
`flash.sh` 的产品名守卫已经写了 `enchilada|fajita`。成本是每轮多编一个 dtb，
收益是多一台可用设备。但**先只刷 enchilada 验证**。

### 决策 3：黑 panda / 介入，本期做不做

推荐：**本期只做 USB-role 服务 + `pandad_tici` 接线**（便宜，~3 个文件），
把黑 panda 真机验证立为**单独里程碑**。理由：
- panda 枚举 → CAN → fingerprint → 点火，**在两个仓库里从未端到端验证过**；
- 刷写是单向砖的（§12.1-6）；
- `harnessStatus` 只有 comma 风格的 SBU 线束才报 normal/flipped，
  普通直通 OBD 线束会一直 `notConnected` —— 这会**静默地把假点火修复退化回原 bug**。
  这个前置条件需要实测才能确认。

### 决策 4：openpilot 的启动模型

推荐：**加 `/etc/sv/openpilot`（runit 监督）**，不沿用 ref 的桌面图标手动启动。
Vamos 的 `sv/comma` → tmux → `comma.sh` → `/data/continue.sh` 已经是成熟的常驻模型，
而且带 cgroup 隔离（`power_drop_monitor` 可以一次杀整棵进程树）。
这是Vamos 相对 ref 的净优势，不要丢掉。

（ref 的 desktop icon 路径需要 `XAUTHORITY` 动态取 mutter 的最新文件、
`DBUS_SESSION_BUS_ADDRESS`、`DISPLAY=:0`，而且启动前会检查
`oneplus6-camera-bridge.service` 是否 failed/inactive/启动不足 20 秒 —— 这些在 runit 模型下
全部简化为依赖检查。）

### 决策 5：`oneplus_cpu_thermal_cooling.patch` 要不要

它会让 CPU 在 90 °C 开始节流（接上 `cooling-maps` → `cpufreq-cpu0`/`cpufreq-cpu4`）。
你 2026-10-23 说过不要动 thermal。

两个事实供参考：
- 纯 modeld 压测 170 秒 GPU 只到 58 °C，14.8 分钟 soak CPU 峰值 88.3 °C **且没有降频**
  —— 因为 CPU 热区现在没有 cooling-map。加了这个补丁，88 °C 就会开始降频。
- GPU 热区**本来就有** 85/90/110 °C trip 且绑了 `devfreq-5000000.gpu`，不受影响。

**推荐**：先**不带**这个补丁（尊重 thermal 不改动），并在文档里记一条
"CPU 无热节流，长时间运行温度上限自负"。要恢复时只需补这一条。

---

## 14. 工作量估算

| 阶段 | 内容 | 预估 | 阻塞关系 |
|---|---|---|---|
| 0 | 数据 + OpenCL spike | 1 天 | 无 |
| 1 | 内核基线迁移 | 1-2 天 | 无 |
| 2 | 编出 boot.img | 2-3 天 | 阶段 1 |
| 3 | 刷写工具 | 0.5 天 | 阶段 2 |
| 4 | rootfs | 2-4 天 | 阶段 0（spike） |
| 5 | 传感器验证 | 1-2 天 | 阶段 4 |
| 6 | openpilot | 2-3 天 | 阶段 5 |
| 7 | 真车介入 | 独立里程碑 | 阶段 6 + 有黑 panda |

**阶段 0-6 合计约 2-3 周**（单人不并行）。阶段 0 的 spike 是唯一可能改变方案的选择点。

---

## 附录 A：ref 侧的实测数据基线（阶段 5/6 的对比基准）

- `verify_oneplus6_sensors.sh`：**22 PASS / 0 FAIL / 0 WARN**
- IMU：**101.1 Hz**（608 samples / 6.01 s），静止重力 `[−0.12, +0.45, +9.83]`
- 路面通道首帧：72-79 ms
- `vblank`：100 → **2035**；曝光 `min=20 max=3083`
- 相机三路各验 5/5 轮：rear imx519→csiphy0/csid1/vfe1；front imx371→csiphy2/csid0/vfe0；
  wide imx376k→csiphy1/csid2/vfe2
- `roadCameraState` **20 Hz**；`modelV2` 6.5-7 Hz；`modelExecutionTime` 中位 117-121 ms、p90 140 ms
- 隔离测：`run_policy` 空闲 48.5 ms / 20.6 Hz；完整 `ModelState.run()` **55.9 ms / 17.9 Hz**
  （`from_blob`×4 + numpy 2.8 ms、`warp_enqueue` 2.5 ms、**`run_policy` 45.7 ms = 90%**、D2H+parser 1.5 ms）
- `Device.get_available_devices()` → `['CL', 'CPU']`；`tg_input_devices.json` 里
  `WARP_DEV`/`QUEUE_DEV = CL`
- GPU `cur_freq` 710 MHz（最高档），devfreq `5000000.gpu` 范围 257-710 MHz，`simple_ondemand`
- CPU：`schedutil`，`scaling_min_freq=307200`
- `encoderd` 关闭后 CPU 全场最大消费者消失（原 200.2% 均值 / 522.7% 峰值）
- `modeld` 7.9% CPU；整机 CPU 合计 ~450% / 8 核 ≈ 56%，未饱和
- 14.8 分钟 soak：CPU 峰值 88.3 °C，GPU 峰值 64.2 °C，无降频
- 产物：`build/output/oneplus6-boot.img` 20815872 B（19.8 MiB）、`rootfs.img` 5013508096 B（4.68 GiB）

## 附录 B：ref 里已经构建好、待刷写的两个修复

1. `kernel/patches/qcom-wled-ovp-irq-enable-balance.patch`（背光过压中断）
2. 蓝牙 public address 修复（配合 `bootmac-bluetooth.service` 启用）

`build/output/oneplus6-boot.img`（10-22 18:21）+ `rootfs.img`（10-22 19:41）都包含。
**当前设备蓝牙两层都坏**：boot.img #30 还带已删除的 `bt-hci-qca-ext-config.patch`
（设 `HCI_QUIRK_EXTERNAL_CONFIG`，每次 power_on 清 public addr），
rootfs 侧 `bootmac-bluetooth.service` 被禁用。

注意 ref 里还有一条设备固件的待办：**`openspec/project.md` 写"设备固件（从 vamOS 获取）"**，
也就是说 ref 的一加6 固件层本身就部分来自Vamos。搬固件时确认没有版本倒退。

---

# 15. 落地记录（2026-10-23 实际改了什么）

前 14 章是分析。这一章记录**已经改进仓库的**，以及分析阶段被实际执行推翻的几条结论。

## 15.1 已落地

| 项 | 状态 |
|---|---|
| `kernel/linux` 子模组 pin | `8d3ae59` → **`e38405d01d118861776181aaffa1f2ae6ae28b92`** (`sdm845-next-20260820-17`) |
| `kernel/initrd` 子模组 | **新增**，pin `e5a5ec24f30670d7dde6e820bbf3bb139adf66eb` (`oneplus6-initrd`) |
| `.gitmodules` | URL 换 `nanasemai/sdm845-next.git` + `branch = sdm845-next`；新增 initrd 段 |
| `kernel/configs/oneplus6/` | `oneplus6_defconfig`(10910 行) + `required_config.conf` + 3 篇 md |
| `kernel/patches/oneplus6/` | 16 个补丁（`oneplus_cpu_thermal_cooling` 已按决策删除） |
| `kernel/firmware/qcom/sdm845/OnePlus/enchilada/` | 16 文件 70 MB |
| `kernel/firmware/qca/OnePlus/enchilada/` | `crnv21.bin` |
| `kernel/firmware/{qcom/a630_sqe.fw, qcom/a630_gmu.bin, qca/crbtfw21.tlv, ath10k/...}` | 已补齐，`CONFIG_EXTRA_FIRMWARE` 11 项全部命中 |
| `tools/build/build_kernel_oneplus6.sh` | 新增 |
| `tools/build/build_bootimg_oneplus6.sh` | 新增 |
| `tools/build/{check_boot_path.py,check_defconfig.sh}` | 从 ref 拷入 |
| `tools/bin/vbmeta.img` | 从 ref 拷入 |
| `tools/flash/oneplus6.sh` | 新增（纯 fastboot） |
| `tools/vamos` | 只剩 oneplus6 分支，EDL 分支已删 |
| `tools/build/Dockerfile` | 模块 ABI 门禁按上游 camss 重写 |
| `docs/oneplus6-retarget-plan-2026-10-23.md` | 本文件 |

**删除**（`git rm`，已进 index，512 文件 / -132213 行）：
`kernel/dts/`(4)、`kernel/spectra-camera/`(374)、`kernel/venus-enable/`(4)、
`kernel/configs/vamos.config`、`kernel/patches/*.patch`(29)、
`firmware/`(29 张 Comma EDL 镜像)、
`tools/flash/{gpt,firmware,kernel,system}.sh`、`tools/bin/qdl`、
`tools/build/{build_kernel.sh,vble-qti.key}`、
Comma 固件 blob 19 个（`samsung_touch.img`、`qcom/sdm845/{mba,modem_nm}.mbn`、
7 个 `.jsn`、`ath10k/WCN3990/hw1.0/` 3 个、`qca/` 6 个）。

保留：`kernel/firmware/regulatory.db{,.p7s}`、`tools/bin/mkbootimg`、全部 `OnePlus/` 子树。

## 15.2 被实际执行推翻的分析结论

1. **`CONFIG_FIRMWARE_IN_KERNEL` 是 unset，`CONFIG_EXTRA_FIRMWARE` 那串清单是空转的。**
   defconfig 里没有 `CONFIG_FIRMWARE_IN_KERNEL=y`（只有 `CONFIG_EXTRA_FIRMWARE=` 和
   `=DIR`），而 `EXTRA_FIRMWARE` 只在该选项开启时生效。固件全部走运行时
   `request_firmware()` 从 `/lib/firmware` 读。
   → 前文关于"blob 会被嵌进 Image.gz、initramfs 必须带固件"的担忧不成立，
   这也解释了为什么 initramfs 不 mount `/firmware` 也能开机：GPU/venus/ADSP/wlan
   都要等 rootfs 挂上才需要固件。ref 树里同名的 `.zst` 副本（`a630_zap.mbn.zst` 等）
   是给别的设备用的，本设备走 `OnePlus/enchilada/` 下的未压缩原件。

2. **上游内核里没有 `media/cam_req_mgr.h`。**
   全树 `find` 无结果，ref 的 build 目录和 build 脚本里也没有。那是 Comma 外挂
   `kernel/spectra-camera` 自带的 vendor 头。上游 camss 的 uapi 走
   `include/uapi/linux/media/` + `linux/v4l2*.h`，没有独立命名空间。
   → `Dockerfile` 里 `test -s /usr/include/media/cam_req_mgr.h` 这条门禁必须删，
   已改成查 `linux/videodev2.h` / `linux/media.h` / `linux/v4l2-controls.h` +
   `linux/media/*.h`。

3. **Dockerfile 的逐模块 vermagic 门禁 6 个模块 4 个不存在。**
   `CONFIG_VIDEO_QCOM_CAMSS=y`、`CONFIG_VIDEO_DEV=y` —— 内置，不产 `.ko`，
   `modinfo` 直接失败；`CONFIG_VIDEO_OMX`/`CONFIG_VIDEO_MSM_VENUS`/
   `CONFIG_VIDEO_V4L2_FOURCC` 均未设置 —— `venus_{core,enc,dec}` 三个模块不存在；
   `spectra_camera` 随目录一起删了。defconfig 里实际有 878 个 `=m`，靠的是
   `modules.dep` 属于本次 krel 这一点来证明模块没串。

4. **initrd 的 `build.sh` 必须传输出路径。**
   它的签名是 `build.sh [输出路径]`，不传就把 `initrd.cpio.gz` 写进**当前目录**
   （= 子模块根目录），弄脏 `kernel/initrd` 的工作区，而且下次 `git submodule update`
   可能清掉、也可能留下上次的旧产物。ref 的 `build_bootimg.sh` 正是这么调用的，
   所以它会依赖 `build/initrd-clone` 是每次新 clone 的。本仓库改成传绝对路径，
   实测产出 1.1 MB / 3889 块，子模块保持 0 改动。

5. **`git submodule sync` 会覆盖本地 URL 覆盖。**
   它的作用就是把 `.gitmodules` 的 URL 写回 local config。想本地走 3 GB 硬链接克隆
   时不能跑 sync，直接 `git config --local submodule.kernel/linux.url <path>` 即可，
   这样 `.gitmodules` 里保留可移植的公开 URL。
   另外本地路径克隆默认被 `protocol.file.allow=never` 拒绝
   （`fatal: 传输 'file' 不允许`），用
   `git -c protocol.file.allow=always submodule update --init` 只对本次调用放开。

## 15.3 已验证

- **补丁集可复现**：在 pin `e38405d01d118861` 的干净子模块上按 glob 字典序应用
  16 个补丁，**16/16 干净通过**，改到 12 个文件（`pm8998.dtsi`、
  `sdm845-oneplus-common.dtsi`、`sdm845-wcd9340.dtsi`、
  `camcc-sdm845.c`、`a6xx_gmu.c`、`adreno_gpu.c`、`msm_submitqueue.c`、
  `imx519.c`、`qcom_smbx.c`、`rtc-pm8xxx.c`、`qcom-wled.c`、`wcd934x.c`）。
  17 个补丁时与 ref 工作区逐字节一致；删掉 `oneplus_cpu_thermal_cooling` 之后
  16/16 仍干净通过，且**唯一差异就是 `sdm845.dtsi` 不再被改**（这正是决策 5
  要的效果），其余 12 个文件不变。顺序有真实依赖，见 `build_kernel_oneplus6.sh` Step 1。
- **`CONFIG_EXTRA_FIRMWARE` 11 项全部能在 `kernel/firmware/` 下找到文件。**
- **initramfs 构建**：1.1 MB，子模块不脏。
- **四个新脚本 `bash -n` 全部通过。**

## 15.4 决策状态

| # | 决策 | 结果 | 已落地动作 |
|---|---|---|---|
| 1 | rootfs 放哪 | **`userdata`**（2026-10-24） | `build_bootimg_oneplus6.sh` 的 `ROOT_DEV=/dev/sda17`、`tools/flash/oneplus6.sh` 的 `fastboot erase/flash userdata` 本来就是按这个走的，无需改动 |
| 2 | 参考哪个实现 | **尽量照搬 ubuntu-sdm845-mainline**（2026-10-24） | rootfs 管线按 ref 的 Ubuntu 体系移植，不走 Vamos 原有的 Void/xbps/runit |
| 5 | thermal | **不动**（2026-10-23） | `kernel/patches/oneplus6/oneplus_cpu_thermal_cooling.patch` 已删除。效果：CPU 热区不再有 `cooling-maps`，trips 仍在（90000 m°C）但没接 cooling device，框架不会主动降频 |

## 15.5 还没做（阻塞中）

| # | 项 | 阻塞原因 |
|---|---|---|
| 1 | rootfs 管线移植（`build_rootfs.sh` / `update_rootfs.sh` / `Dockerfile.ubuntu-rootfs` / 相机与 IMU deb 栈） | 进行中；`userspace/` 的 Void 骨架会被替换掉 |
| 2 | 实机验证 | 需要设备。当前所有验证都是静态的（补丁应用、md5、脚本语法） |
| 3 | 首次内核编译 | 需 docker + `gcc-aarch64-none-elf` 15.2，10-30 分钟；没跑过，`check_defconfig.sh` 门禁的真实通过率未知 |

---

## 16. 2026-10-24 方向修正：只换 rootfs，boot+initrd 走 ref

第 14/15 节按「尽量参考 ubuntu-sdm845-mainline」理解成「连 rootfs 一起换成
ref 的 Ubuntu 体系」，据此把 `userspace/` 整棵 Void 树、`tools/build/Dockerfile`、
`build_system.sh`、`tools/profile|runtime|sync` 全部替换成了 ref 的 Ubuntu 管线。

2026-10-24 的方向修正是：**boot.img 和 initrd 用 ref 的逻辑，rootfs 换回 Vamos
自己的（Void + xbps + runit）**。理由是把 ref 的 rootfs 整个搬过来等于连 openpilot
的宿主发行版一起换，diff 太大；ref 里真正不可复用的是 boot/initrd 那一层。

### 16.1 为什么这个组合是成立的

ref 的 initramfs（`kernel/initrd/initramfs/init`）是 **init 系统无关** 的：

```sh
exec switch_root /mnt /sbin/init      # busybox switch_root
```

它只看 `rootfs_path=` 这个 cmdline 参数：给了就走嵌套 rootfs 镜像（comma 的
`pmos-phosh.img` / `.stowaways`），没给就走简单路径 —— 轮询 `blkid` 找
`/dev/sda17` 最多 10 秒，`mount /dev/sda17 /mnt`，然后 `exec switch_root /mnt
/sbin/init`。它**不读** `rootfstype` / `rootwait`（那两个在 cmdline 里是装饰）。

所以只要 rootfs 里有 `/sbin/init`，runit 的镜像能直接通过这个 initramfs 启动。
我们的 cmdline 里没有 `rootfs_path=`，走的是简单路径。

`/sbin/init` 由 Void 基础镜像提供：`base_setup.sh` 装 `runit-void`（包内提供
`/sbin/init` → `/sbin/runit`），`userspace/root/` 覆盖层里没有 `sbin/` 目录，
不冲突。

### 16.2 不是 drop-in：六个真实缺口及处理

| # | 缺口 | 处理 |
|---|---|---|
| 1 | `base_setup.sh:8-10` 的 `touch /TICI` + `touch /AGNOS` 是 Comma 硬件标识，会让 openpilot 判成 `PC=False` 且走 TICI 分支（找 panda CAN 总线，一加6 上没有） | 改成 `touch /ONEPLUS6`。openpilot 侧 `system/hardware/__init__.py` 有 `ONEPLUS6 = os.path.isfile('/ONEPLUS6')` 和 `class OnePlus6(HardwareBase)` |
| 2 | `base_setup.sh:135` `mkdir -p /data /persist /config /system` 会建 `/persist` 目录。设备上有 persist 分区会被挂上去（无害），但 PC/容器模式下没有那个分区，目录真存在时 openpilot 的 Python 与 C++ 两套 persist 都会解析到 `/persist`，与 `~/.comma/persist` 撞车 | 从 `mkdir -p` 里去掉 `/persist`，也不 chown |
| 3 | `etc/runit/1` 把 `userdata` 挂到 `/data`。本分支 rootfs **本身就在** userdata 上，再挂一次同一 superblock 会 EBUSY（每次开机一条 WARN，容易误判成分区表问题） | 从挂载列表删掉 `userdata:/data`；`/data` 改为 rootfs 内普通目录（`userspace/root/data`），可写 |
| 4 | `etc/runit/1` 硬编码 `/dev/sde4` 挂 `/firmware`。`sde4` 是 Comma 的 UFS LUN 编号，一加6 上同一块 modem 分区落在别的节点，会静默跳过 | 改用 `/dev/disk/by-partlabel/modem_a`，与 fstab 一致 |
| 5 | `tools/build/Dockerfile` 里 `test -s /usr/include/media/cam_req_mgr.h` + 对 `spectra_camera`/`camcc_sdm845`/`venus_*` 六个模块的 vermagic 循环。`cam_req_mgr.h` 是 Comma vendor 头，上游内核**没有**这个文件；`spectra_camera`/`camcc_sdm845`/`venus_*` 是 out-of-tree .ko，本分支内核树里没有；`mc`/`videodev` 是上游 `=y` 内置、不产 .ko。任一 `test` 失败 Docker 层直接挂 | 整段删掉，换成「目录名即契约」：`test -s /lib/modules/$KREL/modules.dep` + `qrtr` 抽样 vermagic（`CONFIG_QRTR=m`，纯内核模块，不依赖 SoC 固件路径）+ `depmod -a` |
| 6 | `build_system.sh` 的产物契约是 Comma 的：要 `build/boot.img`（路径不对，现在是 `build/output/<DEVICE>-boot.img`）、`kernel-artifacts.sha256`（没人产出）、`kernel-source-revision` 比的是**本仓库** HEAD（本分支每次提交都让它失败） | 契约改为 `kernel-rootfs.tar` + `kernel-release` + `kernel-source-revision`（比对**内核子模块** HEAD）+ `build/output/<DEVICE>-boot.img`；sha256 清单换成直接校验 tar 内容与 krel 自洽 |

### 16.3 顺手修的三个硬阻塞（不修就 Docker 层失败）

- `Dockerfile`：`echo '#!/bin/sh' > /etc/sv/sshd/run` —— `/etc/sv/sshd` 既不在
  `userspace/root/` 覆盖层里，也没有 openssh-server 包提供它，重定向不建目录，
  层直接报 `No such file`。加 `mkdir -p /etc/sv/sshd`。
- `Dockerfile`：`chmod 600 /usr/lib/NetworkManager/system-connections/*.nmconnection`
  —— 覆盖层里没有 `system-connections/` 目录也没有 `.nmconnection` 文件，glob 零
  匹配会原样展开成字面量 `*.nmconnection`，chmod 报 `cannot access`。改 `mkdir -p`
  + `find ... -exec chmod 600 {} +`（零匹配是成功空操作）。
- `Dockerfile`：服务启用循环对 `/etc/sv/<svc>` 无脑 `ln -sf`。`qrtr-ns`、
  `tqftpserv`、`pd-mapper`、`rsyslogd`、`nftables`、`cnss_daemon`、`polkitd`、
  `sshd` 八个在覆盖层里都没有对应目录，会产生悬空符号链接，runsvdir 每次重启报
  一条错误。改成存在才建、不存在就打印 WARN。

### 16.4 新增：根文件系统扩容

`build_system.sh` 的 `ROOTFS_IMAGE_SIZE=6G` 是固定值，而一加6 的 `userdata` 分区
大得多。ref 有独立的 `auto-resize-rootfs.service`；这里并进
`userspace/root/usr/comma/fs_setup.sh`（本就是开机一次性的 runit 服务），用
`findmnt` 找根设备、`blockdev` 比大小、`resize2fs` 扩容。`resize2fs` 幂等，每次
开机跑一次没有副作用。`resize2fs` 不存在时只 WARN，不让 fs_setup 整体失败
（后面的 `/home` overlay 和 `/run/fs_setup.ready` 是逗号服务的硬依赖）。

### 16.5 回滚动作

```
git checkout HEAD -- userspace tools/build/build_system.sh tools/build/Dockerfile \
  tools/build/Dockerfile.builder tools/build/package_ota.py tools/build/package_update.py \
  tools/build/upload_update.py tools/build/test_package_update.py tools/build/test_upload_update.py \
  tools/profile tools/runtime tools/sync
rm -f tools/build/{build_rootfs.sh,update_rootfs.sh,rootfs_userspace_container.sh,
Dockerfile.ubuntu-rootfs,verify_build.sh,verify_rootfs.sh,clean_build.sh,
build_camera_module.sh,build_camera_deb.sh,camera_deb_container.sh,
build_hexagonrpc_deb.sh,hexagonrpc_build_container.sh,Dockerfile.hexagonrpc,
build_libssc_deb.sh,libssc_build_container.sh,Dockerfile.libssc,
build_sensor_firmware_deb.sh,check_camera_artifacts.sh,check_sensor_artifacts.sh,
check_firmware.sh,Dockerfile.camera-builder} tools/mirror_test.sh build.sh update_build.sh
```

注意 `git checkout HEAD -- userspace` **不会删掉**之前从 ref 拷过来的 untracked 文件
（`userspace/etc`、`libssc`、`hexagonrpc`、`prebuilt`、`camera`、`home`、`initramfs`、
`usr`、`alsa-ucm-conf.tar.gz`）。必须 `rm -rf userspace` 之后再 checkout，否则
Ubuntu 残留会和 Void 树混在一起。

### 16.6 已知遗留（不阻塞启动，需要实机验证）

**2026-10-24 更新**：下表是 10-23 的原始清单。第 1/3/4/6 项已经修掉了，
第 2 项这条记录本身是错的，第 8 项有新发现见 §16.7。

| # | 项 | 10-23 状态 | 10-24 现状 |
|---|---|---|---|
| 1 | 无 udev | 包列表无 `eudev`；`core-services/` 目录不存在 | **已修**。`base_setup.sh` 加 `eudev`（Void 的 eudev 3.2.14 用 `vsv udevd` 自造 `/etc/sv/udevd`，所以 Dockerfile 里 `rm /etc/runit/runsvdir/default/udevd` 那行才有意义）；新增 `etc/runit/core-services/02-kmods.sh`，在 stage-1 启动 udevd **之前**显式 `modprobe` qrtr/qrtr-smd/mhi/mhi-net/usbnet/usb-net-cdc-ncm |
| 2 | `/usr/comma/set-hostname.sh` 不存在 | ~~不存在，返回 127~~ | **这条记录是错的**。文件一直在：`userspace/root/usr/comma/set-hostname.sh`，209 字节，可执行。当时是 `ls` 输出被截断造成的误判 |
| 3 | 8 个悬空服务 | `nftables`/`sshd` 功能性缺失 | **已修**。`sshd` 和 `nftables` 的 `/etc/sv/<svc>/run` 在 Dockerfile 里手写补上，并且**移到启用循环之前**（原实现在 120 行之后才写 run 脚本，循环跑到 sshd 时目录还不存在，被 guard 跳过 —— 也就是 SSH 从来没被启用过）；`cnss_daemon`/`polkitd` 从启用列表删除（覆盖层无目录、Void 无包、WiFi 也不需要，见 §16.7）；`qrtr-ns`/`tqftpserv`/`pd-mapper`/`rsyslogd`/`cnss_daemon`/`polkitd` 这些靠 Void 包提供，`base_setup.sh` 已装 `qrtr-ns`/`rmtfs`/`tqftpserv`/`pd-mapper`/`rsyslog`/`nftables` |
| 4 | `/usr/default/home` 不存在 | `/home` overlay 起不来 | **已修**。`fs_setup.sh` 的 `lowerdir` 改成 `/home`（`userspace/root/home/` 里的 dotfiles 就是要当只读底层的），并加 `|| echo WARN` |
| 5 | `HOST=comma` 写死 | 观感问题 | 仍在。不影响判定，观感问题 |
| 6 | `/data/params`、`/data/media/0` 不在镜像里 | `comma.sh` 的 chown 会报错 | **已修**。`fs_setup.sh` 加 `mkdir -p /data/media/0 /data/params/d; chown -R comma:comma` |
| 7 | `tools/runtime/load_camera_modules.py` 已删 | hard-fail 在 `comma,tizi` | 仍为已删除状态 |
| 8 | dorapilot 的 ONEPLUS6 HAL 未验证 | 只有静态分析 | **有结论了，且是阻塞项**。见 §16.7：仓库里三条 openpilot 供应路径**没有一条**带 ONEPLUS6 HAL |

### 16.7 最大的阻塞项：openpilot 的代码本身没有供应来源（2026-10-24 新发现）

§8 讨论的是"OS 要给 openpilot 什么"，§9 讨论的是"`dragonpilot_nana` 这个 fork
已经备好了什么"。但两者之间断了一节：**这个仓库里没有任何一条路径会把带
ONEPLUS6 HAL 的 openpilot 代码放上设备。**

三条现存的供应路径，逐条核实过：

| 路径 | 它拉的是什么 | 有 ONEPLUS6 HAL 吗 |
|---|---|---|
| `userspace/root/usr/comma/setup`（7.6 MB zipapp，2026-09-19 打包） | `openpilot/system/hardware/` 下只有 `chestnut`、`comma`、`tici` | **没有**。`__init__.py` 里连 `TICI`/`AGNOS`/`PC` 三个变量都不定义 |
| `userspace/root/usr/comma/installer_dorapilot`（ELF，strings 提取） | `https://github.com/dorapilot/openpilot.git` @ `liberation-day-7.2` | **没有** —— 这正是上面那个 zipapp 的同源上游 |
| `userspace/root/usr/comma/installer`（ELF） | `https://github.com/commaai/openpilot.git` @ `release3-staging` / `release-tizi-staging` / `release-mici-staging` | **没有** —— 那是 Comma 官方树 |

带 HAL 的代码只在**本地**：`/home/ubuntu/openpilot_oneplus/dragonpilot_nana`，
分支 `oneplus6-0.11.1-20251018`（HEAD 已到 `cfaf9e53`，比 §9 记的 `2a9fb456` 新）。
它有 `system/hardware/oneplus6/`、`system/hardware/pc/`、
`ONEPLUS6 = os.path.isfile('/ONEPLUS6')`，还有 §9.1 列的那 3 个守护进程。

`userspace/uv/openpilot/pyproject.toml` 那个"stub"（4342 字节）是故意的，不是残缺：
`userspace/uv/pyproject.toml` 里 `openpilot = { path = "openpilot" }` 只要它的
依赖列表来拉 `comma-deps-*`，代码注释写明"the code comes from /data/openpilot
via PYTHONPATH on device"。问题不在 stub，在于**没有任何东西去填 `/data/openpilot`** ——
`userspace/root/data/` 只有 `misc/wifi/*`，全仓库 grep `/data/openpilot` 只命中
3 个测试脚本和 1 个 bench 脚本的引用，没有一处是生产者。

另外 zipapp 里只有 Python 源码、没有 C++ 二进制（`selfdrive/controls/controlsd.py`
有，`selfdrive/controls/controls` 没有），`dragonpilot_nana` 本地也没有编译产物
（`controls`/`selfdrived`/`locationd`/`modeld`/`sensord`/`transformd`/`ui` 全空）。
所以就算把 Python 树搬过去，`scons` 编译仍是设备上的事。

**结论**：现在的镜像刷到一加6 上，`/ONEPLUS6` 这个标记文件会被创建，
但没有任何代码去读它 —— openpilot 起不来。这一条不补上，前面所有工作
（内核、boot、rootfs、服务）都只是让手机能进桌面，进不了辅助驾驶。

需要拍板的：怎么把 `dragonpilot_nana` 变成一个可重复的供应来源
（本地路径硬编码不可接受，至少得是一个 git 仓库 + ref）。
三种做法见 §12.5 之后的补充：把它做成子模块 / 在镜像里 vendor 一份 Python 树 /
重编 installer 指向新 ref。

### 16.8 2026-10-24 的改动（服务与构建侧）

除 §16.6 表格里列的之外，当天还做了这些：

- **砍掉 6 个 Comma 主板专属服务**（`tools/build/Dockerfile`）：`gpio`、`lte`、
  `power_monitor`、`power_drop_monitor`、`brightnessd`、`sound`。
  危害按严重度排：
  - `lte` 最严重。`lte.sh start` 是 `until is_online; do reset; power_button; done`，
    而 `is_online` 靠 `lsusb -d "0x05c6:"` 判断 —— `0x05c6` 是 Comma 自己的 USB
    厂商号，一加6 上永远不存在，所以它退化成每 ~2 秒拨一次 TLMM gpio50/gpio116
    的**死循环**。
  - `gpio` 第二严重。`gpio.sh` 最后一行无条件 `gpio 30 1`（direction=out + value=1）。
    而一加6 的 panel 节点里是 `esd-pins { pins = "gpio30"; }` —— **30 就是屏幕
    ESD 保护脚**，被抢过去锁成输出，和 DRM 面板驱动正面冲突。
  - `power_drop_monitor` 第三严重。它跟一颗 INA231 对话（I2C 0x40 + PM8998 GPIO4）。
    一加6 上没有那颗芯片也没有 PM8998，`PM8998_BASE` 回退成 0，告警脚变成
    根本没导出的 gpio3；更危险的是电压读数有 `/sys/class/hwmon/hwmon1/in1_input`
    兜底 —— 万一 hwmon1 存在但属于别的传感器，它会拿那个值当电池电压，
    低于 4000mV 就 SIGKILL 整个 comma cgroup 然后关机。
  - `power_monitor` 读 `/dev/input/by-path/platform-894000.i2c-event`（PM8998 的
    中断输入设备），不存在。
  - `brightnessd` 要写 `/sys/class/backlight/panel0-backlight/`。更根本的是：
    本分支 DTB 里**没有 backlight 节点**（`dtc` 反编译确认 compatible 里没有任何
    `*-backlight`，唯一的 "backlight" 是 pmi8998 LED 节点的 label），
    服务没有作用对象。
  - `sound` 的 `sound_init.sh` 用 `case "$(cat .../base/model)"` 只认 `comma tizi` /
    `comma mici`，其余 `exit 1`。
  只从 runit 启用列表里拿掉，脚本本体留在 rootfs 里，要恢复很容易。
- **`etc/runit/1` 的 `mount_part` 改为按 `blkid` 自动探测文件系统**，并 mkdir 挂载点。
  Comma 的 cache 是 ext4，一加6 出厂是 FAT，写死 ext4 的选项（`relatime`、
  `data=ordered`、`discard`）落在 vfat 分区上会直接 mount 失败。同时删掉
  `persist:/persist:ro` 和 `dsp_a:/dsp:ro`：persist 违反"不创建 /persist"的约束，
  参考项目的 fstab 也只有 `/dev/sda17 -> /` 一条；一加6 出厂分区表里没有 `dsp_a`。
- **ccache 真正接上**（`build_kernel_oneplus6.sh`）。之前脚本挂了 `/ccache` 卷、
  注释里也写着"ccache 复用已成功的对象文件"，但 make 的 `CC` 从来没设过 ——
  make 默认直接调 `aarch64-none-elf-gcc`，`ccache -s` 显示 0.00% 就是这个的直接
  证据，每次内核构建都是冷编译。现在 `CC='ccache aarch64-none-elf-gcc'` +
  `CCACHE_DIR`，并在构建前后打印缓存状态，命中率为 0 会 WARN。
- **修掉 `ccache -s 2>/dev/null` 的 stderr 误用**。`ccache -s` 的输出在 **stderr**，
  那个重定向会把整份统计删光，而退出码仍是 0，所以 `|| echo "ccache 不可用"`
  的回退永远不会触发 —— 构建日志里只剩一行孤零零的 "ccache 统计:"。
- **`screen_calibration.py` 的 `assert` 改成干净检查**。`COMMAND_FILE` 是
  `/sys/kernel/debug/dsi_dwo_video_display/mipi_command`，来自 Comma 下行 DRM 驱动，
  上游 msm/drm 没有这个节点。原来先判 gamma 文件、再 `assert` debugfs 路径，
  一旦 gamma 文件出现而接口没跟上，AssertionError 会直接抛出去、runsv 反复重启。
  现在两个前置条件都当"跳过"处理。
- **`fs_setup.sh` 增加 rootfs 自动扩容**：镜像固定 6G，一加6 的 userdata 远大于此，
  不扩的话 `/` 永远只有 6G。`resize2fs` 幂等，每次开机跑一次没有副作用。
- **`sshd_config` 删掉 DSA HostKey 行**：OpenSSH 8.7 起 `ssh-keygen` 不再支持 DSA，
  留着每次开机一条 "unsupported key format"，而且万一哪天只剩 dsa 一个条目，
  sshd 会因 "No supported host key types" 直接退出。
- **`adsp` / `cdsp` 服务改写成 mainline remoteproc 接口**。原来四个脚本
  （`usr/bin/cdsp.sh`、`usr/local/qr-linux/adsp-start.sh`、`etc/initscripts/adsp.sh`）
  打的全是 Qualcomm 下行内核的接口，在上游内核里**一个都不存在**：
  `/sys/kernel/boot_adsp/boot`、`/sys/kernel/boot_cdsp/boot`、
  `/sys/bus/msm_subsys/`、`/sys/module/subsystem_restart/parameters/`。
  结果：`cdsp.sh` 每次开机打一条 "File not found!"，`adsp-start.sh` 白等 10 秒
  `/firmware/image/adsp.mdt`（既不挂 `/firmware`，固件也是 `.mbn` 不是 `.mdt`）
  后 exit 1。两个 DSP 从来不会被它们启动。
  现在统一走 `/usr/bin/rproc-boot.sh <dsp> [start|stop|status]`：
  `/sys/class/remoteproc/<name>/state` 写 `start`/`stop`/`detach`
  （`remoteproc_sysfs.c` 的 `state_store()`），`running` 才算起来
  （`rproc_state_string[]`）。按 `name` 文件匹配而不是硬编码 `remoteprocN` 编号。
  另修 `etc/sv/cdsp/run` 的路径：原写 `/usr/sbin/cdsp.sh`（Comma 的 Debian 布局），
  本分支在 `/usr/bin/cdsp.sh`，runit 每重启一次报一条 not found。
  内核侧的事实链：`CONFIG_QCOM_Q6V5_PAS=y`，DTB `&adsp_pas`/`&cdsp_pas`
  （compatible `qcom,sdm845-adsp-pas`/`qcom,sdm845-cdsp-pas`）的 `.auto_boot = true`，
  `remoteproc_core.c:2348` 在 `rproc_add()` **之后**才 `rproc_trigger_auto_boot()`，
  后者走 `request_firmware_nowait(FW_ACTION_UEVENT, GFP_KERNEL)` → 同步路径。
  `CONFIG_FW_LOADER_USER_HELPER is not set`，且本分支 initramfs 是 1.9M 的 busybox、
  **里面没有 `/lib/firmware`**，固件只在 rootfs 的 `/lib/firmware/qcom/sdm845/OnePlus/
  enchilada/*.mbn`。所以 auto-boot 在 initramfs 阶段拿不到固件 —— 这个服务就是
  switch_root 之后补的那一次启动。
  参考项目没有 adsp/cdsp 服务，靠 `initramfs-tools` 的
  `userspace/initramfs/hooks/qcom-firmware` 把这些 `.mbn` 直接塞进 initramfs
  （见 §16.9 的取舍）。

- **`ncm-param-watcher` 去掉强制启用 USB NCM**。原脚本第一步是
  `echo -n 1 > /data/params/d/UsbNcmEnabled`，然后跑 `set_ncm.sh`。参数是 1
  时 `set_ncm.sh` 走 `enable_ncm`：挂 configfs、建 `/config/usb_gadget/g1`
  （idVendor `0x1d6b` / idProduct `0x0103`，NCM 网络适配器，`192.168.42.2/24`）、
  然后 `echo a600000.usb > UDC` **把 SoC 的 USB 控制器绑成 gadget**。
  那是 Comma 手机连 panda 的协议。一加6 只有**一口** USB —— 被这样绑掉之后
  ADB、数据线、充电协议全都没了，开发调试直接没法进行。
  原注释 `TODO: remove the force on once productionized` 说的就是这一步。
  另外原脚本第 18 行 `exec sleep infinity` 之后的整个 inotifywait 监听循环
  是**不可达的死代码**（`ssh-param-watcher` 没有这个问题，结构是对的），
  所以这个"watcher"从来不 watch。现在按 `ssh-param-watcher` 的结构改成：
  启动时跑一次（参数不存在 → 走 `disable_ncm` 做一次幂等解绑，不绑 UDC），
  然后真正 watch 值变化。监听目标从文件换成**目录** —— 没人启用 USB NCM 时
  openpilot 可能永远不写这个参数文件，`inotifywait` 挂在文件上会直接报错退出、
  被 runit 反复重启刷日志。
  参数仍然存在、脚本也没删，openpilot 真要开 NCM（连 panda）时照常生效。
- **其余未审计的服务过了一遍**，都不需要动：
  - `varwatch` 只是 `/var/log` 超过 70% 时 truncate 日志，无硬件依赖。
  - `magic` 是 GPU 显示服务，`/dev/dri/card0` 有守卫、`sdm_dbg_cfg.txt` 写入
    带 `|| true`；它 `chpst -u comma:comma:gpu:video` 要的 `gpu`/`video` 组
    在 `base_setup.sh` 里有建（`groupadd -f gpu` + `usermod -aG ... video ...`）。
  - `avahi-ssh-publish` 只发 mDNS 记录，model 取不到时回退成 unknown。
  - `serial-hostname` 跑一次 `set-hostname.sh` 就 sleep。
  - `ssh-param-watcher` 结构正确，只在 `SshEnabled=0` 时 `sv down sshd`。
  - `bluetoothd` 等 dbus、`rfkill unblock`、设确定性 MAC，无硬件假设。
  - `dnsmasq` 标准前台运行。

### 16.9 已知遗留：initramfs 里没有固件（DSP 自动启动必然 ENOENT）

这是 §16.8 那条改动的另一半，值得单独记一笔，因为它的修法需要一次**分区大小
决策**，不能随手改。

**问题**：`kernel/initrd`（`nanasemai/initrd@oneplus6-initrd`）是 3 个文件
（busybox 1.9M + 2 个脚本 + 395 个 busybox 符号链接）打包的 cpio.gz，
没有 `/lib/firmware` 目录，也没有任何拷固件的逻辑（`init_functions.sh`
里 `setup_firmware_path()` 只是把搜索路径加成 `/lib/firmware/postmarketos`）。
而 `qcom_q6v5_pas` 在 probe 时就通过 `request_firmware_nowait()` 要
`qcom/sdm845/OnePlus/enchilada/{adsp,cdsp,slpi,mba,modem,venus,wlanmdsp,
ipa_fws}.mbn`，加起来约 **85 MB**（`modem.mbn` 单个 60 MB）。
`CONFIG_FW_LOADER_USER_HELPER is not set`，没有用户态回退机制；
参考项目的 `oneplus6-firmware-reprobe.sh` 也明确记过这个现象：
"ipa / venus 驱动在 rootfs 挂载之前 probe，此时固件不可读，内核报 ENOENT
且不重试"。
所以 ADSP/CDSP/SLPI（modem）/venus/wlanmdsp 在 initramfs 阶段全都拿不到固件，
§16.8 的服务只是"能救则救"。

**为什么不直接塞进 initramfs**：参考项目能这么做是因为它的 rootfs 是 Ubuntu、
initramfs 由 rootfs 自己的 `initramfs-tools` 生成，固件本来就在那里。
本分支的 initramfs 是独立的 busybox 包，塞 85 MB 意味着 boot.img 从
~21 MB 涨到 ~90 MB+（`.mbn` 基本已经压缩过，gzip 帮助很小），
而 `tools/flash/oneplus6.sh` 只写 stock `boot_a`/`boot_b`、**不做任何分区
扩容**，stock 分区放不下的话刷不进去。这个决定要连着分区策略一起改，
不在这一轮里做。

**两条可选路线（待实机确认后再定）**：
1. **保留小 initramfs + §16.8 的补救服务**（现状）。赌的是
   `remoteproc_add()` 里 auto_boot 失败后 `device_del()` 没被走到
   （`request_firmware_nowait` 同步失败时 `request_firmware_failed()` 的行为
   值得实机 `dmesg` 验证一次）。设备还在的话 `state` 写入就能救回来。
2. **仿参考项目把固件塞进 initramfs**，同时给 `tools/flash/oneplus6.sh`
   加 boot 分区扩容（或改 GPT）。代价是 boot.img 变大、启动变慢、
   A/B 槽写盘时间拉长。
