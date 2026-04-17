# 项目上下文

## 目的

vamOS 是一个用于构建车载 Linux 发行版的项目，专为 comma 设备（如 comma 3/3X）设计。

## 技术栈

- Bash (构建脚本)
- Python (辅助工具)
- Docker (系统镜像构建)
- Linux Kernel (主线内核)
- GCC/Clang (交叉编译工具链)

## 项目约定

### Shell 脚本风格
- 使用 `set -e` 确保错误时退出
- 使用 `$(command)` 而不是反引号
- 变量引用使用 `${var}` 格式
- 函数定义简洁明了

### Git 工作流
- Fork：`origin` = 用户自己的 fork
- Upstream：`upstream` = 原始仓库
- 从 `main` 分支创建功能分支

### 时间戳规范
- 所有文档中的日期必须使用 **人类可读日期 + Unix 时间戳** 格式
- 格式：`## 2026-03-12 15:30 (1773285905)`
  - `2026-03-12 15:30` 为人类可读日期时间
  - `(1773285905)` 为 Unix 时间戳，供 AI 排序/查找使用
- 获取时间戳：`date +%s`

## 领域上下文

- 嵌入式 Linux 系统构建
- 车载设备 Linux 移植
- 硬件驱动适配
- ARM64 架构交叉编译
- 设备树配置

## 重要约束

- 内核 defconfig 必须与目标设备匹配
- 设备树必须正确配置所有必要硬件
- 分区操作需要谨慎，可能导致设备变砖
- 固件必须完整才能确保硬件正常工作

## 外部依赖

- Linux 内核源码
- Docker (用于构建 rootfs)
- 交叉编译工具链
- 设备固件

## 关键文档

### 开发日志
- [DEV_LOG.md](./DEV_LOG.md) - 开发日志索引

### OpenSpec 变更管理
- [AGENTS.md](./AGENTS.md) - OpenSpec 规范驱动开发指南
- [changes/](./changes/) - 活跃变更提案

## 常见任务

### 构建内核
```bash
./tools/vamos build kernel
```

### 构建系统
```bash
./tools/vamos build system
```

### 烧录
```bash
./tools/vamos flash kernel
./tools/vamos flash system
```