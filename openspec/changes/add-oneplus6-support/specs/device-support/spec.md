## ADDED Requirements

### Requirement: 一加6设备支持
系统 SHALL 支持 OnePlus 6 (enchilada) 和 OnePlus 6T (fajita) 设备运行 vamOS。

#### Scenario: 一加6内核构建成功
- **WHEN** 使用 oneplus6 配置构建内核
- **THEN** 生成支持一加6硬件的 boot.img

#### Scenario: 一加6设备树编译
- **WHEN** 构建内核时指定一加6设备树
- **THEN** 正确编译 sdm845-oneplus-enchilada.dtb 和 sdm845-oneplus-fajita.dtb

### Requirement: 一加6摄像头支持
系统 SHALL 支持一加6的三个摄像头传感器：IMX371（前置）、IMX519（后置主摄）、IMX376K（后置广角）。

#### Scenario: IMX371前置摄像头识别
- **WHEN** 系统启动时
- **THEN** 检测到 Sony IMX371 前置摄像头并创建 /dev/video 设备节点

#### Scenario: IMX519后置摄像头识别
- **WHEN** 系统启动时
- **THEN** 检测到 Sony IMX519 后置主摄并创建 /dev/video 设备节点

#### Scenario: IMX376K广角摄像头识别
- **WHEN** 系统启动时
- **THEN** 检测到 Sony IMX376K 后置广角摄像头并创建 /dev/video 设备节点

### Requirement: 自动对焦支持
系统 SHALL 支持 LC898217XC 自动对焦驱动。

#### Scenario: 自动对焦驱动加载
- **WHEN** 摄像头初始化时
- **THEN** LC898217XC 自动对焦驱动正确加载并绑定到摄像头

### Requirement: 独立设备配置
一加6设备配置 SHALL 独立于现有 comma 设备配置，不相互影响。

#### Scenario: 独立构建目标
- **WHEN** 执行 `./vamos build kernel --device=oneplus6`
- **THEN** 使用一加6专属配置构建，不影响 comma 设备构建

#### Scenario: 配置隔离
- **WHEN** 修改一加6配置文件
- **THEN** 不影响 comma 3/3X 的配置