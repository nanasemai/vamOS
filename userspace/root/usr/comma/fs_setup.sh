#!/bin/bash
# Void Linux version - no systemd-tmpfiles

# Ensure the symlinks in the read only rootfs are
# backed by real files and directories on userdata.

# 根文件系统扩容。
#
# 镜像是固定 6G 打出来的（tools/build/build_system.sh 的 ROOTFS_IMAGE_SIZE），
# 而一加6 的 userdata 分区远大于 6G。不扩的话 / 永远只有 6G，openpilot 的
# /data/records 和日志很快就写满。ref 的 auto-resize-rootfs.service 就是这个
# 用途；这里并进 fs_setup，少一个服务、少一次冷启动。
#
# resize2fs 是幂等的：文件系统已经占满可用空间时直接返回 0，所以每次开机跑
# 一次没有副作用，也不用留标记文件。
# guard 住 resize2fs：e2fsprogs 不在时只打印一行，不让 fs_setup 整体失败 ——
# 后面的 /home overlay 和 /run/fs_setup.ready 是逗号服务的硬依赖，不能连带挂掉。
ROOT_DEVICE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [ -n "${ROOT_DEVICE}" ] && command -v resize2fs >/dev/null 2>&1; then
  PARTITION_SIZE="$(blockdev --getsize64 "${ROOT_DEVICE}" 2>/dev/null || echo 0)"
  FS_SIZE="$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2}')"
  if [ "${PARTITION_SIZE}" -gt 0 ] && [ -n "${FS_SIZE}" ] && [ "${PARTITION_SIZE}" -gt "${FS_SIZE}" ]; then
    echo "resizing / from ${FS_SIZE} to fit ${PARTITION_SIZE} bytes on ${ROOT_DEVICE}"
    resize2fs "${ROOT_DEVICE}" || echo "WARN: resize2fs failed, continuing with ${FS_SIZE} bytes"
  fi
elif [ -n "${ROOT_DEVICE}" ]; then
  echo "WARN: resize2fs not installed, / stays at its image size"
fi

# Create tmpfiles directories manually (replaces systemd-tmpfiles)
mkdir -p /var/run
chmod 0755 /var/run

mkdir -p /var/crash
chmod 0755 /var/crash

mkdir -p /var/tmp
chmod 1777 /var/tmp

mkdir -p /var/lib/logrotate
chmod 0755 /var/lib/logrotate

mkdir -p /var/lib/rmtfs
chmod 0755 /var/lib/rmtfs

mkdir -p /var/spool/cron/atjobs
chmod 0755 /var/spool /var/spool/cron /var/spool/cron/atjobs

# setup /home
# lowerdir 用 rootfs 自己的 /home：userspace/root/home/ 里的 dotfiles
# （.bashrc / .gitconfig / .tmux.conf 等）经 COPY 后落在 /home/comma/，就是要
# 当只读底层的默认内容。原来的 /usr/default/home 在覆盖层里根本不存在，
# mount 会 EROFS/ENOENT 失败，/home overlay 起不来，comma 用户没有家目录。
#
# upperdir/workdir 放在 /rwtmp（100M tmpfs），和挂载点不共用文件系统，不会成环。
# 挂载本身覆盖在 /home 上：内核在挂载生效前就解析完 lowerdir，所以
# 「lowerdir 就是挂载点」这种自覆盖是安全的。
mkdir -p /rwtmp/home_work
mkdir -p /rwtmp/home_upper
chmod 755 /rwtmp/*
mount -t overlay overlay -o lowerdir=/home,upperdir=/rwtmp/home_upper,workdir=/rwtmp/home_work /home \
  || echo "WARN: /home overlay mount failed (lowerdir=/home)"

# /etc
mkdir -p /data/etc
touch /data/etc/timezone
touch /data/etc/localtime
mkdir -p /data/etc/netplan
mkdir -p /data/etc/NetworkManager/system-connections

# /cache
chown -R comma:comma /cache/

# /data/ssh
mkdir -p /data/ssh
chown comma: /data/ssh

# /data/media/0 —— comma.sh 一开机就 `sudo chown comma: /data/media`，
# 目录不存在会报错（非致命，但每次启动一条噪音）。
# /data/params/d —— openpilot 的参数目录。openpilot 自己会 makedirs，
# 但 setup 流程会先读它，提前建好避免竞态。
mkdir -p /data/media/0 /data/params/d
chown -R comma:comma /data/media /data/params

# /data/tmp - clear out
rm -rf /data/tmp/
mkdir -p /data/tmp/

# /data/persist
if [[ ! -d /data/persist ]]; then
  sudo cp -r /system/persist /data
fi

# zram compressed swap
echo lz4 > /sys/block/zram0/comp_algorithm
echo 512M > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0
echo 10 > /proc/sys/vm/swappiness

# Signal readiness for services that depend on the overlay
mkdir -p /run
chmod 0755 /run
touch /run/fs_setup.ready
