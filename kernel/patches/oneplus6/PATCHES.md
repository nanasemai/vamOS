# OnePlus 6 专用补丁目录

此目录存放一加6设备专属的内核补丁。

## 补丁命名规则

遵循项目统一的命名规范：
```
NNNN-SUBSYSTEM-description.patch
```

- `NNNN` — 序列号（从 0001 开始）
- `SUBSYSTEM` — 修改的内核子系统：
  - `defconfig` — 内核配置
  - `dts` — 设备树
  - `driver` — 驱动
  - `core` — 核心子系统
- `description` — 简短描述（kebab-case）

## 补丁列表

| 补丁文件 | 描述 | 状态 |
|----------|------|------|
| 0001-driver-add-imx371.patch | 添加 IMX371 摄像头驱动 | 待创建 |
| 0002-driver-add-imx376.patch | 添加 IMX376K 摄像头驱动 | 待创建 |
| 0003-driver-add-imx519.patch | 添加 IMX519 摄像头驱动 | 待创建 |
| 0004-driver-add-lc898217xc.patch | 添加 LC898217XC 自动对焦驱动 | 待创建 |
| 0005-dts-oneplus-common.patch | 添加一加6通用设备树 | 待创建 |
| 0006-dts-oneplus-enchilada.patch | 添加一加6设备树 | 待创建 |
| 0007-dts-oneplus-fajita.patch | 添加一加6T设备树 | 待创建 |
| 0008-defconfig-oneplus6.patch | 添加一加6内核配置 | 待创建 |

## 开发工作流

### 1. 在子模块中开发

```bash
cd kernel/linux
# 进行修改...
git status
```

### 2. 提取补丁

```bash
cd kernel/linux
git diff > ../patches/oneplus6/000X-subsystem-description.patch
```

### 3. 测试补丁

```bash
cd kernel/linux
git stash
git apply ../patches/oneplus6/*.patch
# 编译测试...
```

### 4. 重置子模块（清理修改）

```bash
cd kernel/linux
git checkout .
git clean -fd
```

## 补丁应用顺序

1. 首先应用 `kernel/patches/` 目录下的通用补丁
2. 然后应用 `kernel/patches/oneplus6/` 目录下的一加6专用补丁

## 注意事项

- 补丁按文件名顺序应用，请确保序列号正确
- 每个补丁应尽量独立，便于调试
- 避免修改现有通用补丁，如需修改应创建新补丁