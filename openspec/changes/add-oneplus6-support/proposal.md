# Change: 移植 vamOS 到一加6手机

## Why

一加6（OnePlus 6）是一款基于高通骁龙845（SDM845）处理器的智能手机，与 comma 3/3X 使用相同的 SoC。将 vamOS 移植到一加6可以：
1. 提供一个低成本的 openpilot 运行平台
2. 利用现有的 SDM845 驱动支持
3. 扩展 vamOS 的设备兼容性范围
4. 促进社区贡献和测试

## What Changes

- **内核子模块更新**：将 kernel/linux 子模块从 torvalds/linux 替换为 nanasemai/sdm845-next (sdm845-next-oneplus6 分支)
- 该分支已包含完整的一加6/6T支持：
  - 设备树配置（sdm845-oneplus-common.dtsi、sdm845-oneplus-enchilada.dts、sdm845-oneplus-fajita.dts）
  - 摄像头传感器驱动（IMX371前置、IMX376K广角、IMX519主摄）
  - 自动对焦驱动（LC898217XC）
  - SDM845平台完整配置
- **内核配置**：创建 kernel/configs/oneplus6/oneplus6.config 配置文件
  - 启用一加6显示面板 (CONFIG_DRM_PANEL_SAMSUNG_SOFEF00=y)
  - 禁用一加6T显示面板 (CONFIG_DRM_PANEL_SAMSUNG_S6E3FC2X01=n)
  - 配置摄像头驱动为模块模式
- **固件文件**：添加完整的一加6内核固件
  - QCOM 平台固件 (adsp.mbn, cdsp.mbn, venus.mbn, modem.mbn 等)
  - WiFi/蓝牙固件 (crnv21.bin)
- **构建脚本**：创建独立的一加6构建和刷写脚本
  - tools/build/build_kernel_oneplus6.sh
  - tools/flash/kernel_fastboot.sh
- **vamos 命令支持**：添加 `build kernel oneplus6` 和 `flash kernel oneplus6` 命令
- **非破坏性变更**：不修改现有 comma 设备的配置
- **userspace 配置调整**：根据一加6硬件调整分区、设备节点和服务配置

## Userspace 文件分析

### 需要为一加6调整的文件

#### 1. 分区挂载配置 (fstab)
**文件**: `userspace/root/etc/fstab`
**当前内容**: 使用 `/dev/disk/by-partlabel/*` 格式挂载分区
**一加6适配分析**:
- 一加6使用相同的 Qualcomm SDM845 平台，分区布局基本兼容
- 需要确认的分区标签：
  - `dsp_a` - DSP 固件分区
  - `modem_a` - 调制解调器固件
  - `persist` - 持久化存储
  - `userdata` - 用户数据分区
  - `cache` - 缓存分区
- **建议**: 直接兼容，可能无需修改

#### 2. 背光权限规则 (94-backlight.rules)
**文件**: `userspace/root/etc/udev/rules.d/94-backlight.rules`
**当前内容**:
```
ACTION=="add", SUBSYSTEM=="backlight", KERNEL=="panel0-backlight"...
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="soc:qcom,dsi-display@0"...
```
**一加6适配分析**:
- 设备节点路径可能因设备树配置而异
- 一加6的 DSI 显示控制器节点名称需要确认
- **建议**: 根据实际设备树调整 `KERNEL==` 匹配规则

#### 3. 亮度调节服务 (brightnessd)
**文件**: `userspace/root/etc/sv/brightnessd/run`, `userspace/root/usr/comma/brightnessd.py`
**当前内容**: Python 脚本通过 sysfs 控制背光
**一加6适配分析**:
- 背光节点路径可能不同
- 需要确认 `/sys/class/backlight/` 下的设备名称
- **建议**: 检查一加6内核的 backlight 驱动设备节点

#### 4. WiFi/蓝牙固件配置
**文件**: `userspace/root/usr/lib/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini`
**当前内容**: 包含 MAC 地址和 WiFi 驱动参数配置
**一加6适配分析**:
- 一加6使用相同的 QCA WiFi 芯片 (WCN3990/QCA6174)
- MAC 地址需要使用一加6的实际值
- **建议**: 保留该文件，但需要更新 MAC 地址

#### 5. 网络管理器配置
**文件**: `userspace/root/etc/NetworkManager/NetworkManager.conf`
**当前内容**:
```ini
[device]
wifi.scan-rand-mac-address=no
```
**一加6适配分析**: 通用配置，无需修改

### 可能需要调整的文件

#### 6. ADSP 初始化脚本
**文件**: `userspace/root/etc/initscripts/adsp.sh`, `userspace/root/usr/comma/sound/adsp-start.sh`
**当前内容**: 调用 `/usr/local/qr-linux/adsp-start.sh`
**一加6适配分析**:
- 一加6的 DSP 固件路径可能不同
- 需要确认 adsp.mbn 等固件文件的位置
- **建议**: 创建一加6专用版本或通过设备检测选择

#### 7. WLAN 初始化脚本
**文件**: `userspace/root/etc/init.d/wlan`, `userspace/root/etc/initscripts/wlan`
**当前内容**: 加载 wlan.ko 模块
**一加6适配分析**:
- 模块名称和参数可能因设备而异
- **建议**: 检查一加6内核的 wlan 驱动配置

#### 8. 固件文件
**目录**: `userspace/root/usr/lib/firmware/`
**当前内容**:
- `qcom/sdm845/a630_zap.mbn`, `a630_gmu.bin`, `a630_sqe.fw` - GPU 相关固件
- `ipa/ipa_fws.elf` - IPA 固件
**一加6适配分析**:
- SDM845 平台的固件基本通用
- 一加6可能需要额外的传感器固件
- **建议**: 验证并可能需要添加一加6特定的固件

### 无需修改的通用文件

以下文件是通用的，不需要为一加6进行调整：

#### 系统配置
- `base_setup.sh` - Void Linux 基础安装脚本
- `readonly_setup.sh` - 只读文件系统配置
- `profile` - 用户环境变量配置

#### 用户管理
- `userspace/root/home/comma/` - 用户 home 目录配置

#### 服务配置 (runit)
- `etc/sv/dnsmasq/` - DNS/DHCP 服务
- `etc/sv/NetworkManager/` - 网络管理
- `etc/sv/sshd/` - SSH 服务
- `etc/sv/bluetoothd/` - 蓝牙服务
- `etc/sv/modemmanager/` - 调制解调器管理
- `etc/sv/rmtfs/` - 远程固件服务
- `etc/sv/comma/` - openpilot 主服务

#### 系统工具
- `usr/bin/abctl` - A/B 启动控制
- `usr/bin/getprop`, `setprop` - Android 属性工具
- `usr/bin/leprop-service` - 持久化属性服务

#### comma 工具脚本
- `usr/comma/fs_setup.sh` - 文件系统设置
- `usr/comma/init.qcom.sh` - Qualcomm 初始化
- `usr/comma/comma.sh` - openpilot 启动脚本
- `usr/comma/gpio.sh`, `gpio_base.sh` - GPIO 控制
- `usr/comma/brightnessd.py` - 亮度调节
- `usr/comma/power_monitor.py` - 电源监控
- `usr/comma/magic.py` - DRM/Weston 初始化
- `usr/comma/weston.ini` - Weston 配置

#### udev 规则
- `50-firmware.rules` - 通用固件加载
- `78-modem.rules` - 调制解调器规则 (EG25/EG91/C16)
- `92-dsp.rules` - DSP 设备权限
- `93-input.rules` - 输入设备权限
- `95-gpu.rules`, `99-gpu.rules` - GPU 设备权限
- `96-i2c.rules` - I2C 总线权限
- `97-tty.rules` - 串口权限
- `98-panda.rules` - Panda 自动驾驶硬件
- `99-gpio.rules` - GPIO 设备权限

#### 开发工具
- `eval/` - 根文件系统开发工具 (git 跟踪, manifest 生成)
- `irsc_util/` - IPC 路由安全配置工具

## 一加6主线内核移植要点

### 1. 两种启动方案

#### 方案 A：无 initrd（生产环境推荐）

内核直接挂载根文件系统，要求所有驱动内置。

**优点**：启动快，架构简单
**缺点**：调试困难，触控屏可能不工作

#### 方案 B：有 initrd（开发阶段推荐）

使用 SDM845 专用 initrd，包含触控屏驱动和固件。

**优点**：便于调试，可在 initrd 中加载模块和固件
**缺点**：启动较慢

### 2. initrd 开发方案

#### 2.1 克隆 SDM845 专用 initrd

```bash
git clone https://gitlab.com/sdm845-mainline/initrd.git
cd initrd
```

#### 2.2 initrd 构建流程

```bash
# 构建 initrd.cpio.gz
./build.sh

# 验证生成的 initrd
ls -lh initrd.cpio.gz
```

#### 2.3 boot.img 打包参数

```bash
mkbootimg \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 \
  --pagesize 4096 \
  --second_offset 0x00f00000 \
  --cmdline "console=ttyMSM0,115200 root=/dev/sda13 rootfstype=ext4 rootwait=10 loglevel=3 rw splash" \
  --kernel kernel-dtb \
  --ramdisk initrd.cpio.gz \
  -o boot.img
```

#### 2.4 关键触控屏模块（modules-initfs）

根据 postmarketOS 官方配置，以下模块**必须编译进内核或包含在 initrd 中**：

```
i2c_qcom_geni    # I2C总线驱动，触控屏通信必需
rmi_core         # Synaptics RMI触控屏核心驱动
rmi_i2c          # Synaptics RMI I2C接口驱动
qcom_spmi_haptics # 触觉反馈驱动
```

### 3. 内核启动参数 (cmdline)

**标准启动参数：**
```
console=ttyMSM0,115200 root=/dev/sda13 rootfstype=ext4 rootwait=10 loglevel=3 rw splash
```

| 参数 | 说明 | 备注 |
|------|------|------|
| `console=ttyMSM0,115200` | 串口控制台 | 与 comma 3/3X 相同 |
| `root=/dev/sda13` | 根文件系统分区 | ⚠️ **一加6使用 system_a 分位** |
| `rootfstype=ext4` | 文件系统类型 | 通用 |
| `rootwait=10` | 等待根设备就绪 | 可能需要调整 |
| `loglevel=3` | 日志级别 | 通用 |

**一加6 A/B 分区布局：**
| 分区 | 设备节点 | 用途 |
|------|---------|------|
| system_a | sda13 | 根文件系统 (rootfs) |
| system_b | sda14 | 备用系统分区 |
| odm_a | sda15 | OEM 数据分区 |
| userdata | sda17 | 用户数据分区 |

### 2. 必须编译进内核的关键模块

根据 postmarketOS 官方配置，以下模块**必须内置（`*`）而非模块（`M`）**：

| 模块 | 功能 | 重要性 |
|------|------|--------|
| `i2c_qcom_geni` | I2C总线（触控屏通信） | 🔴 必须 |
| `rmi_core` | Synaptics RMI触控屏核心 | 🔴 必须 |
| `rmi_i2c` | Synaptics RMI触控屏接口 | 🔴 必须 |
| `qcom_spmi_haptics` | 触觉反馈 | 🟡 推荐 |

### 3. boot.img 打包参数 (mkbootimg)

```bash
mkbootimg \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 \
  --pagesize 4096 \
  --second_offset 0x00f00000 \
  --cmdline "console=ttyMSM0,115200 root=/dev/sda13 rootfstype=ext4 rootwait=10 loglevel=3 rw splash" \
  --kernel kernel-dtb \
  -o boot.img
```

### 4. 固件加载配置

- **固件路径**: `/firmware/image` (内核默认) 或 `/lib/firmware/qcom/`
- **init 脚本需要**: 设置 `echo "/firmware/image" > /sys/module/firmware_class/parameters/path`

## Impact

- 受影响的规范: specs/device-support/spec.md
- 受影响的代码:
  - kernel/configs/ - 新增 oneplus6 配置
  - kernel/dts/ - 新增一加6设备树文件
  - kernel/patches/ - 新增摄像头驱动补丁目录
  - tools/build/ - 新增构建脚本补丁
  - userspace/root/etc/udev/rules.d/ - 可能需要调整背光规则
  - userspace/root/etc/sv/ - 可能需要调整 brightnessd 服务
  - userspace/root/usr/lib/firmware/ - 可能需要添加一加6特定固件
  - userspace/root/usr/comma/sound/ - 可能需要调整 ADSP 初始化
  - userspace/root/etc/initscripts/ - 可能需要调整 WLAN 初始化
- 新增目录:
  - kernel/patches/oneplus6/ - 一加6专用补丁
  - kernel/configs/oneplus6/ - 一加6配置文件
  - userspace/root/etc/sv/oneplus6/ - 一加6专用服务 (可选)

## 实施状态

### ✅ 已完成

| 文件 | 实施内容 |
|------|----------|
| `userspace/root/etc/udev/rules.d/94-oneplus6-backlight.rules` | 新建：一加6背光 udev 规则 |
| `userspace/root/etc/udev/rules.d/99-oneplus6-wifi-mac.rules` | 新建：WiFi/Bluetooth MAC udev 规则 |
| `userspace/root/usr/comma/brightnessd.py` | 修改：增加 `--device oneplus6` 参数和自动检测 |
| `userspace/root/etc/sv/brightnessd-oneplus6/run` | 新建：一加6亮度服务启动脚本 |
| `userspace/root/etc/sv/brightnessd-oneplus6/finish` | 新建：一加6亮度服务 finish 脚本 |
| `userspace/root/usr/local/sbin/bootmac-wrapper` | 新建：MAC 地址设置脚本（备用） |
| `userspace/root/etc/fstab.oneplus6` | 新建：一加6分区配置模板 |
| `userspace/base_setup.sh` | 修改：添加 bootmac 从 postmarketOS 安装 |

### ⚠️ 待验证（通用 Qualcomm 脚本，理论兼容）

| 文件 | 说明 |
|------|------|
| `userspace/root/usr/comma/sound/adsp-start.sh` | Qualcomm 通用 DSP 初始化脚本 |
| `userspace/root/etc/init.d/wlan` | Qualcomm 通用 WLAN 初始化脚本 |
| `userspace/root/etc/initscripts/wlan` | Qualcomm 通用 WLAN 初始化脚本 |

这些是 SDM845 平台通用脚本，一加6使用相同 SoC，理论上兼容。实际兼容性需在设备上测试验证。

### 🔴 需要修复

| 文件/配置 | 问题 | 修复方案 | 状态 |
|-----------|------|----------|------|
| `kernel/configs/oneplus6/oneplus6.config` | 缺少关键触控屏模块内置配置 | 添加 `CONFIG_I2C_QCOM_GENI=y`, `CONFIG_RMI_CORE=y`, `CONFIG_RMI_I2C=y`, `CONFIG_QCOM_SPMI_HAPTICS=y` | ✅ 已修复 |
| `kernel/configs/oneplus6/oneplus6.config` | 缺少 UFS 存储驱动内置 | 添加 `CONFIG_SCSI_UFS_QCOM=y`, `CONFIG_UFS_QCOM=y` | ✅ 已修复 |
| `tools/build/build_kernel_oneplus6.sh` | cmdline 需更新为 `root=/dev/sda13` | 修改 root= 参数 | ✅ 已修复 |
| `userspace/root/etc/fstab.oneplus6` | 分区配置需添加 rootfs | 添加 system_a 作为根文件系统挂载点 | ✅ 已修复 |

## 触控屏关键模块说明

根据 postmarketOS 官方 modules-initfs 文件，以下模块**必须编译进内核（内置）**才能确保一加6触控屏正常工作：

```
i2c_qcom_geni    # I2C总线驱动，触控屏通信必需
rmi_core         # Synaptics RMI触控屏核心驱动
rmi_i2c          # Synaptics RMI I2C接口驱动
qcom_spmi_haptics # 触觉反馈驱动
```

**原因**：这些模块需要在挂载根文件系统之前就加载，而 vamOS 不使用 initrd，所以必须内置到内核中。