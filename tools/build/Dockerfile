# vamOS Void Linux Build
# check=error=true

# ################## #
# ###### Base ###### #
# ################## #
FROM scratch AS void-base

# Add Void Linux aarch64 rootfs
ARG VOID_ROOTFS
ADD ${VOID_ROOTFS} /

# Build folder
RUN mkdir -p /tmp/vamos

ARG USERNAME=comma

# Base system setup
COPY ./userspace/base_setup.sh /tmp/vamos/
RUN /tmp/vamos/base_setup.sh

# ################### #
# ###### vamOS ###### #
# ################### #
FROM void-base

ARG USERNAME=comma

# Build 64-bit irsc_util (replaces 32-bit blob that requires armhf libs)
COPY ./userspace/irsc_util/ /tmp/vamos/irsc_util/
RUN cd /tmp/vamos/irsc_util && \
    gcc -Wall -O2 -o /usr/bin/irsc_util irsc_util.c && \
    rm -rf /tmp/vamos/irsc_util

# libqmi, ModemManager are from Void repos (in base_setup.sh)
# lpac, qt, weston, gcc-arm-none-eabi - removed, now vendored via commaai/dependencies

# Build EDL reboot helper
COPY ./userspace/reboot_edl/reboot_edl.c /tmp/vamos/reboot_edl.c
RUN mkdir -p /usr/local/libexec && \
    gcc -Wall -Wextra -Werror -O2 -o /usr/local/libexec/reboot-edl /tmp/vamos/reboot_edl.c && \
    rm /tmp/vamos/reboot_edl.c

# Extra packages (nice-to-haves for development)
RUN xbps-install -y \
  bash-completion \
  btop \
  hyperfine \
  iperf \
  iperf3 \
  ripgrep \
  ncdu \
  nfs-utils \
  socat \
  stress-ng \
  tree \
  wavemon \
  android-tools \
  avahi-utils \
  usbutils \
  vim

# Python packages via uv
ARG XDG_DATA_HOME="/usr/local"
ENV PATH="/root/.local/bin:$XDG_DATA_HOME/venv/bin:$PATH"
COPY ./userspace/uv /tmp/vamos/uv
RUN cd /tmp/vamos/uv && \
    MAKEFLAGS="-j$(nproc)" UV_CONCURRENT_BUILDS=4 UV_NO_CACHE=1 UV_PROJECT_ENVIRONMENT=$XDG_DATA_HOME/venv \
    uv sync --frozen --inexact

# Install firmware from upstream linux-firmware (ath10k WiFi + modem + Bluetooth)
COPY ./kernel/firmware/ath10k/WCN3990/hw1.0 /lib/firmware/ath10k/WCN3990/hw1.0
COPY ./kernel/firmware/qcom/sdm845 /lib/firmware/qcom/sdm845
COPY ./kernel/firmware/qca /lib/firmware/qca
RUN ln -sf /lib/firmware/ath10k/WCN3990/hw1.0/wlanmdsp.mbn /lib/firmware/qcom/sdm845/wlanmdsp.mbn

# Root filesystem overlay — all userspace files at their final paths
COPY ./userspace/root/ /

# Install modules produced with the matching boot image.
#
# 原实现还校验 /usr/include/media/cam_req_mgr.h 和 spectra_camera /
# camcc_sdm845 / venus_* 六个模块的 vermagic —— 那整段是 Comma 外挂
# Spectra 驱动体系的产物：
#   * cam_req_mgr.h 是 Comma 自建的 vendor 头，上游内核**没有**这个文件
#     （上游 camss uapi 在 include/uapi/linux/media/ + linux/v4l2*.h）；
#   * spectra_camera / camcc_sdm845 / venus_* 是 out-of-tree .ko，
#     本分支的内核树里根本没有这些驱动；
#   * mc / videodev 在上游是 CONFIG_MEDIA_SUPPORT 的 =y 内置驱动，
#     不产出 .ko，modinfo 查不到。
# 任一条都让 `test` 返回非零，Docker 层直接失败 —— 所以整段删掉。
#
# 现在的判据是「目录名即契约」：build_kernel_oneplus6.sh 用同一个 krel
# 目录名写模块，build_system.sh 用同一个字符串传 KERNEL_RELEASE。
# 只要 /lib/modules/<krel>/modules.dep 存在且 depmod 成功，模块就和
# boot.img 里的内核同源。qrtr 抽样只是兜底（CONFIG_QRTR=m 是内核自带的
# 纯模块，不依赖任何 SoC 私有固件路径），万一哪天上游改名它会立刻在这里
# 报出来，不会静默放过。
ARG KERNEL_RELEASE
ADD ./build/kernel-rootfs.tar /
RUN test -n "$KERNEL_RELEASE" && \
    test -s "/lib/modules/$KERNEL_RELEASE/modules.dep" && \
    test "$(modinfo -k "$KERNEL_RELEASE" -F vermagic qrtr 2>/dev/null | cut -d' ' -f1)" = "$KERNEL_RELEASE" && \
    depmod -a "$KERNEL_RELEASE"

# Fix ownership on home directory (overlay COPY runs as root)
RUN chown -R comma:comma /home/comma
# Void's default .bashrc doesn't source .bash_aliases
RUN printf '\nif [ -f ~/.bash_aliases ]; then\n    . ~/.bash_aliases\nfi\n' >> /home/$USERNAME/.bashrc
RUN mkdir -p /root/.config

# 补齐两个没有 /etc/sv 目录的服务。必须在启用循环**之前**，否则它们永远拿不到
# runsvdir 的符号链接（原实现里 sshd 的 run 脚本写在下面 120 行之后，
# 循环跑到 sshd 时目录还不存在，被 guard 跳过，结果 SSH 服务从来没被启用）。
#
# sshd：openssh-server 不在包里，也没有包提供 /etc/sv/sshd，只能手写。
# 主机密钥放 /data/etc/ssh/ —— /data 在 rootfs 里可写（本分支 rootfs 就在
# userdata 上），所以首次启动生成一次之后就能持久保存。
RUN mkdir -p /etc/sv/sshd && \
    echo '#!/bin/sh' > /etc/sv/sshd/run && \
    echo 'exec 2>&1' >> /etc/sv/sshd/run && \
    echo '# Create ssh host keys if needed (on first boot)' >> /etc/sv/sshd/run && \
    echo 'mkdir -p /data/etc/ssh' >> /etc/sv/sshd/run && \
    echo 'if [ ! -f /data/etc/ssh/ssh_host_ed25519_key ]; then' >> /etc/sv/sshd/run && \
    echo '  ssh-keygen -t ed25519 -f /data/etc/ssh/ssh_host_ed25519_key -N ""' >> /etc/sv/sshd/run && \
    echo '  ssh-keygen -t rsa -b 4096 -f /data/etc/ssh/ssh_host_rsa_key -N ""' >> /etc/sv/sshd/run && \
    echo '  ssh-keygen -t ecdsa -f /data/etc/ssh/ssh_host_ecdsa_key -N ""' >> /etc/sv/sshd/run && \
    echo 'fi' >> /etc/sv/sshd/run && \
    echo 'exec /usr/bin/sshd -D' >> /etc/sv/sshd/run && \
    chmod +x /etc/sv/sshd/run

# nftables：Void 的 nftables 包只提供 CLI，不带 runit 服务。
# 规则本身在覆盖层的 /etc/nftables.conf 里（拦 wwan0 入站）。
# 一次跑完就 sleep，和 fs_setup / init-qcom 那套 one-shot 模式一致 ——
# 规则在内存里由 nft 内核态表持久化，服务退出不会丢。
RUN mkdir -p /etc/sv/nftables && \
    echo '#!/bin/sh' > /etc/sv/nftables/run && \
    echo 'exec 2>&1' >> /etc/sv/nftables/run && \
    echo 'nft -f /etc/nftables.conf' >> /etc/sv/nftables/run && \
    echo 'exec sleep infinity' >> /etc/sv/nftables/run && \
    chmod +x /etc/sv/nftables/run

# Enable runit services
#
# /etc/sv/<svc> 有的来自 userspace/root/ 覆盖层，有的来自 Void 包。
# 原实现无脑 ln -sf：源目录不存在时会留下**悬空符号链接**，runit 起来后
# runsvdir 每次重启都报一条错误（不致命，但日志里全是噪音，容易掩盖真问题）。
# 现在缺的就在构建日志里明说，好让「该服务的 /etc/sv 目录漏在覆盖层里」
# 和「包没装」这两种情况立刻可见。
#
# gpio / lte / power_monitor / power_drop_monitor / brightnessd 这五个服务
# 刻意**不**在这里启用 —— 它们绑死 Comma tici 主板的物理硬件，一加6 上不但
# 没用，而且有几个是主动的危害：
#
#   gpio      /usr/comma/gpio.sh 按 Comma 引脚表导出 TLMM 30/49/134/41/50/116/
#             124/34/33/32/52（HUB_RST_N、PANDA_1V8_EN_N、ST_RST_N、GPS_* ...），
#             最后一行无条件 `gpio 30 1`，即 direction=out + value=1。
#             一加6 的 panel 节点里 `esd-pins { pins = "gpio30"; }` —— **30 是
#             屏幕 ESD 保护脚**。被这个服务抢走并锁成输出，和 DRM 面板驱动直接
#             冲突。这是最实的一条。
#
#   lte       /usr/comma/lte/lte.sh 的 `start` 分支是
#               until is_online; do reset; power_button; done
#             is_online 靠 `lsusb -d "0x05c6:"` 判断，0x05c6 是 Comma 自己的
#             USB 厂商号，一加6 上永远不存在。于是它退化成每 ~2 秒拨一次
#             gpio50 / gpio116 的**死循环**，永远跑不完。
#
#   power_drop_monitor  整个脚本在跟一颗 INA231 电池监测芯片对话：
#             I2C 地址 0x40、`smbus2.SMBus`、PM8998 GPIO4 的电源告警脚、
#             /sys/fs/cgroup/comma/cgroup.procs。一加6 上没有这颗 INA231，
#             也没有 PM8998（用的是 pmi8998/pm8996），PM8998_BASE 回退成 0，
#             于是告警脚变成 gpio3 —— 一个根本没导出的引脚，open() 直接失败。
#             更要命的是电压读数有 `/sys/class/hwmon/hwmon1/in1_input` 兜底：
#             万一 hwmon1 存在但是别的传感器，它会把那个值当成电池电压，
#             低于 4000mV 就 SIGKILL 掉整个 comma cgroup 然后关机。
#
#   power_monitor   读 `/dev/input/by-path/platform-894000.i2c-event`，
#             那是 PM8998 的中断输入设备，一加6 上不存在，每次启动失败。
#
#   brightnessd  写 `/sys/class/backlight/panel0-backlight/`（Comma 的下行内核
#             名字）。更根本的问题是：本分支 DTB 里**没有 backlight 节点**
#             （dtc 反编译确认 compatible 里没有任何 *-backlight，
#             唯一的 "backlight" 是 pmi8998 LED 节点的 label），
#             所以 /sys/class/backlight/ 下没有面板可调，这个服务没有作用对象。
#
#   sound        /usr/comma/sound/sound_init.sh 末尾按
#             case "$(cat /sys/firmware/devicetree/base/model)" in
#               "comma tizi") card=commatizi ... ;;
#               "comma mici") card=commamici ... ;;
#               *) echo "Unsupported sound card: $model" >&2; exit 1 ;;
#             esac
#             来决定 ALSA 卡。一加6 的 model 不在表里，直接 exit 1，run 脚本里
#             `sound_init.sh || exit 1` 把整个服务判失败。commatizi/commamici
#             的卡名和 SEC_MI2S_RX 路由也都是 Comma 的音频拓扑。
#             一加6 的音频走 AFE/SOUL，得按实际 AFE 设备名重写，
#             没有真机信息之前不猜设备名。
#
# 一加6 的基带不走 GPIO 复位，走 qrtr-ns / rmtfs / tqftpserv / pd-mapper
# 这条标准 QMI over SMD 路径（下面都在启用列表里）。
# 脚本本身留在 rootfs 里（lte.nmconnection 和 udev 规则都是无害的），
# 只是不给它们 /etc/runit/runsvdir/default/ 的符号链接 —— 要恢复很容易。
#
# cnss_daemon / polkitd 也刻意不启用：覆盖层里没有这两个 /etc/sv 目录，
# Void 也没有 cnss-daemon 包（srcpkgs/cnss-daemon/template 404，已核实）。
# WiFi 不需要 cnss-daemon —— ATH10K=y + ATH10K_PCI=y + ATH10K_SNOC=y 全内置，
# ath10k 在 probe 时自己从 /lib/firmware/ath10k/WCN3990/hw1.0/ 拉固件
# （上面的 COPY 已就位），参考项目也走这条路：它的 wifi-mac.service
# 只是等 wlan0 和 wiphy 注册，并不起 cnss-daemon。
RUN for svc in \
  ipa_fws fs_setup init-qcom \
  avahi-ssh-publish \
  screen_calibration serial-hostname \
  varwatch busybox-ntpd \
  irsc_util leprop adsp cdsp \
  qrtr-ns rmtfs tqftpserv pd-mapper \
  comma bluetoothd magic \
  ssh-param-watcher ncm-param-watcher dnsmasq \
  rsyslogd nftables \
  sshd agetty-ttyMSM0 agetty-ttyAMA0; do \
    if [ -d "/etc/sv/$svc" ]; then \
      ln -sf /etc/sv/$svc /etc/runit/runsvdir/default/; \
    else \
      echo "WARN: /etc/sv/$svc 不存在，跳过（不生成悬空符号链接）"; \
    fi; \
  done

# Remove udevd service - we start udevd in runit stage 1, no need for service
RUN rm -f /etc/runit/runsvdir/default/udevd

# Make logs readable by comma user (for journalctl shim)
RUN sed -i 's/FileCreateMode 0640/FileCreateMode 0644/' /etc/rsyslog.conf

# Set executable permissions
RUN chmod +x /usr/comma/comma.sh /usr/comma/get-serial.sh /usr/comma/get-bt-address.sh /usr/comma/set-bt-address.sh /usr/comma/set_ssh.sh /usr/comma/set_ncm.sh /usr/comma/fs_setup.sh /usr/bin/journalctl /etc/sv/bluetoothd/run
# DSP 启动脚本：adsp/cdsp 服务在覆盖层里，路径散在四处（/etc/sv/*/run、
# /etc/initscripts/、/usr/bin/、/usr/local/qr-linux/）。git 里的模式是 0775，
# 但 COPY 之后想再确认一次 —— 这里缺一个可执行位就会静默失败。
RUN chmod +x /usr/bin/rproc-boot.sh /usr/bin/cdsp.sh \
    /usr/local/qr-linux/adsp-start.sh /etc/initscripts/adsp.sh \
    /etc/sv/adsp/run /etc/sv/cdsp/run
# core-services/ 也要可执行：/etc/runit/1 里 stage 1 会对 02-kmods.sh 做
# `[ -x ]` 检查，权限不对就静默跳过，模块一个都不会加载。
RUN chmod +x /etc/runit/1 /etc/runit/2 /etc/runit/3
RUN chmod +x /etc/runit/core-services/*.sh 2>/dev/null || true

# Shutdown wrappers - send wall broadcast like systemd does on Ubuntu
# Only poweroff and reboot: halt/shutdown must NOT be wrapped because Void's
# /usr/bin/shutdown script calls halt/reboot internally, causing cascading walls
RUN chmod +x /usr/local/sbin/poweroff && \
    ln -sf poweroff /usr/local/sbin/reboot

# NetworkManager connection permissions.
# 两点必须一起处理：
#   1. userspace/root/etc/NetworkManager/ 下只有 NetworkManager.conf 和 conf.d/，
#      没有 system-connections/ —— 目录不建的话 chmod 的 glob 根本找不到路径。
#   2. 即使目录建了，首次构建时一个 .nmconnection 都没有，shell glob 不匹配就
#      原样展开成字面量 `*.nmconnection`，chmod 照样报 "cannot access"。
# 用 find -exec 而不是 glob：零匹配时 find 是成功的空操作。
# 目录同时是运行时 NetworkManager 写连接的落点，所以建了是必要的。
RUN mkdir -p /usr/lib/NetworkManager/system-connections && \
    find /usr/lib/NetworkManager/system-connections -name '*.nmconnection' -exec chmod 600 {} +

# MOTD - profile.d runs update-motd.d scripts into /run/motd, pam_motd displays it
RUN sed -i 's|motd=/etc/motd|motd=/run/motd|' /etc/pam.d/system-login

# Hourly logrotate cron job
RUN chmod 755 /etc/cron.hourly/logrotate

# Mount point directories used by runtime partition mounts
RUN mkdir -p /dsp /firmware && \
    chown comma:comma /dsp /firmware

# /system/persist structure (copied to /data on first boot by fs_setup.sh)
RUN mkdir -p /system/persist/hlos_rfs/shared \
             /system/persist/rfs/mdm/adsp \
             /system/persist/rfs/mdm/mpss \
             /system/persist/rfs/msm/adsp \
             /system/persist/rfs/msm/mpss \
             /system/persist/rfs/shared

# Prefer ipv4 over ipv6
RUN echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf

# Compatibility symlinks
# pdmappersvc needs libjson-c.so.2 but Void has libjson-c.so.5
RUN ln -sf /usr/lib/libjson-c.so.5 /usr/lib/libjson-c.so.2
# raylib wheel needs libffi.so.6 but Void has newer version
RUN ln -sf $(ls /usr/lib/libffi.so.* 2>/dev/null | grep -v '.so.6' | head -1) /usr/lib/libffi.so.6
# TODO: remove once no more openpilot libraries build against the _adreno names
RUN ln -sf /usr/lib/libGLESv2.so.2 /usr/lib/libGLESv2_adreno.so && \
    ln -sf /usr/lib/libEGL.so.1 /usr/lib/libEGL_adreno.so

# ldconfig
RUN ldconfig

# Rootfs development/eval tools
COPY ./userspace/eval/rootfs-init.sh /usr/local/bin/
COPY ./userspace/eval/rootfs-manifest.sh /usr/local/bin/
COPY ./userspace/eval/rootfs-diff.sh /usr/local/bin/
COPY ./userspace/eval/rootfs-export.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/rootfs-*.sh
# op-launch 是 openpilot 的启动入口（见脚本头部注释：rootfs 里没有任何东西会
# 拉它，setup->installer 那条链在本分支走不通）。COPY 之后确认一次可执行位。
RUN chmod +x /usr/local/bin/op-launch.sh 2>/dev/null || true

# Read-only rootfs setup
COPY ./userspace/readonly_setup.sh /tmp/vamos/
RUN /tmp/vamos/readonly_setup.sh

# Drop non-English locales, man/doc/info pages, and xbps cache
RUN find /usr/share/locale -maxdepth 1 -mindepth 1 ! -name en_US ! -name en -exec rm -rf {} + && \
    rm -rf /usr/share/man /usr/share/doc /usr/share/info && \
    rm -rf /var/cache/xbps

# ################# #
# #### Cleanup #### #
# ################# #

# DEBUG: allow root login
RUN echo ttyS0 >> /etc/securetty
RUN echo ttyMSM0 >> /etc/securetty

# DEBUG: fix comma password (chpasswd fails under QEMU)
# Use pre-computed hash for reliability: password is "comma"
RUN usermod -p '$6$vamosdev$NmMcideymvdAilEr.m7OeTX.fnt3H4UmcgheKB39rkrmebVfvZIUE17zjgtOxi7K07uGicamzFFbkFLE3EjQj/' comma && \
    usermod -p '$6$vamosdev$NmMcideymvdAilEr.m7OeTX.fnt3H4UmcgheKB39rkrmebVfvZIUE17zjgtOxi7K07uGicamzFFbkFLE3EjQj/' root

# DEBUG: SSH setup - sshd_config expects keys in /data/etc/ssh/
# /data 在 rootfs 里可写（本分支 rootfs 就在 userdata 上），首次启动生成
# 主机密钥后持久保存。/etc/sv/sshd/run 在上面的启用循环之前创建。
RUN mkdir -p /var/chroot/ssh

RUN ldconfig

# Note: /data mount is handled in runit stage 1 (/etc/runit/1)
