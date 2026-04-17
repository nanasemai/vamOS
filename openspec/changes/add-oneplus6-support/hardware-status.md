# OnePlus 6 硬件支持状态

## 设备信息

| 属性 | 规格 |
|------|------|
| 设备名称 | OnePlus 6 (enchilada) / OnePlus 6T (fajita) |
| SoC | Qualcomm Snapdragon 845 (SDM845) |
| CPU | 4x Kryo 385 Gold @ 2.8GHz + 4x Kryo 385 Silver @ 1.8GHz |
| GPU | Adreno 630 |
| 内存 | 6/8GB LPDDR4X |
| 存储 | 64/128/256GB UFS 2.1 |

## 硬件支持状态

### 核心组件
- [x] UFS 存储 - SDM845 原生支持
- [x] 显示 - Adreno 630 DRM/KMS
- [x] GPU - Adreno 630 加速
- [x] USB - SDM845 原生支持
- [x] 调制解调器 - 需固件支持
- [x] SPI - SDM845 原生支持
- [ ] I2C (IMU/温度传感器...)
- [ ] GPS
- [ ] 声音

### 摄像头（内核驱动已包含在 sdm845-next-oneplus6 分支中）
- [x] IMX371 (前置 16MP)
  - [x] 内核驱动 - 已包含在内核分支
  - [ ] ISP 配置
  - [ ] openpilot 集成
- [x] IMX519 (后置主摄 48MP)
  - [x] 内核驱动 - 已包含在内核分支
  - [ ] ISP 配置
  - [ ] openpilot 集成
- [x] IMX376K (后置广角 16MP)
  - [x] 内核驱动 - 已包含在内核分支
  - [ ] ISP 配置
  - [ ] openpilot 集成
- [x] LC898217XC (自动对焦)
  - [x] 内核驱动 - 已包含在内核分支

### 网络
- [x] WiFi - QCA6174（需固件）
- [x] 蓝牙 - 需固件支持
- [ ] 蜂窝网络

### 传感器
- [ ] 加速度计
- [ ] 陀螺仪
- [ ] 磁力计
- [ ] 距离传感器
- [ ] 光线传感器

### 其他
- [ ] 指纹识别（openpilot 不需要）
- [ ] 快充功能
- [ ] Venus (视频编解码)
- [ ] OpenCL - via rusticl / msm_drm

## 驱动来源

| 组件 | 驱动位置 | 状态 |
|------|----------|------|
| IMX371 | linux-kernel-7.0/drivers/media/i2c/imx371.c | 主线已合并 |
| IMX376K | linux-kernel-7.0/drivers/media/i2c/imx376.c | 主线已合并 |
| IMX519 | linux-kernel-7.0/drivers/media/i2c/imx519.c | 主线已合并 |
| LC898217XC | linux-kernel-7.0/drivers/media/i2c/lc898217xc.c | 主线已合并 |

## 依赖项

### 固件（待提供）
- [ ] WiFi 固件 (QCA6174)
- [ ] 蓝牙固件
- [ ] 调制解调器固件
- [ ] 摄像头固件
- [ ] 显示固件

### 配置文件
- [x] 内核配置参考 - linux-kernel-7.0/arch/arm64/configs/oneplus6-7.0.defconfig
- [x] 设备树参考 - linux-kernel-7.0/arch/arm64/boot/dts/qcom/sdm845-oneplus-common.dtsi

## 兼容性说明

### 与 comma 3/3X 共享组件
- [x] SDM845 SoC 核心支持
- [x] Adreno 630 GPU
- [x] UFS 存储驱动
- [x] USB 驱动
- [x] 部分电源管理

### 一加6专属组件
- [ ] IMX371/IMX376K/IMX519 摄像头
- [ ] LC898217XC 自动对焦
- [ ] 特定电源调节器配置
- [ ] 特定 GPIO 配置

## 风险评估

| 风险 | 级别 | 描述 | 缓解措施 |
|------|------|------|----------|
| 摄像头驱动兼容性 | 高 | 驱动在 6.18 上可能存在 API 差异 | 从主线提取并适配 |
| 固件缺失 | 高 | 缺少相机等固件 | 用户后续提供 |
| 设备树冲突 | 中 | 与现有配置可能冲突 | 创建独立设备树 |
| 构建复杂性 | 低 | 多设备支持增加复杂度 | 使用独立配置目录 |