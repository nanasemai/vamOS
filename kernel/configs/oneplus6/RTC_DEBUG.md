# RTC / shadow 时钟污染问题（2026-10-14）

在 172.16.42.1 上排"无法启动桌面"时抓到的两层问题：**GDM 起不来**（表层）和
**RTC 硬件不可写 + shadow last_change 被 1973 时钟污染**（根因）。

---

## 现象

- GDM 服务 `active (running)`，`loginctl` 里没有 `seat0` 会话，桌面永远进不去
- `journalctl -u gdm`：

```
gdm-autologin]: PAM unable to dlopen(pam_gnome_keyring.so): 无法打开共享目标文件
gdm-autologin]: pam_unix(gdm-autologin:account): expired password for user ubuntu (root enforced)
gdm3: gdm_session_handle_secret_info_query: assertion 'self->user_verifier_interface != NULL' failed
gdm-autologin: pam_unix(gdm-autologin:chauthtok): conversation failed
```

- `timedatectl`：

```
Local time: 三 2026-10-14 17:41:45 CST       # 系统时钟正常
RTC time:   一 1973-08-13 00:57:55           # RTC 死在 1973
System clock synchronized: no
```

- `/etc/shadow` 里 ubuntu 行：

```
ubuntu:$y$j9T$...:1320:0:99999:7:::
                    ^^^^  = 1973-08-13
```

## 根因链

1. RTC 硬件（pm8998 里的 `rtc@6000`）**只能读不能写**——
   `kernel/linux/drivers/rtc/rtc-pm8xxx.c:622-624` 里 `allow_set_time` 由 DTB
   `allow-set-time` 属性决定，OnePlus 6 的 `pm8998.dtsi:104` 节点没这个属性。
2. 走 offset 路径时依赖 nvmem cell 或 UEFI 变量来存偏移量
   （`pm8xxx_rtc_update_offset()`，见 rtc-pm8xxx.c:243-282），本设备两者都没有。
   `pm8xxx_rtc_update_offset` 里第一句就 `return -ENODEV`：

   ```c
   if (!rtc_dd->nvmem_cell && !rtc_dd->use_uefi)
       return -ENODEV;
   ```

3. 所以 `hwclock --systohc`、`RTC_SET_TIME` ioctl 全部静默失败（ENOTTY/ENOTDEV）。
   RTC 永远停在开机时的那个值——那台机器刷进 kernel 时 RTC 硬件默认就是 1973-08-13，
   于是每次开机 `hctosys` 都读到 1973。

4. 首次设密码时系统时钟还没被 NTP 校正过来（RTC 是 1973，NTP 要几秒才追上），
   `chpasswd` 把 last_change 写成 1320（=1973-08-13 的 epoch days）。

5. GDM 的 autologin PAM 配置里 `@include common-password` 触发 `pam_unix(chauthtok)`；
   同时 `pam_gnome_keyring.so` 缺失导致会话链状态错乱，最终 PAM 报
   "expired password (root enforced)"（这条信息其实语义不准——max=99999 天
   理论上够到 2000+ 年——真正的失败点是 `conversation failed / (old) token not obtained`，
   即 GDM 没接住交互改密的会话）。

6. GDM 断言 `user_verifier_interface != NULL` 失败，autologin 整个链路崩掉，
   桌面进程起不来。

## 为什么 4cb0d7e8 能进桌面

`git show 4cb0d7e8` 只改了 `oneplus6_defconfig` + `required_config.conf`，
RTC 驱动一样坏。区别只是**那次刷 rootfs 时宿主时钟是好的**（或 shadow 是脚本用
宿主 `time()` 直接写入的），last_change 落成正常值，PAM 不触发 chauthtok 分支。
跟 RTC 无直接关系，本质是**"影子变量"**：shadow 字段值依赖于刷 rootfs 时
宿主机的时钟状态。

## 治标（已执行）

在 172.16.42.1 上：

```bash
echo "ubuntu:123456" | chpasswd                # last_change 变成 20740
chage -d 2026-10-14 ubuntu                     # 显式再钉一次
systemctl restart gdm                          # 桌面正常起来
```

`loginctl` 里出现 `seat0 tty2 active`，桌面已可登入。RTC 依然是 1973（下面治本）。

## 治本方案

### 内核 DT 补丁：给 pm8998 rtc@6000 加 `allow-set-time;`

```diff
--- a/arch/arm64/boot/dts/qcom/pm8998.dtsi
+++ b/arch/arm64/boot/dts/qcom/pm8998.dtsi
@@ -104,8 +104,9 @@
 			compatible = "qcom,pm8941-rtc";
 			reg = <0x6000>, <0x6100>;
 			reg-names = "rtc", "alarm";
 			interrupts = <0x0 0x61 0x1 IRQ_TYPE_EDGE_RISING>;
+			allow-set-time;
 		};
```

**安全性**：`allow-set-time` 走 `__pm8xxx_rtc_set_time()`，是 pm8941 系列设计的
标准 4 字节写入序列（disable RTC enable → 写 0 到 Byte0 → 写 Byte1-3 → 写 Byte0
→ re-enable），非 hack。同属性已经在 `pmp8074.dtsi`、`qcs6490-thundercomm-rubikpi3.dts`
上默认开启，上游稳定。

**副作用**：加了这个属性后，`hctosys` 不再走 offset 路径。当前 offset 就是 0
（本来写不进去过），无损失。

### rootfs 加固：shadow 时钟自愈服务

即使 rootfs 重刷时宿主时钟仍然是 1973，`last_change` 又写错，也要在开机后
自动修回。方案：`userspace/etc/systemd/system/oneplus6-shadow-heal.service`
+ 一个 oneshot 单元，检测 last_change < 某个阈值（比如 10000 天 = 1996 年）
就 `chage -d $(date +%Y-%m-%d)`。

### hwclock 二进制缺失

`util-linux` 包已装 2.39.3-9ubuntu6.6 但 `/usr/sbin/hwclock` 不存在
（`dpkg -L util-linux | grep hwclock` 只返回 .txt 文档）。RTC 修好后如果
systemd 要自动 `hwclock --systohc` 写回，缺这个二进制就会失败。要么
`apt install --reinstall util-linux`，要么在 rootfs 里补 busybox。

## 关键代码位置

| 位置 | 作用 |
|---|---|
| `kernel/linux/drivers/rtc/rtc-pm8xxx.c:294` | `__pm8xxx_rtc_set_time()` 硬件写入 |
| `kernel/linux/drivers/rtc/rtc-pm8xxx.c:243` | `pm8xxx_rtc_update_offset()` offset 路径 |
| `kernel/linux/drivers/rtc/rtc-pm8xxx.c:345` | 分支点：allow_set_time ? 硬件 : offset |
| `kernel/linux/drivers/rtc/rtc-pm8xxx.c:622` | DTB 属性读取 |
| `kernel/linux/arch/arm64/boot/dts/qcom/pm8998.dtsi:104` | 缺 `allow-set-time` |
| `kernel/linux/arch/arm64/boot/dts/qcom/pmp8074.dtsi:89` | 参考：已启用 |

## 复现命令（在 target 上）

```bash
# 看 RTC 状态
timedatectl
cat /sys/class/rtc/rtc0/time
cat /sys/class/rtc/rtc0/date

# 看 shadow 污染
getent shadow ubuntu    # 需要 root
passwd -S ubuntu         # 普通用户可读，P/E/L 是状态字符

# 看驱动模式
grep pm8xxx_rtc /proc/kallsyms | head
# 如果看到 pm8xxx_rtc_set_time 但 ioctl 失败，就是 allow_set_time=false

# 试着写 RTC（应该失败）
hwclock --systohc       # 或 python ioctl RTC_SET_TIME

# 看 GDM 日志
journalctl -u gdm -b --no-pager | tail -20
```
