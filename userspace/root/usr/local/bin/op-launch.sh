#!/usr/bin/env bash
# op-launch - 启动设备上 /data/openpilot 里的 openpilot
#
# 为什么需要这个
# --------------
# /data/openpilot 里的源码由 tools/build/prep_openpilot.sh 在构建 rootfs 时
# 拷进来（来源见 /data/openpilot/.openpilot-manifest）。
#
# 但 rootfs 里**没有任何东西**会去启动它。原厂的启动链是：
#   /usr/comma/comma.sh -> /usr/comma/setup -> /tmp/installer (ELF)
#                       -> /data/continue.sh -> launch_openpilot.sh
# 其中 /tmp/installer 是 Comma 的 provisioning ELF，负责把 openpilot 下载到
# /data/openpilot 并生成 continue.sh。本分支没有这个 ELF（见文档 §16.7），
# 所以链子在 "waiting for installer" 处卡死 —— 源码在，venv 在，就是没人拉它。
#
# 这个脚本就是那个缺失的一环，手动版本：
#   /usr/local/bin/op-launch.sh
#
# 刻意**不**做成 runit 服务、也刻意**不**写 /data/continue.sh：
# 是否开机自动拉起 openpilot（以及要不要绕过 setup UI）是产品行为，
# 不该由构建脚本替用户决定。想自动化就把它做成 /etc/sv/op/run，
# 或让 setup 流程生成 continue.sh 指向这里。
#
# 退出后回到 shell，不重定向：openpilot 的输出就是这次调试的全部信息。

set -u

OP_DIR="${OP_DIR:-/data/openpilot}"
VENV="${OP_VENV:-/usr/local/venv}"

if [ ! -x "$OP_DIR/launch_openpilot.sh" ]; then
  echo "ERROR: $OP_DIR/launch_openpilot.sh 不存在或不可执行" >&2
  if [ ! -d "$OP_DIR" ]; then
    echo "  $OP_DIR 整个不存在 —— rootfs 构建时没带 OPENPILOT_SRC，" >&2
    echo "  重建：OPENPILOT_SRC=/path/to/openpilot ./vamos build system" >&2
  elif [ ! -s "$OP_DIR/.openpilot-manifest" ]; then
    echo "  目录在但没有 manifest，说明是手工拷的，来源不可追溯。" >&2
  fi
  exit 1
fi

if [ -f "$OP_DIR/.openpilot-manifest" ]; then
  echo "openpilot: $(grep -E '^(openpilot_ref|built)=' "$OP_DIR/.openpilot-manifest" | tr '\n' ' ')"
fi

# venv 是 Dockerfile 里 `uv sync` 装出来的（含 msgq-ipc / opendbc / pandacan /
# teleoprtc / tinygrad 以及所有 vendored 的 comma-deps-*）。
# 注意顺序：venv 的 bin 在最前，`python` 解析到的才是带那些依赖的解释器。
export PATH="$VENV/bin:$PATH"
# 代码本体在这里。openpilot/ 包是符号链接扇出（openpilot/selfdrive -> ../selfdrive），
# 所以 PYTHONPATH 指**仓库根**，selfdrive / common / cereal 才能被 import。
export PYTHONPATH="$OP_DIR${PYTHONPATH:+:$PYTHONPATH}"

cd "$OP_DIR" || exit 1
exec ./launch_openpilot.sh
