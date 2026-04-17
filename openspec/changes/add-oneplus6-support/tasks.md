## 1. 准备工作
- [x] 1.1 将 kernel/linux 子模块更新为 nanasemai/sdm845-next (sdm845-next-oneplus6 分支)
- [x] 1.2 该分支已包含完整的一加6/6T支持：
  - 设备树配置（sdm845-oneplus-common.dtsi、enchilada.dts、fajita.dts）
  - 摄像头驱动（IMX371、IMX376K、IMX519）
  - 自动对焦驱动（LC898217XC）

## 2. 内核配置准备
- [x] 2.1 创建 kernel/configs/oneplus6/ 目录 - 已创建
- [x] 2.2 从内核子模块复制 oneplus6.config 配置文件
- [x] 2.3 摄像头和SDM845平台支持已在内核分支中配置

## 3. 设备树配置
- [x] 3.1-3.7 设备树文件已包含在内核子模块中（sdm845-oneplus-*.dts）

## 4. 驱动补丁准备
- [x] 4.1-4.5 所有驱动已包含在内核子模块中，无需额外补丁

## 5. 构建脚本修改
- [x] 5.1 创建 tools/build/build_kernel_oneplus6.sh - 已创建
- [x] 5.2 添加一加6设备树到构建目标 - 脚本已配置
- [x] 5.3 更新 vamos 主脚本支持 oneplus6 构建目标
- [x] 5.4 创建 tools/flash/kernel_fastboot.sh - 一加6专用fastboot刷写脚本
- [x] 5.5 更新 vamos 添加 fastboot 命令支持
- [x] 5.6 添加一加6内核固件文件 (firmware/qcom/sdm845/oneplus6/)
- [ ] 5.7 测试构建流程

## 6. 测试验证
- [ ] 6.1 验证内核编译成功
- [ ] 6.2 验证 boot.img 生成
- [ ] 6.3 设备测试（相机功能验证）
- [ ] 6.4 性能测试和稳定性测试

## 7. 文档更新
- [ ] 7.1 更新 openspec/vamOS-analysis.md 添加一加6支持说明
- [ ] 7.2 更新 project.md 添加一加6设备信息
- [ ] 7.3 添加移植文档

## 8. 代码审查和合并
- [ ] 8.1 提交代码审查
- [ ] 8.2 根据反馈修改
- [ ] 8.3 合并到主分支