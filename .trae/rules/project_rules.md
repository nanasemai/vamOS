# vamOS 项目规则

## 项目概述

vamOS 是一个用于构建车载 Linux 发行版的项目，专为 comma 设备（如 comma 3/3X）设计。

## 构建命令

### 首次设置环境
```bash
# 克隆仓库
git clone https://github.com/commaai/vamOS.git
cd vamOS

# 初始化子模块
git submodule update --init --depth 1
```

### 构建内核
```bash
# 构建 Linux 内核
./tools/vamos build kernel

# 构建产物位于 output/ 目录
# - boot.img: 启动镜像
# - Image.gz-dtb: 内核+设备树合并镜像
```

### 构建系统
```bash
# 构建完整 vamOS 系统
./tools/vamos build system

# 构建产物为 Docker 镜像或文件系统
```

### 烧录
```bash
# 烧录内核到设备
./tools/vamos flash kernel

# 烧录系统镜像
./tools/vamos flash system
```

## 代码规范

### Shell 脚本规范
- 使用 `set -e` 确保脚本在任何命令失败时退出
- 使用 `$(command)` 而不是反引号
- 变量引用使用 `${var}` 而不是 `$var`
- 函数定义使用 `function_name()` 而不是 `function function_name`

**正确示例：**
```bash
#!/usr/bin/env bash
set -e

function build_kernel() {
    local defconfig="${1}"
    make "${defconfig}" -j$(nproc)
}
```

### Python 规范
- 2 空格缩进
- 行长度：160 字符
- 使用 ruff 进行 lint 和格式化

### 内核配置规范
- 使用设备特定的 defconfig 作为基础配置
- 配置项使用 `CONFIG_xxx=y` 或 `CONFIG_xxx=m` 格式
- 禁用不需要的硬件：`CONFIG_xxx=n`

## Git 工作流

### 远程仓库
- **origin** = 用户自己的 fork
- **upstream** = 原始仓库 - **不要推送到这里**

### 重要规则
- **永远不要推送到 upstream**
- 只能推送到 **origin**
- 推送前等待用户的明确批准

### Git 提交操作

**重要规则：所有 Git 提交备注必须使用中文。**

**重要规则：每次提交代码前必须获得用户的明确批准。**

#### 提交前检查清单
- [ ] 代码已通过格式检查
- [ ] 更改已测试
- [ ] 用户已明确批准提交

#### 提交信息格式
```
<类型>: <简短描述>

[可选的详细描述]
```

**类型包括：**
- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档更新
- `refactor`: 代码重构
- `build`: 构建相关
- `chore`: 其他维护工作

#### 提交命令
```bash
# 1. 查看更改
git status
git diff

# 2. 添加更改的文件
git add <文件名>

# 3. 提交（使用 -s 添加签名）
git commit -s -m "feat: 添加新功能"

# 4. 推送到 origin（需要用户批准）
git push origin <分支名>
```

#### 分支管理
- 从 `main` 分支创建功能分支
- 分支命名：`feature/<功能描述>` 或 `fix/<问题描述>`
- 完成工作后创建 PR 请求合并

## 项目架构

### 核心目录

- **kernel/linux/**：Linux 内核源码

- **userspace/**：用户空间文件系统
  - `root/`：根文件系统
  - `base_setup.sh`：基础设置脚本

- **firmware/**：设备固件

- **tools/**：工具
  - `build/`：构建相关工具
  - `flash/`：烧录脚本
  - `vamos`：主工具脚本

## 重要约束

- 内核构建必须使用正确的 defconfig
- 设备树必须与硬件匹配
- 分区操作需要谨慎，可能导致设备变砖
- 固件必须完整，否则部分功能无法工作

## 领域上下文

- 嵌入式 Linux 系统构建
- 车载设备移植
- 硬件驱动适配
- 文件系统构建和烧录