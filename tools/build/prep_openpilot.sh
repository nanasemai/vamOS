#!/usr/bin/env bash
set -euo pipefail

# 把 openpilot 源码供应进 rootfs 构建上下文，落到 /data/openpilot。
#
# 为什么这一步是必需的
# -------------------
# userspace/uv/pyproject.toml 里 openpilot 的来源是 { path = "openpilot" }，
# 指向 userspace/uv/openpilot/ —— 那里**只有一个 pyproject.toml**
# （由 tools/sync/openpilot.sh 从远端拉下来、在 [tool.uv.sources] 处截断），
# 没有任何代码。注释写得很直白：
#
#   # openpilot's submodules, for their dependencies. the code comes from
#   # /data/openpilot via PYTHONPATH on device.
#
# 也就是说：`uv sync` 只负责把 openpilot 的**依赖**装进 /usr/local/venv，
# 代码本体从来不在镜像里。设备上期望它在 /data/openpilot。
#
# 本仓库里**没有任何地方**引用过源码路径 —— grep 'dragonpilot_nana' 全仓库零命中，
# rootfs 覆盖层里也没有 launch_openpilot.sh / chffrplus。所以这一步之前是缺失的：
# 刷上去能开机、能进 SSH，但 openpilot 没有任何代码可跑。
#
# 用法
# ----
#   OPENPILOT_SRC=/path/to/openpilot  ./tools/build/prep_openpilot.sh
#   # 默认 /home/ubuntu/openpilot_oneplus/dragonpilot_nana
#
# 幂等：每次全量重拷（先删旧目录），并写一份 manifest 记录来源 commit。
#
# 产物被 .gitignore 掉（userspace/root/data/openpilot/），不进版本库。
# 镜像会因此变大（核心模型 ~68MB + 源码 ~150MB），ROOTFS_IMAGE_SIZE=6G 够放。

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)"

SRC="${OPENPILOT_SRC:-/home/ubuntu/openpilot_oneplus/dragonpilot_nana}"
DEST="${OPENPILOT_DEST:-$DIR/userspace/root/data/openpilot}"

# ---- 前置校验 ------------------------------------------------------------
if [ ! -d "$SRC" ]; then
  echo "ERROR: openpilot 源码不存在: $SRC" >&2
  echo "  用 OPENPILOT_SRC=/path/to/openpilot 指定" >&2
  exit 1
fi

# 必须是真 openpilot 树：有 pyproject.toml 且可构建包名是 openpilot。
# 防的是把任意目录拷进去、然后在设备上以「代码存在」的假象静默失败。
if [ ! -f "$SRC/pyproject.toml" ]; then
  echo "ERROR: $SRC 里没有 pyproject.toml，不像是 openpilot 树" >&2
  exit 1
fi
grep -q '^name = "openpilot"' "$SRC/pyproject.toml" || {
  echo "ERROR: $SRC/pyproject.toml 的 name 不是 openpilot" >&2
  echo "  实际: $(grep -m1 '^name' "$SRC/pyproject.toml")" >&2
  exit 1
}

# selfdrive/ 在根目录（fork 用 openpilot/ -> ../selfdrive 的符号链接扇出）。
if [ ! -d "$SRC/selfdrive" ]; then
  echo "ERROR: $SRC/selfdrive 不存在" >&2
  exit 1
fi

# 核心模型必须在位且是完整文件。modeld 没有这些就起不来。
for m in driving_vision.onnx driving_policy.onnx dmonitoring_model.onnx; do
  f="$SRC/selfdrive/modeld/models/$m"
  if [ ! -s "$f" ]; then
    echo "ERROR: 缺模型 $f" >&2
    echo "  如果是 git-lfs 分片，目录里会有 $m.chunkNNofNN + chunkmanifest，" >&2
    echo "  需要先重组（git lfs pull），不能用分片启动。" >&2
    exit 1
  fi
done

# ---- 拷入 -----------------------------------------------------------------
echo "Preparing openpilot from $SRC"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"

# 为什么用 rsync 而不是 cp
# ------------------------
# GNU cp 9.4 **没有** --exclude 选项（那是 rsync 的），所以排除只能靠"先全拷
# 再删"，而 .git + .venv 有 2.2G，白拷一遍浪费时间和空间。rsync 两个都有。
# 必须带 -a（保留符号链接）：这个 fork 的 openpilot/ 是符号链接扇出
#   openpilot/selfdrive -> ../selfdrive/
#   openpilot/system    -> ../system/
# 相对目标在拷贝内部依然可解析，所以拷完仍然有效。丢掉 -a 会把链接变成实拷贝
# 或断链，import openpilot.selfdrive 直接失败。
if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: 需要 rsync（GNU cp 没有 --exclude）" >&2
  exit 1
fi

rsync -a \
  --exclude='.git/' \
  --exclude='.venv/' \
  --exclude='.gitignore' \
  --exclude='__pycache__/' \
  --exclude='*.chunk*' \
  --exclude='.ruff_cache/' \
  --exclude='.mypy_cache/' \
  --exclude='.pytest_cache/' \
  --exclude='.idea/' \
  --exclude='.vscode/' \
  "$SRC/" "$DEST/"

# ---- manifest ------------------------------------------------------------
REF="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo 'not-a-git-repo')"
REMOTE="$(git -C "$SRC" config --get remote.origin.url 2>/dev/null || echo unknown)"
DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
  echo "openpilot_repo=$REMOTE"
  echo "openpilot_ref=$REF"
  echo "built=$DATE"
} > "$DEST/.openpilot-manifest"

BYTES=$(du -sh "$DEST" | cut -f1)
COUNT=$(find "$DEST" -type f | wc -l)
echo "[OK] $COUNT 个文件 / $BYTES -> $DEST"
echo "[OK] manifest:"
sed 's/^/       /' "$DEST/.openpilot-manifest"
