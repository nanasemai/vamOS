# AI 助手指引 (Trae)

**本文件为 Trae AI 专用入口。**

---

## ⚠️ 语言要求

- **必须使用中文**与用户交流

---

## 快速索引

| 需要了解 | 去哪里 |
|----------|--------|
| 项目概述、构建命令 | [.trae/rules/project_rules.md](.trae/rules/project_rules.md) |

---

## 核心规则

1. **不要推送到非 origin 仓库** - 只推送到 origin (你自己的 fork)
2. **提交前必须获得用户批准**
3. **内核修改后需要重新构建测试**

---

## 常见命令

```bash
# 克隆仓库
git clone https://github.com/commaai/vamOS.git
cd vamOS

# 初始化子模块
git submodule update --init --depth 1

# 构建内核
./tools/vamos build kernel

# 构建系统
./tools/vamos build system
```