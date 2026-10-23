# OnePlus 6 (enchilada) 内核硬件配置

基于设备树 `sdm845-oneplus-common.dtsi` + `sdm845-oneplus-enchilada.dts` 分析。

> **本表是"硬件 ↔ 开关"的映射，实际取值一律以 `kernel/configs/oneplus6/oneplus6_defconfig` 为准。**
> 下表历史上写错过若干次（沿用了改名前的旧符号名、把 `=m` 写成 `=y`），所以改完配置请跑
> `./tools/build/check_defconfig.sh`（清单：`kernel/configs/oneplus6/required_config.conf`）；
> `tools/build/build_kernel.sh` 在编译前也会自动核对，缺项直接中止构建。

## SoC: Qualcomm Snapdragon 845 (SDM845)

---

## 硬件设备与内核配置映射

### 1. 显示/GPU

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| Adreno 630 GPU | `&gpu` | `CONFIG_DRM_MSM=y` | 内置 |
| MDSS 显示子系统 | `&mdss` | `CONFIG_DRM_MSM_MDSS=y` | 内置 |
| DSI0 控制器 | `&mdss_dsi0` | `CONFIG_DRM_MSM_DSI=y` | 内置 |
| DSI0 PHY (10nm) | `&mdss_dsi0_phy` | `CONFIG_DRM_MSM_DSI_10NM_PHY=y` | 内置 |
| Samsung SOFEF00 AMOLED 面板 | `samsung,sofef00` | `CONFIG_DRM_PANEL_SAMSUNG_SOFEF00=y` | 内置 |
| Display CC 时钟 | `&gcc` | `CONFIG_SDM_DISPCC_845=y` | 内置 |
| GPU Zap Shader | `&gpu_zap_shader` | `CONFIG_SDM_GPUCC_845=y` | 内置 |
| LAB/IBB 显示供电 | `labibb` (pmi8998.dtsi:96，**无 label**，不能用 `&labibb` 引用) | `CONFIG_REGULATOR_QCOM_LABIBB=y` | 内置 |

### 2. 音频

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| SDM845 声卡 | `qcom,sdm845-sndcard` | `CONFIG_SND_SOC_SDM845=y` | 内置 |
| WCD9340/WCD9341 编解码器 | `&wcd9340` (slim217,250) | `CONFIG_SND_SOC_WCD934X=y` + `CONFIG_MFD_WCD934X=y` | 内置 |
| WCD9335 SLIMBUS 编解码器 | 本设备不用 | `# CONFIG_SND_SOC_WCD9335 is not set` | 未启用 |
| MAX98927 扬声器放大器 | `maxim,max98927` (I2C4) | `CONFIG_SND_SOC_MAX98927=y` | 内置 |
| Q6 AFE DAI | `&q6afedai` | `CONFIG_SND_SOC_QDSP6_AFE=y` | 内置 |
| Q6 ASM DAI | `&q6asmdai` | `CONFIG_SND_SOC_QDSP6_ASM=y` | 内置 |
| Q6 Voice (语音通话) | `&q6voicedai` | `CONFIG_SND_SOC_QDSP6_Q6VOICE=y` | 内置 |
| Q6 Routing | `&q6routing` | `CONFIG_SND_SOC_QDSP6_ROUTING=y` | 内置 |
| APR 音频包路由 | (q6dsp) | `CONFIG_QCOM_APR=y` | 内置 |
| SLIMBus 总线 | (slim-ngd 框架) | `CONFIG_SLIMBUS=y` | 内置 |
| SLIMBus NGD 控制器 | `&slim` (sdm845.dtsi:4078 `slim-ngd@171c0000`，`qcom,slim-ngd-v2.1.0`) | `CONFIG_SLIM_QCOM_NGD_CTRL=y` | 内置 |

> NGD 控制器在上游 `sdm845.dtsi` 里默认 `status = "disabled"`，由 `sdm845-wcd9340.dtsi` 的
> `&slim { status = "okay"; }` 重新打开（wcd9340 的 slim217,250 挂在它下面）。**label 是 `slim`
> 不是 `slimbus`**——label 写错，覆盖语句就变成新建一个同名节点，原来那个还是 disabled。

### 3. 蓝牙/WiFi

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| WCN3990 蓝牙 | `qcom,wcn3990-bt` (UART6) | `CONFIG_BT_HCIUART_QCA=y` | 内置 |
| WCN3990 WiFi | `&wifi` | `CONFIG_ATH10K_SNOC=y` | 内置 |
| WCNSS PIL 协处理器 | (wcnss) | `CONFIG_QCOM_WCNSS_PIL=y` | 内置 |
| WCNSS 控制器 | (wcnss) | `CONFIG_QCOM_WCNSS_CTRL=y` | 内置 |
| BT LE 低功耗 | (wcn3990-bt) | `CONFIG_BT_LE=y` | 内置 |
| BT RFCOMM 串口协议 | - | `CONFIG_BT_RFCOMM=m` | 模块 |
| BT BNEP 网络封装 | - | `CONFIG_BT_BNEP=m` | 模块 |

### 4. NFC

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| PN553 NFC 芯片 | `nxp,pn553` (I2C3) | `CONFIG_NFC_NXP_NCI=y` | 内置 |
| NFC I2C 传输 | `nxp,nxp-nci-i2c` | `CONFIG_NFC_NXP_NCI_I2C=y` | 内置 |

### 5. 触控屏

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| Synaptics RMI4 触控 | `syna,rmi4-i2c` (I2C12) | `CONFIG_RMI4_CORE=y` | 内置 |
| RMI4 I2C 传输 | - | `CONFIG_RMI4_I2C=y` | 内置 |
| RMI4 F11 功能 | rmi4-f11 | `CONFIG_RMI4_F11=y` | 内置 |
| RMI4 F12 功能 | rmi4-f12@12 | `CONFIG_RMI4_F12=y` | 内置 |
| RMI4 F30 功能 | rmi4-f30 | `CONFIG_RMI4_F30=y` | 内置 |
| RMI4 F3A 功能 | rmi4-f3a | `CONFIG_RMI4_F3A=y` | 内置 |

### 6. 摄像头

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| CAMSS 相机子系统 | `&camss` | `CONFIG_VIDEO_QCOM_CAMSS=y` | 内置 |
| CCI I2C 控制器 | `&cci` | `CONFIG_I2C_QCOM_CCI=y` | 内置 |
| 后置主摄 IMX519 | `sony,imx519` | `CONFIG_VIDEO_IMX519=y` | 内置 |
| 前置摄像头 IMX371 | `sony,imx371` | `CONFIG_VIDEO_IMX371=y` | 内置 |
| 后置副摄 IMX376K | `sony,imx376k` | `CONFIG_VIDEO_IMX376=y` | 内置 |
| 对焦/OIS 马达 LC89821X | `onnn,lc898217xc` | `CONFIG_VIDEO_LC89821X=y` | 内置 |
| 相机时钟控制器 | `&clock_camcc` | `CONFIG_SDM_CAMCC_845=y` | 内置 |

### 7. Remoteproc (远程处理器)

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| ADSP (音频DSP) | `&adsp_pas` | `CONFIG_QCOM_Q6V5_ADSP=y` | 内置 |
| CDSP (计算DSP) | `&cdsp_pas` | `CONFIG_QCOM_Q6V5_PAS=y` | 内置 |
| SLPI (传感器DSP) | `&slpi_pas` | `CONFIG_QCOM_Q6V5_PAS=y` | 内置 |
| Modem (MSS) | `&mss_pil` | `CONFIG_QCOM_Q6V5_MSS=y` | 内置 |
| Sysmon | (remoteproc) | `CONFIG_QCOM_SYSMON=y` | 内置 |
| PIL Info | (remoteproc) | `CONFIG_QCOM_PIL_INFO=y` | 内置 |
| MDT Loader | (remoteproc) | `CONFIG_QCOM_MDT_LOADER=y` | 内置 |

### 8. USB

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| USB DWC3 控制器 | `&usb_1_dwc3` | `CONFIG_USB_DWC3=y` | 内置 |
| USB DWC3 QCOM 包装 | `&usb_1` | `CONFIG_USB_DWC3_QCOM=y` | 内置 |
| QUSB2 HS PHY | `&usb_1_hsphy` | `CONFIG_PHY_QCOM_QUSB2=y` | 内置 |
| USB Role Switch | (dwc3) | `CONFIG_USB_ROLE_SWITCH=y` | 内置 |
| USB Conn GPIO | (usb) | `CONFIG_USB_CONN_GPIO=y` | 内置 |

### 9. 存储

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| UFS Host Controller | `&ufs_mem_hc` | `CONFIG_SCSI_UFSHCD=y` | 内置 |
| UFS QCOM | `&ufs_mem_hc` | `CONFIG_SCSI_UFS_QCOM=y` | 内置 |
| UFS PHY | `&ufs_mem_phy` | `CONFIG_PHY_QCOM_QMP_UFS=y` | 内置 |
| UFS Crypto | (ufs) | `CONFIG_SCSI_UFS_CRYPTO=y` | 内置 |

### 10. 电源/电池/充电

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| BQ27441 电池电量计 | `ti,bq27411` (I2C10) | `CONFIG_BATTERY_BQ27XXX=y` | 内置 |
| PMI8998 充电器 | `&pmi8998_charger` | `CONFIG_CHARGER_QCOM_SMB2=y` | 内置 |
| 电池管理器 | (battery) | `CONFIG_BATTERY_QCOM_BATTMGR=y` | 内置 |
| PMIC GLINK 通信 | (power) | `CONFIG_QCOM_PMIC_GLINK=y` | 内置 |
| RMTFS MEM | (modem) | `CONFIG_QCOM_RMTFS_MEM=y` | 内置 |

### 11. 触觉反馈/振动

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| PMI8998 Haptics | `&pmi8998_haptics` | `CONFIG_INPUT_QCOM_PMI8998_HAPTICS=y` | 内置 |

### 12. LED/闪光灯

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| PMI8998 闪光灯 | `&pmi8998_flash` | `CONFIG_LEDS_QCOM_FLASH=m` | 模块（上限） |
| PMI8998 LPG (RGB LED) | `&pmi8998_lpg` | `CONFIG_LEDS_QCOM_LPG=y` | 内置 |

> `CONFIG_LEDS_QCOM_FLASH` 只能 `=m`：它依赖 `CONFIG_LEDS_CLASS_FLASH`，而后者在本配置里是 `=m`，
> tristate 的上限由父项决定，写 `=y` 也会被 syncconfig 改回 `=m`。`leds-qcom-flash.ko` 靠 DT
> alias 自动加载，闪光灯功能不受影响。

### 13. 串口/UART

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| UART9 (控制台) | `&uart9` | `CONFIG_SERIAL_QCOM_GENI=y` | 内置 |
| UART6 (蓝牙) | `&uart6` | `CONFIG_SERIAL_QCOM_GENI=y` | 内置 |
| GENI SE | (qup) | `CONFIG_QCOM_GENI_SE=y` | 内置 |

### 14. 视频编解码

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| Venus 视频编解码器 | `&venus` | `CONFIG_VIDEO_QCOM_VENUS=y` | 内置 |

### 15. 网络加速

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| IPA 网络加速 | `&ipa` | `CONFIG_QCOM_IPA=y` | 内置 |

### 16. GPIO 按键/传感器

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| 音量键 | `gpio-keys` (PM8998) | `CONFIG_KEYBOARD_GPIO=y` | 内置 |
| Alert Slider | `gpio-keys` (TLMM) | `CONFIG_KEYBOARD_GPIO=y` | 内置 |
| 霍尔传感器 | `gpio-keys` (TLMM) | `CONFIG_KEYBOARD_GPIO=y` | 内置 |
| PM8941 电源键 | (pm8998) | `CONFIG_INPUT_PM8941_PWRKEY=y` | 内置 |

### 17. I2C 总线

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| I2C QCOM GENI (所有I2C) | `&i2c3/4/10/12` | `CONFIG_I2C_QCOM_GENI=y` | 内置 |
| QUPv3 ID0/1 | `&qupv3_id_0/1` | `CONFIG_I2C_QUP=y` | 内置 |

### 18. 电源管理/调节器

| 硬件 | 设备树节点 | 内核配置 | 状态 |
|------|-----------|---------|------|
| RPMH 调节器 (PM8998) | `qcom,pm8998-rpmh-regulators` | `CONFIG_REGULATOR_QCOM_RPMH=y` | 内置 |
| RPMH 调节器 (PMI8998) | `qcom,pmi8998-rpmh-regulators` | `CONFIG_REGULATOR_QCOM_RPMH=y` | 内置 |
| RPMH 调节器 (PM8005) | `qcom,pm8005-rpmh-regulators` | `CONFIG_REGULATOR_QCOM_RPMH=y` | 内置 |
| 固定调节器 | `regulator-fixed` | `CONFIG_REGULATOR_FIXED_VOLTAGE=y` | 内置 |
| GPIO 调节器 | (regulator) | `CONFIG_REGULATOR_GPIO=y` | 内置 |

### 19. QCOM 基础设施

| 功能 | 内核配置 | 状态 |
|------|---------|------|
| RPMH | `CONFIG_QCOM_RPMH=y` | 内置 |
| RPMHPD | `CONFIG_QCOM_RPMHPD=y` | 内置 |
| SMEM | `CONFIG_QCOM_SMEM=y` | 内置 |
| SMP2P | `CONFIG_QCOM_SMP2P=y` | 内置 |
| SMSM | `CONFIG_QCOM_SMSM=y` | 内置 |
| GLINK RPM | `CONFIG_RPMSG_QCOM_GLINK_RPM=y` | 内置 |
| GLINK SMEM | `CONFIG_RPMSG_QCOM_GLINK_SMEM=y` | 内置 |
| SMD | `CONFIG_RPMSG_QCOM_SMD=y` | 内置 |
| AOSS QMP | `CONFIG_QCOM_AOSS_QMP=y` | 内置 |
| LLCC | `CONFIG_QCOM_LLCC=y` | 内置 |
| OCMEM | `CONFIG_QCOM_OCMEM=y` | 内置 |
| BAM DMA | `CONFIG_QCOM_BAM_DMA=y` | 内置 |
| PDC | `CONFIG_QCOM_PDC=y` | 内置 |
| CPR | `CONFIG_QCOM_CPR=y` | 内置 |
| Command DB | `CONFIG_QCOM_COMMAND_DB=y` | 内置 |
| SCM | `CONFIG_QCOM_SCM=y` | 内置 |
| SPMI | `CONFIG_SPMI=y` | 内置 |
| SPMI MSM PMIC ARB | `CONFIG_SPMI_MSM_PMIC_ARB=y` | 内置 |
| TSENS 温度传感器 | `CONFIG_QCOM_TSENS=y` | 内置 |
| SPMI ADC5 | `CONFIG_QCOM_SPMI_ADC5=y` | 内置 |
| SPMI VADC | `CONFIG_QCOM_SPMI_VADC=y` | 内置 |
| SPMI TEMP ALARM | `CONFIG_QCOM_SPMI_TEMP_ALARM=y` | 内置 |
| SPMI RRADC | `CONFIG_QCOM_SPMI_RRADC=y` | 内置 |
| IRQ Combiner | `CONFIG_QCOM_IRQ_COMBINER=y` | 内置 |
| SoC 硬件随机数 (`/dev/hwrng`, `rng@793000`) | `CONFIG_HW_RANDOM_QCOM=y` | 内置 |
| APSS 看门狗 (`watchdog@17980000`) | `CONFIG_QCOM_WDT=y` | 内置 |
| PM8998 PON (`/sys/power/{state,restart}`) | `CONFIG_POWER_RESET_QCOM_PON=y` | 内置 |

### 20. 固件加载

| 功能 | 内核配置 | 状态 |
|------|---------|------|
| 固件压缩加载 | `CONFIG_FW_LOADER_COMPRESS=y` | 内置 |
| XZ 解压 | `CONFIG_FW_LOADER_COMPRESS_XZ=y` | 内置 |
| ZSTD 解压 | `CONFIG_FW_LOADER_COMPRESS_ZSTD=y` | 内置 |

### 21. Pstore/Ramoops

| 功能 | 内核配置 | 状态 |
|------|---------|------|
| Pstore | `CONFIG_PSTORE=y` | 内置 |
| Ramoops | `CONFIG_PSTORE_RAM=y` | 内置 |

---

## 固件文件

OnePlus 6 专用固件位于 `kernel/firmware/qcom/sdm845/OnePlus/enchilada/`:

| 文件 | 用途 |
|------|------|
| `mba.mbn` | Modem Boot Authenticator |
| `modem.mbn` | Modem 固件 |
| `adsp.mbn` | ADSP (音频DSP) 固件 |
| `cdsp.mbn` | CDSP (计算DSP) 固件 |
| `slpi.mbn` | SLPI (传感器DSP) 固件 |
| `venus.mbn` | Venus 视频编解码器固件 |
| `a630_zap.mbn` | Adreno 630 GPU Zap Shader |
| `ipa_fws.mbn` | IPA 网络加速固件 |
| `wlanmdsp.mbn` | WiFi 固件 |
| `adspr.jsn` / `adspua.jsn` | ADSP JSON 配置 |
| `cdspr.jsn` | CDSP JSON 配置 |
| `modemr.jsn` / `modemuw.jsn` | Modem JSON 配置 |
| `slpir.jsn` / `slpius.jsn` | SLPI JSON 配置 |

---

## 内核补丁

| 补丁文件 | 说明 |
|---------|------|
| `kernel/patches/adreno_opencl.patch` | Adreno 6xx OpenCL 兼容性补丁 (CHIP ID 映射、优先级、频率修复) |

---

## 配置变更历史

### 2026-10-09: 修正文档旧符号名 + 加装配置断言

**背景**：`oneplus6_defconfig` 被一份 7.0.0 时代的旧 `.config` 重新生成，olddefconfig 不会把改名
符号的旧值搬到新符号上，于是三项静默掉成 `=n`（构建/启动都不报错）：

| 掉的开关 | 影响 | 现已恢复 |
|---------|------|---------|
| `CONFIG_INPUT_QCOM_PMI8998_HAPTICS` | 振动/触觉反馈 | `=y` ✅ |
| `CONFIG_VIDEO_LC89821X` | 前后摄对焦 + OIS 马达 | `=y` ✅ |
| `CONFIG_HW_RANDOM_QCOM` | SoC 硬件随机数 `/dev/hwrng` | `=y` ✅ |

**本文件同步修正的旧符号名/旧取值**：
- `CONFIG_INPUT_QCOM_SPMI_HAPTICS` → `CONFIG_INPUT_QCOM_PMI8998_HAPTICS`（7.2.0 改名）
- `CONFIG_VIDEO_LC898217XC` → `CONFIG_VIDEO_LC89821X`（改名）
- 删除 `CONFIG_RMI4_F01`（本树无此符号）
- `CONFIG_LEDS_QCOM_FLASH` 由 `=y` 改为实际的 `=m`（tristate 上限，见 §12）
- `CONFIG_WCD9335` 标为未启用；音频相关 5 项由 `=m` 更正为实际的 `=y`
- 补充 `CONFIG_HW_RANDOM_QCOM` 一行

**新增防回归机制**：
- `kernel/configs/oneplus6/required_config.conf` — 119 条关键开关断言（114 项必须 `=y`，5 项须已编出）
- `tools/build/check_defconfig.sh` — 核对任意 `.config`，缺项非零退出
- `tools/build/build_kernel.sh` — 编译前自动核对 `build/out/.config`，缺项即中止构建

### 2026-10-09: 看门狗与 PON 改内置 + 启动路径自动校验

**背景**：连续几次刷机掉进 fastboot（6.16 / 7.1 分支正常）。这类失败的共同特征是
**零报错**，而 `/sys/power/{state,restart}` 与 ABL 跳内核那一跳恰恰是"静默复位"的重灾区。

| 改动 | 原值 | 新值 | 理由 |
|------|------|------|------|
| `CONFIG_QCOM_WDT` | `=m` | `=y` | ABL 若已在跳内核前启动 APSS 看门狗，模块还没加载就没人喂 → SoC 被复位。`qcom_defconfig` 本来就是 `=y` |
| `CONFIG_POWER_RESET_QCOM_PON` | `=m` | `=y` | `/sys/power/{state,restart}` 全部走它 |

**验证**：容器内 `olddefconfig` 输出 `No change to .config`，`diff` 新旧 CONFIG 行
**0 差异**——没有级联改动，也没有别的开关被丢。

**本文件同步修正的节点名错误**（照抄 label 前没查源，都错的）：
- `&labibb` → `labibb`：`pmi8998.dtsi:96` 那个节点**根本没有 label**，不能用 `&` 引用
- `&slimbus` → `&slim`（2 处）：NGD 控制器的 label 是 `slim`，写在
  `sdm845.dtsi:4078`，由 `sdm845-wcd9340.dtsi` 重新打开
- §19 补 APSS 看门狗、PM8998 PON 两行

**新增防回归机制**：
- `tools/build/check_boot_path.py` — 打包前核对启动关键路径 66 项必须内置，缺项 `exit 1`
- `tools/build/build_bootimg.sh` — 打包前自动调用上面这个检查

> **改完这两个符号必须重建内核才会生效**：
> `./tools/build/build_kernel.sh && ./tools/build/build_bootimg.sh && ./flash.sh`

### 2026-05-26: 硬件配置优化

**新增启用:**
- `CONFIG_SND_SOC_QDSP6_Q6VOICE=y` - 语音通话支持
- `CONFIG_BT_RFCOMM=m` - 蓝牙串口协议
- `CONFIG_BT_BNEP=m` - 蓝牙网络封装
- `CONFIG_FW_LOADER_COMPRESS_ZSTD=y` - ZSTD 固件解压支持

**模块改内置 (=m → =y):**
- `CONFIG_QCOM_RMTFS_MEM` - Modem 启动依赖
- `CONFIG_SND_SOC_SDM845` - 音频声卡
- `CONFIG_SND_SOC_WCD934X` - WCD9340 编解码器
- `CONFIG_SND_SOC_TFA98XX` - TFA98XX 音频放大器
- `CONFIG_QCOM_APR` - 音频包路由
- `CONFIG_RPMSG_QCOM_GLINK_SMEM` - remoteproc 通信
- `CONFIG_SDM_CAMCC_845` - 相机时钟控制器
- `CONFIG_QCOM_IPA` - 网络加速
- `CONFIG_VIDEO_QCOM_VENUS` - 视频编解码
- `CONFIG_LEDS_QCOM_FLASH` - 闪光灯
- `CONFIG_LEDS_QCOM_LPG` - RGB 通知灯
- `CONFIG_QCOM_PMIC_GLINK` - PMIC GLINK 通信
- `CONFIG_BATTERY_QCOM_BATTMGR` - 电池管理
- `CONFIG_ATH10K_SNOC` - WiFi SNOC 总线
- `CONFIG_NFC_NXP_NCI` - NFC 核心
- `CONFIG_NFC_NXP_NCI_I2C` - NFC I2C 传输
- `CONFIG_VIDEO_QCOM_CAMSS` - 摄像头子系统
- `CONFIG_VIDEOBUF2_CORE` - Videobuf2 核心
- `CONFIG_VIDEOBUF2_MEMOPS` - Videobuf2 内存操作
- `CONFIG_VIDEOBUF2_DMA_SG` - Videobuf2 DMA SG

**依赖链修复 (=m → =y，防止 Kconfig 降级):**
- `CONFIG_NFC=y` - NFC 核心 (NFC_NCI 依赖)
- `CONFIG_NFC_NCI=y` - NCI 协议 (NFC_NXP_NCI 依赖)
- `CONFIG_SLIMBUS=y` - SLIMBus 总线 (MFD_WCD934X 依赖)
- `CONFIG_MFD_WCD934X=y` - WCD9340 MFD 核心 (SND_SOC_WCD934X 依赖)
- `CONFIG_SOUNDWIRE=y` - SoundWire 总线 (SDM845 声卡和 WCD934X 依赖)
- `CONFIG_SND_SOC_QDSP6=y` - QDSP6 核心 (Q6VOICE 依赖)
- `CONFIG_QCOM_PBS=y` - PBS 支持 (LEDS_QCOM_LPG 依赖)
- `CONFIG_TYPEC=y` - USB Type-C (QCOM_PMIC_GLINK 依赖)
- `CONFIG_LEDS_CLASS_MULTICOLOR=y` - LED 多色 (LEDS_QCOM_LPG 依赖)
- `CONFIG_SND_SOC_QCOM=y` - QCOM 音频核心 (SDM845 声卡依赖)
- `CONFIG_SND=y` / `CONFIG_SOUND=y` - 音频核心链

**禁用非 OP6 硬件驱动 (精简约 150 项):**
- 禁用 9 个非 SDM845 架构 (Apple/MediaTek/Meson/Renesas/Rockchip/Tegra/UniPhier/Visconti/ZynqMP)
- 禁用 21 个非 OP6 面板驱动
- 禁用 72 个非 Qualcomm 音频驱动和非 SDM845 QCOM 声卡
- 禁用 46 个非 SDM845 Pin Controller
- 禁用 39 个非 Qualcomm 视频/VPU 驱动
- 禁用 32 个非 SDM845 I2C/SPI/PCIe/时钟/杂项驱动
- 禁用 TFA98XX (6T 专用扬声器驱动，OP6 用 MAX98927)
- 禁用 5 个非 OP6 摄像头传感器和 2 个 Samsung NFC

**关键启动配置修复 (=m → =y):**
- `CONFIG_BT=y` - 蓝牙核心
- `CONFIG_BT_HCIUART=y` - 蓝牙 UART 驱动
- `CONFIG_USB_CONFIGFS=y` - USB Gadget ConfigFS
- `CONFIG_TYPEC_QCOM_PMIC=y` - Type-C PMIC 检测
- `CONFIG_LEDS_QCOM_FLASH=y` - 闪光灯 LED
- `CONFIG_QCOM_BAM_DMUX=y` - BAM 数据多路复用

**效果:**
- Image.gz: 18.8M → 17.5M (-7%)
- 内核模块: 1424 → 1043 (-27%)
