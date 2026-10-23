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

# Enable runit services
#
# /etc/sv/<svc> 有的来自 userspace/root/ 覆盖层，有的来自 Void 包。
# 原实现无脑 ln -sf：源目录不存在时会留下**悬空符号链接**，runit 起来后
# runsvdir 每次重启都报一条错误（不致命，但日志里全是噪音，容易掩盖真问题）。
# 现在缺的就在构建日志里明说，好让「该服务的 /etc/sv 目录漏在覆盖层里」
# 和「包没装」这两种情况立刻可见。
RUN for svc in \
  ipa_fws brightnessd fs_setup gpio init-qcom lte \
  avahi-ssh-publish power_monitor power_drop_monitor \
  screen_calibration serial-hostname \
  sound varwatch busybox-ntpd \
  irsc_util leprop adsp cdsp \
  qrtr-ns rmtfs tqftpserv pd-mapper \
  comma bluetoothd magic \
  ssh-param-watcher ncm-param-watcher dnsmasq \
  rsyslogd nftables cnss_daemon polkitd \
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
RUN chmod +x /etc/runit/1 /etc/runit/2 /etc/runit/3

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
# The /data partition is mounted at runtime from /dev/sda12
# We need to create the ssh directory structure on first boot
RUN mkdir -p /var/chroot/ssh

# DEBUG: Custom sshd run script - /data is mounted in runit stage 1
# mkdir 是必需的：/etc/sv/sshd 不在 userspace/root/ 里（也没有 openssh-server
# 包提供它），echo 重定向不会自己建目录，Docker 层会直接报 No such file。
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
    echo 'exec /usr/bin/sshd -D' >> /etc/sv/sshd/run

RUN ldconfig

# Note: /data mount is handled in runit stage 1 (/etc/runit/1)
