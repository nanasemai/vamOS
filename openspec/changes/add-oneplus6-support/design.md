## Context

一加6（OnePlus 6，codename enchilada）和一加6T（codename fajita）是基于高通骁龙845（SDM845）处理器的智能手机。与 comma 3/3X 使用相同的 SoC，这为 vamOS 移植提供了良好的硬件基础。

### 硬件配置对比

| 组件 | OnePlus 6 | comma 3/3X |
|------|-----------|-----------|
| SoC | Qualcomm Snapdragon 845 | Qualcomm Snapdragon 845 |
| CPU | 8 cores (4x Kryo 385 Gold @ 2.8GHz, 4x Kryo 385 Silver @ 1.8GHz) | 相同 |
| GPU | Adreno 630 | 相同 |
| 内存 | 6/8GB LPDDR4X | 6GB |
| 存储 | 64/128/256GB UFS 2.1 | UFS |
| 前置相机 | Sony IMX371 (16MP) | 类似 |
| 后置主摄 | Sony IMX519 (48MP) | 不同 |
| 后置广角 | Sony IMX376K (16MP) | 不同 |

## Goals / Non-Goals

### Goals
- 支持一加6/6T 设备启动 vamOS
- 支持三个摄像头（前置 IMX371、后置 IMX519、后置广角 IMX376K）
- 支持自动对焦功能（LC898217XC）
- 保持与现有 comma 设备配置的隔离
- 提供独立的构建目标

### Non-Goals
- 不支持指纹识别（openpilot 不需要）
- 不支持快充功能（后续可添加）
- 不修改现有 comma 设备的配置

## Decisions

### Decision 1: 使用专用内核分支而非补丁方式
- **理由**: 将 kernel/linux 子模块替换为 nanasemai/sdm845-next (sdm845-next-oneplus6 分支)，该分支已包含完整的一加6/6T支持，包括：
  - 摄像头传感器驱动（IMX371、IMX376K、IMX519）
  - 自动对焦驱动（LC898217XC）
  - 设备树配置文件
  - SDM845平台完整配置
- **优势**: 避免手动移植驱动的复杂性，直接使用经过验证的配置

### Decision 2: 创建独立的设备配置目录
- **理由**: 将一加6的配置与现有 comma 设备分离，避免冲突，便于维护。
- **实现**: 
  - kernel/configs/oneplus6/ - 配置文件
  - kernel/dts/sdm845-oneplus-*.dts - 设备树
  - kernel/patches/oneplus6/ - 专用补丁

### Decision 3: 使用模块化驱动配置
- **理由**: 摄像头驱动作为模块编译，减少内核体积，便于调试。
- **配置**:
  - CONFIG_VIDEO_IMX371=m
  - CONFIG_VIDEO_IMX376=m
  - CONFIG_VIDEO_IMX519=m
  - CONFIG_VIDEO_LC898217XC=m

### Decision 4: 复用现有的构建框架
- **理由**: 保持构建流程一致，减少学习成本。
- **实现**: 创建 build_kernel_oneplus6.sh 脚本，复用现有 Docker 构建环境。

## Risks / Trade-offs

### 风险 1: 驱动兼容性问题
- **描述**: IMX371/IMX376K/IMX519 驱动在 Linux 6.18 上可能存在 API 兼容性问题
- **缓解措施**: 仔细分析驱动代码，必要时进行适配；先在 Linux 7.0 上验证驱动功能

### 风险 2: 设备树兼容性
- **描述**: 一加6设备树可能与现有 comma 设备树存在冲突
- **缓解措施**: 创建独立的设备树文件，不修改现有配置

### 风险 3: 固件缺失
- **描述**: 缺少相机固件可能导致相机无法正常工作
- **缓解措施**: 用户后续提供固件后再进行相机功能测试

### 风险 4: 构建复杂性增加
- **描述**: 多设备支持增加了构建系统的复杂性
- **缓解措施**: 使用清晰的目录结构和独立的构建脚本

## Migration Plan

### 实施步骤
1. **阶段1**: 准备配置文件和设备树（独立于现有代码）
2. **阶段2**: 添加驱动补丁
3. **阶段3**: 创建构建脚本
4. **阶段4**: 测试构建
5. **阶段5**: 设备测试

### 回滚计划
- 如果出现严重问题，可简单删除 oneplus6 相关目录，恢复原有配置

## Open Questions

1. 是否需要支持一加6T（fajita）？两者硬件相似，但有一些差异
2. 是否需要创建单独的刷机脚本？
3. 相机固件的提供方式和位置？