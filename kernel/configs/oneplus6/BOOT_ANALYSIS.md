# OnePlus 6 内核配置排查文档

> 更新时间：2026-05-25（2026-10-09 补注）

> ⚠️ **重新生成 `.config` 的铁律**：基线只能用**当前 tree 的那份** `oneplus6_defconfig`，
> 不要用历史备份 / 别的分支 / 别的内核版本的文件。用旧文件当基线时，改名的符号
> （如 `INPUT_QCOM_SPMI_HAPTICS` → `INPUT_QCOM_PMI8998_HAPTICS`）会静默掉成 `=n`，
> olddefconfig 不报错、构建也不报错，只有设备上功能没了。2026-10-09 就是踩了这个坑，
> 掉了 `INPUT_QCOM_PMI8998_HAPTICS` / `VIDEO_LC89821X` / `HW_RANDOM_QCOM` 三项。
> 生成后请跑 `./tools/build/check_defconfig.sh` 核对；`build_kernel.sh` 已内置这一步。

---

## 一、待修复问题清单

### 🔴 高优先级

1. **WiFi/BT 协处理器驱动未编译进内核 ✅ 已修复**
   - **问题**：`CONFIG_QCOM_WCNSS_PIL=m`（模块）应为 `=y`（内置）→ **已修复为 =y**
   - **原因**：设备树 `wcn3990-pmu` 节点需要固件加载驱动
   - **修复**：已在 2026-05-24 提交中修复
   - **影响**：WiFi 和蓝牙可能无法正常工作

2. **蓝牙 LE 支持被禁用 ✅ 已修复**
   - **问题**：`# CONFIG_BT_LE is not set`（已禁用）→ **已修复为 =y**
   - **原因**：OnePlus 6 使用 Qualcomm WCN3990 芯片，需要 BLE 支持
   - **修复**：已在 2026-05-24 提交中修复
   - **影响**：蓝牙低功耗功能无法使用

### 🟡 中优先级

3. **协处理器驱动（Q6V5）模块化**
   - **问题**：`CONFIG_QCOM_Q6V5_COMMON=m`、`CONFIG_QCOM_Q6V5_ADSP=m`、`CONFIG_QCOM_Q6V5_MSS=m`、`CONFIG_QCOM_Q6V5_PAS=m`（均为模块）
   - **建议**：设备树中 `status=okay` 的节点应设为 `=y`，但目前已编译为模块，需在启动后手动加载
   - **当前状态**：系统启动后可自动加载（通过 udev），暂时不影响启动
   - **修复**：如需确保启动时可用，在 `oneplus6_defconfig` 中改为 `=y`

4. **固件配置不完整**
   - **问题**：`CONFIG_EXTRA_FIRMWARE` 缺少部分固件路径
   - **当前配置**：包含 GPU 固件、WiFi 固件，但可能缺少蓝牙固件
   - **建议**：检查 `kernel/firmware/` 目录，确保所有必要固件都已包含
   - **修复**：
     ```bash
     # 添加蓝牙固件到配置
     CONFIG_EXTRA_FIRMWARE="qcom/a630_sqe.fw qcom/a630_gmu.bin qcom/sdm845/OnePlus/enchilada/a630_zap.mbn regulatory.db regulatory.db.p7s ath10k/WCN3990/hw1.0/board-2.bin ath10k/WCN3990/hw1.0/wlanmdsp.mbn qca/OnePlus/enchilada/crnv21.bin"
     ```

---

## 二、从设备日志中发现的问题（2026-05-25）

### 🔴 WiFi/BT 协处理器加载失败

**日志信息**：
```
qcom-q6v5-mss 4080000.remoteproc: failed to acquire pdc reset
pwrseq-qcom_wcn wcn3990-pmu: error -EPERM: Error applying setting, reverse things back
qcom-q6v5-mss 4080000.remoteproc: Handover signaled, but it already happened
qcom-q6v5-mss 4080000.remoteproc: port failed halt
wlan0: failed to remove key (0, a4:39:b6:19:08:a3) from hardware (-110)
```

**问题分析**：
1. 协处理器（Q6V5 MSS）无法获取 PDC reset，导致固件加载失败
2. WiFi/BT 电源序列（pwrseq）操作失败（权限错误）
3. WiFi 密钥安装失败（可能是固件未正确加载）

**可能原因**：
- `CONFIG_QCOM_WCNSS_PIL=m`（模块）导致启动时固件加载延迟
- 设备树中 `wcn3990-pmu` 节点配置可能不完整
- 缺少必要的固件文件

**建议修复**：
```bash
# 1. 确认固件文件存在
ls -lh /lib/firmware/qcom/a630_sqe.fw
ls -lh /lib/firmware/qcom/a630_gmu.bin
ls -lh /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin

# 2. 修复内核配置
sed -i 's/CONFIG_QCOM_WCNSS_PIL=m/CONFIG_QCOM_WCNSS_PIL=y/' kernel/configs/oneplus6/oneplus6_defconfig

# 3. 重新编译并刷入
./tools/build/build_kernel.sh
./tools/build/build_bootimg.sh
./flash.sh
```

### 🟡 音频编解码器配置缺失

**日志信息**：
```
Failed to find module 'snd-soc-tfa98xx'
wcd934x-slim 217:250:1:0: missing qcom,mbhc-buttons-vthreshold-microvolt entry
qcom,slim-ngd-ctrl 171c0000.slim-ngd: QMI wait timeout
```

**问题分析**：
1. TFA98xx 音频放大器模块缺失（未编译）
2. WCD934x 音频编解码器缺少 MBHC（Multi Headphone Jack Config）阈值配置
3. SLIM 总线通信超时

> 📌 上面第二行日志同时证明**WCD9340 编解码器驱动是存在的**：驱动名 `wcd934x-slim`，
> 源码在 `drivers/mfd/wcd934x.c`（MFD）与 `sound/soc/codecs/wcd934x.c`（编解码器），
> 对应 `CONFIG_MFD_WCD934X=y` + `CONFIG_SND_SOC_WCD934X=y`。
> 旧文档里"本树完全没有 WCD9340 驱动、只能移植 6500 行回来"的说法**是错的**——
> 上游只是把符号从 `wcd9340` 改名成了 `wcd934x`。麦克风/听筒的问题要从
> MBHC 阈值属性和 dai-link 绑定上排查，不用再找驱动。

**影响**：
- 音频输出可能工作，但部分功能受限
- 耳机检测功能可能不准确

**建议**：
- 如需完整音频支持，需要添加 `CONFIG_SND_SOC_TFA98XX=m`
- 检查设备树中 `wcd9340` 节点配置

### 🟡 蓝牙 RFCOMM 协议不支持

**日志信息**：
```
sap-server: Operation not permitted (1)
RFCOMM server failed: Protocol not supported (93)
```

**问题分析**：
- RFCOMM 协议未正确初始化
- 可能是蓝牙协议栈配置问题

**建议**：
- 检查 `CONFIG_BT_RFCOMM=y` 配置
- 更新 bluez 相关包

### 🟢 其他警告（暂时可忽略）

| 警告信息 | 说明 | 影响 |
|---------|------|------|
| `debugfs: 'cpu0' already exists in 'opp'` | CPU OPP 节点重复 | 无，不影响功能 |
| `bq27xxx-battery: invalid battery data` | 电池驱动数据异常 | 电池状态显示可能不准 |
| `Filesystem uses "xz" compression` | initramfs 压缩格式警告 | 无，仅警告 |
| `spmi write disallowed` | SPMI 总线写入限制 | 无，安全机制 |

---

## 三、检查清单

**首要方式：跑断言脚本**（119 项，缺项非零退出，`build_kernel.sh` 已内置同样的检查）：

```bash
./tools/build/check_defconfig.sh                                   # 默认核对 build/out/.config
./tools/build/check_defconfig.sh kernel/configs/oneplus6/oneplus6_defconfig
# 清单本体: kernel/configs/oneplus6/required_config.conf
```

单项含义与注意点：

| 检查项 | 结论（2026-10-09 实测） |
|--------|------------------------|
| `CONFIG_USB_DWC3_QCOM` | `=y` ✅ |
| `CONFIG_SUSPEND` | `=y` ✅ |
| `CONFIG_SERIAL_QCOM_GENI_CONSOLE` | `=y` ✅ |
| `CONFIG_DRM_PANEL_SAMSUNG_SOFEF00` | `=y` ✅ |
| `CONFIG_ARCH_SDM845` | **本树没有这个符号**，SDM845 由 `ARCH_QCOM` + SoC 表承接，不要照旧文档去找它 |
| `CONFIG_QCOM_Q6V5_COMMON/ADSP/MSS/PAS` | 四项均 `=y` ✅（早期文档写 `=m`，已过期） |
| `CONFIG_QCOM_WCNSS_PIL` / `CONFIG_BT_LE` | `=y` ✅ |
| `CONFIG_BT_RFCOMM` | `=m`（模块，bluetoothd 需要时自动加载 `rfcomm.ko`；文档曾写 `=y`） |
| `CONFIG_LEDS_QCOM_FLASH` | `=m`，tristate 上限所致，见 README §12 |
| `CONFIG_FW_LOADER_USER_HELPER` | `=n` ✅ |
| `CONFIG_EXTRA_FIRMWARE` | 见第五节「固件路径验证」 |

构建前其他核对（保留原有 greps 供人工参考）：

```bash
cd kernel/linux/

# ✅ USB DWC3 QCOM 支持
grep "CONFIG_USB_DWC3_QCOM" .config
# 期望: CONFIG_USB_DWC3_QCOM=y
# 状态: 已确认 ✅

# ✅ SUSPEND
grep "CONFIG_SUSPEND" .config
# 期望: CONFIG_SUSPEND=y
# 状态: 已确认 ✅

# ✅ MSM 串口 console
grep "CONFIG_SERIAL_QCOM_GENI_CONSOLE" .config
# 期望: CONFIG_SERIAL_QCOM_GENI_CONSOLE=y
# 状态: 已确认 ✅

# ✅ 面板支持
grep "CONFIG_DRM_PANEL_SAMSUNG_SOFEF00" .config
# 期望: CONFIG_DRM_PANEL_SAMSUNG_SOFEF00=y
# 状态: 已确认 ✅

# ⚠️ 固件内置（需验证完整性）
grep "CONFIG_EXTRA_FIRMWARE" .config
# 期望: 包含 a630_sqe.fw a630_gmu.bin 等
# 状态: 部分配置 ⚠️

# ✅ FW_LOADER_USER_HELPER
grep "CONFIG_FW_LOADER_USER_HELPER" .config
# 期望: CONFIG_FW_LOADER_USER_HELPER=n
# 状态: 已确认 ✅

# ✅ WCNSS 协处理器驱动（已修复）
grep "CONFIG_QCOM_WCNSS_PIL" .config
# 期望: CONFIG_QCOM_WCNSS_PIL=y
# 当前: CONFIG_QCOM_WCNSS_PIL=y ✅ 已修复

# ✅ 蓝牙 LE 支持（已修复）
grep "CONFIG_BT_LE" .config
# 期望: CONFIG_BT_LE=y
# 当前: CONFIG_BT_LE=y ✅ 已修复

# ⚠️ 协处理器驱动（设备树中 status=okay 的建议 =y）
grep -E "CONFIG_QCOM_Q6V5" .config
# 期望: 所有相关配置应为 =y
# 当前: 均为 =m ⚠️ 暂时可用，但建议优化
```

### 重新生成 .config（当前推荐方式）

```bash
# 1) 在 builder 容器里、用交叉工具链跑 olddefconfig。
#    宿主 gcc 探测不到交叉编译器的特性，会改掉 CC_HAS_*/ARM64_MTE/SME 等约 39 行，还得手工 sed 回来。
#    注意：该镜像 ENTRYPOINT 是 `sleep infinity`，必须加 --entrypoint bash，否则命令根本不执行。
cd /home/ubuntu/openpilot_oneplus/ubuntu-sdm845-mainline
docker run --rm --entrypoint bash --network host -u 1000:1000 \
  -v "$PWD:$PWD" -w "$PWD" -v /tmp:/scratch sdm845-kernel-builder:latest -c \
  'rm -rf /scratch/kcfg && mkdir -p /scratch/kcfg && \
   cp kernel/configs/oneplus6/oneplus6_defconfig /scratch/kcfg/.config && \
   make -C $PWD/kernel/linux O=/scratch/kcfg ARCH=arm64 CROSS_COMPILE=aarch64-none-elf- olddefconfig'

# 2) 核对：基线里 =y/=m 的符号有没有变成 n / 消失 —— 改名符号只有这一步能查出来
diff <(grep -E '^(CONFIG_|# CONFIG_)' kernel/configs/oneplus6/oneplus6_defconfig) \
     <(grep -E '^(CONFIG_|# CONFIG_)' /tmp/kcfg/.config)
./tools/build/check_defconfig.sh /tmp/kcfg/.config

# 3) 确认无误后回写
cp /tmp/kcfg/.config kernel/configs/oneplus6/oneplus6_defconfig
```

### 快速修复命令（历史记录）

**注意**：以下高优先级修复已应用（2026-05-24），命令保留供参考。

```bash
# 1. 修复 WCNSS 驱动
sed -i 's/CONFIG_QCOM_WCNSS_PIL=m/CONFIG_QCOM_WCNSS_PIL=y/' kernel/configs/oneplus6/oneplus6_defconfig

# 2. 启用蓝牙 LE
echo "CONFIG_BT_LE=y" >> kernel/configs/oneplus6/oneplus6_defconfig

# 3. 可选：优化协处理器驱动
sed -i 's/CONFIG_QCOM_Q6V5_COMMON=m/CONFIG_QCOM_Q6V5_COMMON=y/' kernel/configs/oneplus6/oneplus6_defconfig
sed -i 's/CONFIG_QCOM_Q6V5_ADSP=m/CONFIG_QCOM_Q6V5_ADSP=y/' kernel/configs/oneplus6/oneplus6_defconfig
sed -i 's/CONFIG_QCOM_Q6V5_MSS=m/CONFIG_QCOM_Q6V5_MSS=y/' kernel/configs/oneplus6/oneplus6_defconfig
sed -i 's/CONFIG_QCOM_Q6V5_PAS=m/CONFIG_QCOM_Q6V5_PAS=y/' kernel/configs/oneplus6/oneplus6_defconfig
```

---

## 三、已确认正常配置

| 配置项 | 值 | 状态 | 说明 |
|--------|-----|------|------|
| `CONFIG_ARM64` | `=y` | ✅ | ARM64 架构支持 |
| `CONFIG_ARCH_SDM845` | — | ⚠️ | **本树没有这个符号**；SDM845 由 `CONFIG_ARCH_QCOM=y` + SoC 表承接 |
| `CONFIG_USB_DWC3_QCOM` | `=y` | ✅ | USB DWC3 QCOM 支持 |
| `CONFIG_SUSPEND` | `=y` | ✅ | 系统挂起支持 |
| `CONFIG_SERIAL_QCOM_GENI_CONSOLE` | `=y` | ✅ | 串口控制台 |
| `CONFIG_DRM_PANEL_SAMSUNG_SOFEF00` | `=y` | ✅ | 显示面板 |
| `CONFIG_I2C_QCOM_GENI` | `=y` | ✅ | I2C 触控支持 |
| `CONFIG_RMI4_CORE` | `=y` | ✅ | RMI4 触控核心 |
| `CONFIG_DRM_MSM` | `=y` | ✅ | MSM DRM 框架 |
| `CONFIG_ATH10K` | `=y` | ✅ | ath10k 核心 |
| `CONFIG_BT_BREDR` | `=y` | ✅ | 蓝牙 BR/EDR |
| `CONFIG_QCOM_WCNSS_CTRL` | `=y` | ✅ | WCNSS 控制接口 |
| `CONFIG_FW_LOADER_USER_HELPER` | `=n` | ✅ | 固件加载优化 |
| `CONFIG_QCOM_WCNSS_PIL` | `=y` | ✅ | WiFi/BT 协处理器（已修复） |
| `CONFIG_BT_LE` | `=y` | ✅ | 蓝牙低功耗（已修复） |

---

## 四、参考配置来源

| 文件 | 说明 |
|------|------|
| `kernel/linux/arch/arm64/configs/sdm845.config` | SDM845 基础配置 |
| `kernel/linux/.config.bak` | 参考配置备份 |
| `kernel/configs/oneplus6/oneplus6_defconfig` | OnePlus 6 的**完整 .config**（不是片段），由当前内核树生成；生成/核对流程见项目根 `CLAUDE.md` |
| `kernel/configs/oneplus6/required_config.conf` | 关键开关断言清单（119 项），由 `tools/build/check_defconfig.sh` 核对 |
| `kernel/linux/arch/arm64/boot/dts/qcom/sdm845-oneplus-common.dtsi` | 设备树配置 |

---

## 五、固件路径验证

```bash
# 检查固件文件是否存在
ls -lh kernel/firmware/qcom/a630_sqe.fw
ls -lh kernel/firmware/qcom/a630_gmu.bin
ls -lh kernel/firmware/qcom/sdm845/OnePlus/enchilada/a630_zap.mbn
ls -lh kernel/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin
ls -lh kernel/firmware/ath10k/WCN3990/hw1.0/board-2.bin
ls -lh kernel/firmware/qca/OnePlus/enchilada/crnv21.bin

# 验证固件权限
ls -l /lib/firmware/qcom/  # 在设备上检查
ls -l /lib/firmware/ath10k/  # 在设备上检查
ls -l /lib/firmware/qca/  # 在设备上检查
```
