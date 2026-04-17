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
- 创建独立的构建脚本支持一加6设备
- **非破坏性变更**：不修改现有 comma 设备的配置

## Impact

- 受影响的规范: specs/device-support/spec.md
- 受影响的代码: 
  - kernel/configs/ - 新增 oneplus6 配置
  - kernel/dts/ - 新增一加6设备树文件
  - kernel/patches/ - 新增摄像头驱动补丁目录
  - tools/build/ - 新增构建脚本补丁
- 新增目录:
  - kernel/patches/oneplus6/ - 一加6专用补丁
  - kernel/configs/oneplus6/ - 一加6配置文件