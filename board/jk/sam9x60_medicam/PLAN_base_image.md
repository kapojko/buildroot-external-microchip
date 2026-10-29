# MediCam base image — implementation plan

Status: **stage 0, stage 1, stage 1.5 and stage 2 done and verified on hardware
(2026-10-28): the board boots from NAND with no SD card, `/` on UBIFS and `/data`
on a second UBI volume.** 2026-10-29: **F29 fixed** — an ordering cycle in
`medicam-data.service` had been dropping `/data` (and with it the user
application) from the boot transaction; the unit fix is verified on hardware,
but both images still have to be rebuilt/reflashed to ship it. Open: the 10x
reboot / 5x power-cut matrix (stage 2 run-off) and the ~30 s ROM boot-sequence
delay without an SD card (F26, accepted for now). Work happens session by
session on branch `medicam_clean` (created from `medicam`); see the working
rules in section 0 and the measured log in LOG_base_image.txt.

Board: SAM9X60D1G SiP (DDR2 128 MiB in package), 128 MiB RAM, MT29F8G08ABACAWP
parallel NAND (1 GiB), OV2640 camera on ISI, 24C256 EEPROM @0x50 on I2C0,
WS2812 on SPI1, two USARTs, Ethernet RMII, USB host + USB device.

Goal: a lean, trustworthy base image that boots from SD (stage 1), optionally
boots from NAND (stage 2), and always exposes a persistent `/data` area so a
desktop script can later push FRP + the user application. User-application
integration itself is **out of scope**; only its filesystem/systemd contract is
fixed here (section 11).

---

## 0. Working rules (binding for every stage, including future sessions)

**R1 — full rebuilds are run by the user, not by the agent.**
A full build takes ≥ 1 h and downloads packages from the network. The agent therefore:

* prepares and statically verifies every file/defconfig change;
* **may** run: `<defconfig>` selection, `make <pkg>-rebuild`, `make <pkg>-dirclean`,
  `make linux-rebuild`, and any read-only inspection of `output/` (`grep`, `ls`, `du`, `size`);
* **must not** run a full `make` (or `make clean`/`defclean` + build) inside a piped/tailed tool
  call — a network outage or a failing package download has to stay visible to the user so it can
  be fixed and the build resumed;
* hands over the exact command plus the expected completion signal, and waits for the user's
  paste of the tail, or of `~/src/build-<stage>.log`.

Suggested user command: `cd ~/src/buildroot-mchp && make -j$(nproc) 2>&1 | tee ~/src/build-<stage>.log`.

**R2 — the build log is a deliverable of every stage.**
`board/jk/sam9x60_medicam/LOG_base_image.txt` records every reproducible step:
host preparation, commands, files touched, observed numbers. Style:

* numbered steps, one action per line, `DONE` / `TODO` / `FAILED` marker per step; no prose;
* commands copy-pasteable as-is, measured values inline (`rootfs=110 MiB`);
* updated in the **same commit** as the stage it documents — a stage is not done before its log
  lines exist;
* device-specific values (MAC, NAND OOB, die size) are always *measured and recorded*, never
  assumed, so the log replays on a different board.

**R3 — builds happen only in the WSL checkout, never on the Windows one.**
WSL inherits the Windows `PATH` (Windows `make`/`gcc`/`find` shadow the Linux ones) unless
`[interop] appendWindowsPath = false` is set in `/etc/wsl.conf`. From the Windows side the MSYS
layer rewrites unix-looking arguments; call WSL as
`wsl -d Debian -- bash -lc '<single-quoted command>'` (`MSYS_NO_PATHCONV=1` when an argument must
reach Linux verbatim). Long tool calls that hang are usually this, not the build.

**R4 — hardware sessions are explicit, and cheap.**
The board is only needed at the points listed below; everything before them is off-target work,
so no session should block on hardware.

| Board session | When | Needed for |
|---|---|---|
| 1 | end of stage 1 (task 1.11) | boot the trimmed SD image, serial + SSH login, `mtdinfo` geometry (**gates stage 2**), USB smoke test |
| 2 | end of stage 1.5 | `/data` on NAND from the SD boot, write/reboot/read-back, `/home` symlink |
| 3 | stage 2 | NAND boot attempt, power-cut matrix |

Per session, have ready: DBGU UART at 115200 8N1, Ethernet with DHCP/DNS, a written SD card
(balenaEtcher or `dd`), and a power switch that can cut power cleanly.

---

## 1. Scope

| In scope | Out of scope |
|---|---|
| Package trim, SSH, root password, hostname, overlay infra | Writing/porting the user application or FRP |
| NAND boot attempt (bootstrap/U-Boot/env/UBIFS layout) | The desktop-side upload script itself |
| NAND as persistent `/data` (fallback + always shipped) | A/B updates, read-only rootfs (stage 3, later) |
| Fixing reproduction hazards found during analysis | Wi-Fi/BT application features, firewall rules |

---

## 2. Workspace and branches (current state)

| Checkout | State |
|---|---|
| Windows `D:/Source/buildroot-external-microchip` | branch `medicam` @ `07a8c2b` (trusted, boots) |
| WSL `~/src/buildroot-external-microchip` | **not detached**: a local branch *literally named* `origin/medicam` @ `b5443b5` (content of `medicam_nand`), tree clean; no `origin/medicam_clean` ref yet; has a `local` remote → `/mnt/d/Source/buildroot-external-microchip` (fetch the Windows checkout directly) — must be reset |
| WSL `~/src/buildroot-mchp` (buildroot main tree) | `linux4microchip-2025.04`, `.config` built from `sam9x60_medicam_nand_defconfig` (`BR2_DEFCONFIG` still points there), last build 2026-07-27; `output/images/` still holds NAND-variant artifacts — re-select `sam9x60_medicam_defconfig` before stage 1 and do not mistake those files for stage 1 results |

Branch roles:

* `medicam` — working SD configuration, boots on hardware.
* `medicam_nand` — untrusted experiment (never flashed successfully). Reference
  only: files are ported one by one after review, **never merged wholesale**;
  in particular its DTS and defconfig are not adopted.
* `medicam_clean` — **new**, created from `medicam`; all work in this plan lands here.

---

## 3. What the current board configuration is

### 3.1 `configs/sam9x60_medicam_defconfig` vs `sam9x60_curiosity_headless_defconfig`

167 lines, of which only five differ:

| Setting | Curiosity (base) | MediCam |
|---|---|---|
| `BR2_TARGET_GENERIC_HOSTNAME` / `_ISSUE` | `sam9x60_curiosity` / "Microchip SAM9X60 CURIOSITY Demo" | `sam9x60_medicam` / "Welcome to the SAM9X60 MediCam" |
| `BR2_ROOTFS_POST_SCRIPT_ARGS` (genimage cfg) | `board/microchip/sam9x60_curiosity/genimage.cfg` | `board/jk/sam9x60_medicam/genimage.cfg` |
| Kernel DTS | `BR2_LINUX_KERNEL_INTREE_DTS_NAME="microchip/at91-sam9x60_curiosity"` | `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH=…/board/jk/sam9x60_medicam/at91-sam9x60_medicam.dts` |
| Packages | — | `+ BR2_PACKAGE_V4L2GRAB=y` (added with the camera commit) |
| U-Boot env source | `…/sam9x60_curiosity/uboot-env.txt` | `…/board/jk/sam9x60_medicam/uboot-env.txt` |

Everything else is inherited verbatim, including the bootloaders:

* `BR2_TARGET_AT91BOOTSTRAP3_DEFCONFIG="sam9x60_curiositysd_uboot"`, AT91Bootstrap 4.0.11
* `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="sam9x60_curiosity_mmc"`, U-Boot `linux4microchip-2025.04`
* kernel `at91_dt` + `board/microchip/sam9x60/at91_dt.fragment`
* 512 M ext4, rootfs overlays from `board/microchip/sama5*/` (no MediCam overlay)

Boot flow difference: curiosity boots a FIT (`bootm itb#kernel_dtb`); MediCam
loads `zImage` + `.dtb` separately and uses `bootz`. Consequently
`BR2_PACKAGE_DT_OVERLAY_MCHP` + FIT are built but **unused** (the generated
`.itb`/`.dtbo` are not listed in `genimage.cfg`).

The bootloaders being "curiosity" is acceptable: same SAM9X60D1G SiP DDR2 and the
same SDMMC0 wiring, so ROM → AT91Bootstrap → U-Boot works unchanged.

### 3.2 Measured sizes (last build, `~/src/buildroot-mchp/output`, NAND variant)

Package set is identical to the SD defconfig except UBI/UBIFS target options, so
the rootfs numbers are representative.

| Metric | Value |
|---|---|
| `BR2_PACKAGE_*=y` in defconfig | 122 lines (110 target settings + 12 host) |
| `BR2_PACKAGE_*=y` in generated `.config` | 430 (includes all sub-options) |
| Built components (`output/build/*`) | 244 |
| Installed files in rootfs | 11 541 |
| `output/target` on disk | **211 MiB** |
| `rootfs.ext2/4` | nominal **512 MiB**, content ≈ **221 MiB**, `rootfs.tar` 205 MiB |
| `sdcard.img` (SD defconfig) | **≈ 529 MiB** (1 M offset + 16 M `boot.vfat` + 512 M ext4) |
| `sdcard.img` (NAND defconfig build) | 806 354 944 B (256 M vfat + 512 M ext4) |
| `medicam-nand.img` / `rootfs.ubifs` / `rootfs.ubi` | 128 MiB / 101 MiB / 105 MiB |

Largest installed packages (measured):

```
18.81 systemd (of which hwdb.bin 13.0)   17.70 python3        13.29 vim
 8.25 file      6.22 gdb      5.79 openssh      5.49 python-pip
 4.25 libopenssl 4.05 python-setuptools 3.84 libglib2 3.70 util-linux
 3.27 python-cryptography 2.53 bluez5_utils 2.31 p11-kit 2.22 iproute2
 2.11 gnutls 2.09 dhcp 2.02 kbd 1.96 lmbench 1.70 tzdata 1.61 wpa_supplicant
 1.33 hostapd 1.17 sqlite 1.06 libgcrypt 1.00 strace ...
```
Sum of attributed packages ≈ 150 MiB; the remaining ~60 MiB is unattributed floor
(systemd+udev, glibc, kernel modules, util-linux, iproute2, bash/busybox).

**Stage 1 result (clean build, 2026-10-28) — the estimate above was pessimistic:**
the trimmed image is **55 MiB** (`du -sm output/target`; 63 MiB before `file` was
dropped), `rootfs.tar` 52 MiB, 3 923 tar entries (was 11 541), `sdcard.img` **273 MiB**,
`boot.vfat` 16 MiB with `zImage` 5.34 MiB + `u-boot.bin` 448 KiB.
On the board: `du -sm /` = **50 MiB**, `df` 47.6 MiB used of 229.9 M (256 MiB ext4),
`zImage` 5.62 MiB (kernel + SysRq/BPF), `u-boot.bin` 448 KiB.
Largest installed packages now: systemd 10.5, openssh 5.8, libopenssl 4.2,
util-linux 3.6, linux (modules) 3.2, glibc 2.1, kbd 2.0, gcc-final (libstdc++) 1.8,
tzdata 1.7, iproute2 1.7 MiB. Unattributed overlap ≈ 6 MiB. (Sorted before the
`file` drop, which removed the then-largest entry.)
Two items from the drop list do not actually leave the image: `kbd` (pulled in by
systemd's default vconsole keymap, ≈ 5 MiB with keymaps + consolefonts) and
busybox applet symlinks such as `usr/bin/tree` (a symlink, no bytes) — see the
candidates in section 10.

### 3.3 Kernel / toolchain facts (verified in `output/build/linux-custom/.config`)

* `BR2_ARM_CPU_ARMV5=y`, `BR2_arm926t=y` → Go later needs `GOARM=5` (out of scope here).
* Storage: `MTD=y`, `MTD_NAND_ATMEL=y`, `ATMEL_EBI=y`, `MTD_UBI=y`,
  `MTD_UBI_BLOCK=y`, `MTD_UBI_FASTMAP=y`, `UBIFS_FS=y`, `MTD_CMDLINE_PARTS=y`,
  `EXT4_FS=y`, `VFAT_FS=y`, **`CONFIG_MTD_BLOCK` is NOT set**, `JFFS2` off.
* USB host: `USB_EHCI_HCD_AT91=y`, `USB_OHCI_HCD_AT91=y`, `USB_STORAGE=y`, `SCSI=y`.
* USB gadget: `USB_CONFIGFS=m`, `USB_CONFIGFS_{ACM,RNDIS,MASS_STORAGE}=y`.
* Wi-Fi: `CFG80211=m`, `MAC80211=m`, `CFG80211_WEXT=y`, `RFKILL=y`, `RT2800USB=m`
  (RT33xx/RT35xx/RT53xx/RT55xx), `RTL8187=m`, `MWIFIEX_USB=m`.
  Missing drivers: `rtl8xxxu`, `ath9k_htc`, `mt7601u`, `brcmfmac`, `r8188eu`,
  `zd1211rw`, `carl9170` (one fragment line each).
* Bluetooth: `BT=y`, `BT_BREDR`, `BT_LE`, `BT_LE_L2CAP_ECRED`, `RFCOMM`, `BNEP`,
  `HIDP`, `BT_HCIBTUSB=y`, `BT_HCIUART=y`.
* Netfilter: `NETFILTER=y`, `NF_TABLES=y`, `IP_NF_IPTABLES=y`, `IP_NF_FILTER=y`,
  **`NF_CONNTRACK` off** → no stateful rules possible.
* RNG: `HW_RANDOM_ATMEL=y`; entropy: `CONFIG_MODULES=y`, `FW_LOADER=y`.
* Buildroot side: `BR2_PACKAGE_KMOD=y`, `+TOOLS`, `WIRELESS_REGDB=y`,
  `SYSTEMD_TIMESYNCD=y`, `SYSTEMD_NETWORKD=y`, `SYSTEMD_HWDB=y`,
  `SYSTEMD 256`, `Go 1.23.7`, `Python 3.12`, no `E2FSPROGS`, no `LINUX_FIRMWARE`.

---

## 4. Findings that shape the plan

Each finding was verified against the tree or a datasheet; the fix is in the
indicated stage.

**F1 — the kernel config fragment is a saved git diff, not a kconfig fragment.**
`board/microchip/sam9x60/at91_dt.fragment` has a literal `+` prefix on every line
(`+CONFIG_OVERLAY_FS=y`), so no symbol is applied. Proof: the built kernel has
`# CONFIG_OVERLAY_FS is not set` while the file requests `=y`. Consequences:
`OVERLAY_FS`, `NAMESPACES`, cgroup set, `EXT4_FS_POSIX_ACL`, `SYN_COOKIES`,
`USB_CONFIGFS_ECM` are all off. Netfilter happens to be on from the `at91_dt`
defconfig, not from this file. → **Stage 1 (task 1.7)**.

**F2 — NAND spare/OOB mismatch.** MT29F8G08ABACAWP datasheet: page `4320 B
(4096 + 224)`, block `64 pages (256K + 14K)`, 2 planes × 2048 blocks →
**4096 blocks × 256 KiB = 1 GiB**, OOB **224 B**. AT91Bootstrap inherits
`CONFIG_PMECC_OOB_256=y` from the curiosity NAND presets, whose chip
(Macronix MX30LF4G28AD, 4 Gb) really is `4096+256`. `scripts/pmecc_head.py`
derives `eccOffset = oob - sectors*ecc_bytes` → **152** for 256 (current
`0xc2605007`) vs **120** for 224. The ROM decodes the bootstrap using the header
stamped into `boot.bin.pmecc`, so this must be corrected before NAND boot can
work. → **Stage 2 (task 2.1)**; confirmed by stage 1 `mtdinfo`.

**F3 — three different NAND densities coexist in the tree.**
`genimage-nand.cfg` declares `numpebs = 512` (128 MiB), the DTS rootfs partition
ends at 512 MiB, the README and the chip say 1 GiB. Additionally the two
branches disagree: `medicam` DTS has kernel `6 MiB` and rootfs at `0x800000`,
while `medicam_nand` has kernel `8 MiB` and rootfs at `0xa00000` (the latter is
the self-consistent one). → freeze one table in four places (DTS, env, genimage,
flash script) in **stage 1.5**, use it in **stage 2**.

**F4 — SAM-BA DDR2 rejection is a preset problem, not a hardware problem.**
SAM-BA 3.9.1: `sam9x60-ek` uses `extram { preset: 12 }` (W972GG6KB) — the wrong
chip; the current script therefore passes `::no_extram` and falls back to the
64 KiB internal SRAM buffer. `qml/SAMBA/Device/SAM9X60/SAM9X60.qml`
`configDevice()` maps `sam9x60d1g` → `extram.preset = 8` (W971GG6SB), which is
exactly the SiP's W971G16SG2-5I. The curiosity board preset leaves `extram`
commented out with the same chip name. **Use `-d sam9x60d1g`**, keep
`-a nandflash:1:8:0xc2605007`, drop `::no_extram` (buffer moves to DRAM).
→ **Stage 2 (task 2.7)**.

**F5 — no MediCam rootfs overlay is wired in.** The `medicam` defconfig uses only
`board/microchip/sama5*/fs-overlay`, so board-specific files (sshd config, units,
`/data`) cannot be shipped at all. → **Stage 1 (tasks 1.3–1.5)**.

**F6 — SSH is installed but not enabled, and root has no password.**
`BR2_PACKAGE_OPENSSH=y` installs `/usr/lib/systemd/system/sshd.service`, but
`/etc/systemd/system/` is empty (Buildroot only installs the unit; enablement is
done by `systemctl --root=… preset-all`, and `90-systemd.preset` does not enable
sshd). `BR2_TARGET_GENERIC_ROOT_PASSWD=""` → `/etc/shadow` root has no password.
The shipped `sshd_config` is minimal (no `Include`, no `PermitRootLogin`) →
OpenSSH default `PermitRootLogin prohibit-password`. → **Stage 1 (task 1.4/1.6)**.

**F7 — `board/microchip/at91/post_build.sh` breaks the build after trimming.**
It unconditionally `mv`s `dhcpd.service` and `rm`s `wpa_supplicant.service`
without checking existence; dropping those packages makes the script fail.
→ **Stage 1 (task 1.9)**.

**F8 — NAND is visible from an SD boot, but not mountable as a block device.**
`CONFIG_MTD_BLOCK` is off (no `/dev/mtdblockN`), while UBI/UBIFS and the full
`mtd-utils`/UBI toolset (`ubiattach`, `ubimkvol`, `ubiformat`, `ubiblock`, …) are
present. Mount options: `ubiattach` + `mount -t ubifs ubi0:rootfs` (works
today), or `ubimkvol` + `mkfs.ubifs` for a dedicated `/data` volume, or
`ubiblock` + ext4 (needs `E2FSPROGS`). Bare ext4 on NAND is not wear-safe.
→ **Stage 1.5**.

**F9 — `&trng` is not enabled in the MediCam DTS** although
`HW_RANDOM_ATMEL=y` and `sam9x60.dtsi` provides `rng@f0030000`
(`microchip,sam9x60-trng`). Without it, first-boot `ssh-keygen -A` can stall on
entropy. → **Stage 1 (task 1.8)**.

**F10 — firewall tooling is currently useless.** Both `iptables` 0.9 (legacy
xtables backend, `BR2_PACKAGE_IPTABLES_NFTABLES` off) and `nftables` 0.6 (with
`BR2_PACKAGE_NFTABLES_PYTHON=y`) are in the image, but `NF_CONNTRACK` is off, so
no stateful rule set is possible. No firewalld in the tree. → drop both in
**stage 1**; when a rule set is designed, add `nftables` + `CONFIG_NF_CONNTRACK`,
`NF_CONNTRACK_IPV4`, `NETFILTER_XT_MATCH_CONNTRACK`.

**F11 — DHCP client is `systemd-networkd`.** `BR2_SYSTEM_DHCP="eth0"` generates
`/etc/systemd/network/eth0.network` (`DHCP=yes`, verified present in the image),
so `dhcp`, `dhcpcd`, `dhcp-server`, `radvd`, `ifupdown` are redundant.

**F12 — no `rfkill` package exists in this tree**; the tool is
`BR2_PACKAGE_UTIL_LINUX_RFKILL` (util-linux option). Ralink firmware is
`BR2_PACKAGE_LINUX_FIRMWARE_RALINK_RT2XX` (provides `rt2870.bin`).

**F13 — the curiosity crypto stack is unrelated to TLS/Wi-Fi.**
`cryptoauthlib`, `p11-kit`, `libp11`, `gnutls` exist for the ATECC demo on the
curiosity board (MediCam only has a 24C256 EEPROM). TLS comes from `libopenssl`
(this build) or from Go's own `crypto/tls` (frp) + `ca-certificates`.
`wpa_supplicant` uses OpenSSL. Dropping them is safe.

**F14 — `kmod` must stay**: the OV2640 driver is built as a module
(`CONFIG_VIDEO_OV2640=m`).

**F15 — `busybox` wget has no HTTPS** (`CONFIG_WGET=y` without the HTTPS feature)
→ keep the full `wget` package (uses the already-present OpenSSL).

**F16 — boards share one hostname.** `BR2_TARGET_GENERIC_HOSTNAME="sam9x60_medicam"`
is identical on every device, so "target the board by hostname" cannot work with
more than one board on a LAN. → unique hostname per board at first boot
(**task 1.5**), `medicam-<6 hex chars of eth0 MAC>`.

**F17 — the WSL checkout currently contains the untrusted branch content** and
would silently build the wrong tree. → **stage 0**.

**F18 — CRLF / exec-bit hazard (measured, not assumed).** The Windows checkout
uses `core.autocrlf=true`, so its *working tree* is CRLF while the *blobs* are LF;
the build host sees LF, so nothing is broken today. Measured over all tracked
files (`git cat-file blob HEAD:<f>`, counting CR bytes in Python; the shell
CR idiom is mangled by git-bash and yields false results): only the two PNGs (binary, expected)
and this plan file (2 stray CRs, fixed) contain CR bytes. So the real hazards are
(a) files created on the Windows side without a matching `.gitattributes` rule
(e.g. overlay `motd`/`sshd_config`, which have no extension) and (b) **lost exec
bits** — Windows has `core.fileMode=false` and the `executable` gitattribute is
informative only, so a new `*.sh` must be added with
`git update-index --chmod=+x <path>`. `medicam_nand`'s `.gitattributes` is ported
in **stage 0** (extended with the overlay text patterns); audit
`git ls-files -s -- '*.sh' | grep '^100644'` must stay empty for our scripts.

**F22 — an incremental build cannot produce the trimmed image.** Buildroot does
not delete files from `output/target` when a package is disabled, so after the
stage 1 defconfig change a plain `make` regenerates the images *with* the old
contents (measured: `output/target` stayed at 211 MiB, python3/vim/gdb/dhcpd still
in `rootfs.tar`). Any package-set change therefore needs `make clean && make`
(`dl/` is preserved, nothing is re-downloaded), and only then do the stage 1 size
numbers in 3.2/7.3 mean anything. Related and expected: image creation prints
`".../target/home" already exists and is not a directory.` — `makedevs` applying
the `d /home 755` entry of `system/device_table.txt` to the `/home -> data/home`
symlink (exit status 0, the symlink survives; the runtime twin, systemd's
`Q /home` in `tmpfiles.d/home.conf`, is masked by the board overlay). → **Recorded
in stage 1 (task 1.11) / LOG 7.11b**.

**F23 — the OV2640 needs the module to be plugged; nothing else.** With the
module absent the driver reports `ov2640 0-0030: Product ID error 87:87` and `i2cdetect -y 0`
shows nothing at `0x30` (the bus floats), and no `/dev/video0` appears. With the
module fitted: `Product ID 26:42 Manufacturer ID 7f:a2` → `OV2640 Probed`,
`/dev/video0` is `atmel_isi`, `v4l2grab -W 320 -H 240` writes a valid JPEG. The
green cast of the raw frame is the missing AWB/AEC tuning, not a driver fault.
No DTS or kernel change needed.

**F24 — the board has no hardware MAC address, so its identity lives in the SD
card.** Measured: `ethtool -P eth0` → `00:00:00:00:00:00`, the DTS has no
`local-mac-address`, and the kernel logs `macb f802c000.ethernet: invalid hw
address, using random`. The final address comes from systemd-udevd's
`99-default.link` (`MACAddressPolicy=persistent`), i.e. a hash of
`/etc/machine-id` + interface name: stable across reboots (verified), but **it
changes whenever the rootfs (machine-id) is regenerated**, and the hostname
follows it (`medicam-48db74` today, `medicam-62` on the previous card). Two
boards still get different names, so stage 1 criterion 2 holds; but the
desktop-script contract of section 11 ("target the board as medicam-<mac6>")
requires an identity that survives reflashing. Fix: store the MAC (and later a
board serial) in the on-board 24C256 EEPROM (blank, 32 KiB) and apply it before
`systemd-networkd` → new task in stage 1.5.

**F25 — the DHCP client id is a DUID derived from `machine-id`, not the MAC.**
Measured on the board: `networkctl status eth0` → `DHCPv4 Client ID:
IAID:0x1ba59b32/DUID`, `DUID-EN/Vendor:0000ab11…`, and
`/var/lib/systemd/network/` is empty, i.e. the DUID is regenerated from
`/etc/machine-id` on every boot. Even with the EEPROM MAC restored (F24), a
reflash therefore presents the router with a *new* DHCP client: after one reflash
the board stayed without an address for 4.5 min (carrier 09:03:43 → lease
09:08:18) while the server kept the old lease for the previous client id.
Fix: `fs-overlay/etc/systemd/network/eth0.network.d/10-client-id.conf` with
`[DHCPv4] ClientIdentifier=mac`, so leases follow the EEPROM MAC (F24) and
reflashing neither churns leases nor renames the board at the router.
**Verified:** `DHCPv4 Client ID: 2a:45:d5:48:db:74` and the lease is acquired in
the same second as carrier (was 4.5 min). DHCPv6 keeps a machine-id DUID, which
is irrelevant here — the board only has an IPv6 link-local address.

**F19 — U-Boot/partition margin is thin.** `u-boot.bin` is 580 184 B in a 768 KiB
partition; `zImage` is 5.6 MiB. The `medicam` DTS allots only 6 MiB to the kernel
— too tight for growth. Use the `medicam_nand` values (8 MiB kernel, rootfs at
`0xa00000`), which are consistent with `uboot-env-nand.txt` and
`genimage-nand.cfg`.

**F20 — USB gadgets are available** (`RNDIS`, `ACM`, `MASS_STORAGE`, configfs)
and `usb0` is wired in the DTS. If the desktop script ever needs a network
without LAN infrastructure, a RNDIS/ECM gadget on the DEBUG USB port is possible
without kernel work (needs a small configfs setup unit). Decided: not now,
Ethernet + DHCP.

**F21 — NAND-only flash updates are large.** A 1 GiB raw image written over
SAM-BA is slow; prefer the SD rescue path (`nandwrite` for the raw boot
partitions + `ubiformat`/`ubiupdatevol` for the rootfs volume).

**F27 — NAND control lines have no external pull resistors (netlist, verified).**
Traced in `MediCam.SDF` (rev 1.0): `NAND_RDY_PD5` (NAND `R/B#`, U7.7 ↔ SoC
PD5/K14), `NAND_RE_PD0`, `NAND_WE_PD1`, `NAND_ALE_PD2`, `NAND_CLE_PD3` connect the
NAND directly to the SoC with no external resistor; `CE#` does have a 100 kΩ
pull-up (R42) ahead of the 0 Ω link R43. Microchip's SAM9X60 schematic checklist
documents the EBI/NAND control inputs as internally pulled-up (100 kΩ) to VDDIO at
reset. Recorded as a design observation; it is not needed to explain F26.

**F26 — delay before `RomBOOT` on a cold power-on (open, ROM-side).**
Verified measurements (board, 2026-10-28):

| Situation | Time to `RomBOOT` |
|---|---|
| cold power-on, **bootable** SD card (valid `boot.bin`) | immediate — ROM boots from SD |
| cold power-on, **the same card formatted blank** (Windows format) | **~20 s** |
| cold power-on, blank SD card or **no** SD card (measured earlier) | ~30 s |
| **RESET** pressed at any moment, including during the wait | immediate |

The same physical card gives immediate boot with valid content and ~20 s once
formatted, so the trigger is **card content**, not card presence or loading: the
delay appears only when the ROM finds no valid code on SD and has to fall back to
NAND. That makes it ROM-side behaviour in the NAND-fallback path, not a
power-rail/reset-release effect.

What is still unknown: *why* that fallback path takes 20-30 s on a cold power-on.
NAND readiness is not the answer — `tPOR`/`tVSL` are microseconds to milliseconds,
the ROM only requires a ≤ 100 µs NAND reset time (§17.1.4.7.1), and a RESET press
seconds after power-on boots from NAND immediately, i.e. the NAND is usable within
seconds.

Documented conflict, recorded rather than resolved: TB3380 ("Booting from NAND
Flash on SAM9X60/SAM9X7", §4.5) states that if `RomBOOT` is not displayed the MPU
is probably held in reset or the power sequencing is wrong, and that such an early
failure "cannot be due to the booting process from the NAND Flash device". Our
cold NAND-fallback case shows no `RomBOOT` for 20-30 s while the same hardware
boots from NAND within seconds on a warm reset, so TB3380's generalisation does
not describe this board's behaviour.

Remaining measurements, in order, if this is picked up again:
1. raw-byte capture of DBGU over the whole window (are bytes emitted at all?);
2. timing repeated several cold boots (fixed value = timer, spread = retries);
3. scope `NRST` + `PWRHLD` + NAND `VCC`/`R/B#` during a cold power-on with a
   bootable card vs. without, to see when the SoC starts and when NAND is accessed.

Nothing in Buildroot, AT91Bootstrap or U-Boot can influence this; **decision:
accepted as-is for now** (costs only time-to-first-output).

**F28 — there is no on-die temperature sensor, so `Tm` needs an external part.**
The user application reads the MCU temperature from
`/sys/class/thermal/thermal_zone0/temp`, and its TODO assumes a kernel option
for it; neither the sensor nor that option exists.

* Datasheet features (`SAM9X60-Data-Sheet-DS60001579.md:100`): "One 12-channel
  12-bit Analog-to-Digital Converter with 4/5 wires resistive touchscreen
  support" — no temperature sensor anywhere in the peripheral list (lines 1–90),
  and the SiP datasheet says the same (`SAM9X60-SIP-DataSheet-DS60001580C.md:276`).
* ADC register map (same datasheet, `:60240`): `ADC_CWR` sits at 0x44 and
  `ADC_TSMR`/`ADC_XPOSR`/`ADC_YPOSR`/`ADC_PRESSR` at 0xB0–0xBC (touchscreen).
  The SAMA5D2's `TEMPMR`/`TEMPON` and its temperature channel are absent — the
  SAM9X60 ADC is the touchscreen variant with the temp sensor removed. The
  datasheet itself places temperature sensing outside the chip (`:14151`, RTC
  calibration: "a temperature sensor can be placed close to the crystal
  oscillator").
* Kernel: `sam9x60.dtsi` binds `microchip,sam9x60-adc` through the
  `atmel,sama5d2-adc` fallback to `sama5d2_platform`, which sets no
  `.temp_sensor` and lists no temperature channel. On the board `iio:device0`
  (`f804c000.adc`) exposes `in_voltage0..11` only — no `in_temp*`. There is also
  **no `CONFIG_AT91SAM9X_THERM` anywhere in the 6.12 tree**: the symbol named in
  the app's TODO is invented and can never be enabled.
* Measured on the board (2026-10-29): `/sys/class/thermal` does not exist
  (`CONFIG_THERMAL` is off), no hwmon device is registered, `i2cdetect -y 0`
  shows only 0x30 (OV2640) and 0x50 (EEPROM). `PB14`/`AD3` is muxed by
  `pinctrl_adc_default` but nothing is connected to it (`in_voltage3_raw` =
  14076, floating).

Both ways to get a number are **board changes**, and both measure PCB/case
temperature near the sensor — never the junction:

| Route | Software | Result |
|---|---|---|
| NTC + fixed resistor on a free ADC pin (AD0–AD3/AD6 = PB11/PB12/PB13/PB14/PB17 are free on MediCam) | `CONFIG_THERMAL=y`, `CONFIG_GENERIC_ADC_THERMAL=y`, DT `compatible = "generic-adc-thermal"` with `io-channels = <&adc 3>`, `io-channel-names = "sensor-channel"`, `temperature-lookup-table`, plus a `thermal-zones` entry | real `/sys/class/thermal/thermal_zone0/temp` (m°C) → app unchanged |
| I2C part on the free I2C0 addresses 0x48–0x4F, LM75-compatible | none — `CONFIG_SENSORS_LM75=m` is already in the image and `modprobe lm75` was verified on the board; DT node `compatible = "ti,tmp112"; reg = <0x48>;` | `/sys/class/hwmon/hwmon0/temp1_input` (m°C); no thermal zone, so the app needs a hwmon fallback |

TMP112 (`TMP112AIDRLR`, SOT-563) fits the second route: `ti,tmp112` is in
`drivers/hwmon/lm75.c` (16-bit config register, forced 12-bit/8 Hz, one-shot
cleared) and in `lm75.yaml`, which forbids an `interrupts` property for it;
0.0625 °C/LSB, ±0.5 °C over 0–65 °C, 1.4–3.6 V (runs from `VDD1_3V3`). Runtime
test without a DTB change: `echo tmp112 0x48 > /sys/bus/i2c/devices/i2c-0/new_device`.

**Decision: not enabled.** No sensor is fitted, so `Tm` stays absent (the app
returns nil). Do not enable the `generic-adc-thermal` node before the part is
populated: a floating pin yields a plausible-looking but meaningless
temperature.

**F29 — `/data` was silently dropped from the boot transaction (ordering
cycle).** Measured on the board 2026-10-29 (NAND boot, no SD card): after a
reboot `/data` was not mounted, `medicam.service` and
`medicam-data-init.service` had never been started, while
`medicam-identity`/`-hostname` had; `systemctl start` worked. The cause is our
own unit graph — `medicam-data.service` kept the default dependency set
(`After=basic.target`) while declaring `Before=data.mount local-fs.target`, and
a local mount unit is implicitly `Before=local-fs.target`, while the boot chain
runs `local-fs.target → sysinit.target → basic.target`. The journal spells the
cycle out:

```
data.mount: Found ordering cycle on medicam-data.service/start
data.mount: Found dependency on basic.target/start
... sockets.target → dbus.socket → sysinit.target →
    systemd-tmpfiles-setup.service → local-fs.target → data.mount
data.mount: Job medicam-data.service/start deleted to break ordering cycle
```

The job systemd deletes is **not stable**: with `medicam-data.service/start`
gone, `data.mount` (`Requires=medicam-data.service`) was dropped too,
`medicam-data-init.service` (`Requires=data.mount`) was skipped, and every unit
with `RequiresMountsFor=/data` — i.e. the user application — never entered the
transaction. **The stage 1.5 "`/data` mounted after a reboot" verification
therefore passed by luck**, not because the graph was correct; the defect was
present in the SD-boot configuration as well (a different job happened to lose
the cycle). → fixed in the stage-1.5 unit set (8.3): `medicam-data.service` is
now an early-boot prerequisite modelled on `systemd-remount-fs.service`
(`DefaultDependencies=no`, `After=local-fs-pre.target`, `Before=data.mount
local-fs.target shutdown.target`, `Wants=local-fs-pre.target`,
`Conflicts=shutdown.target`). Rule for future units: **anything that must be
ordered before `local-fs.target` has to use `DefaultDependencies=no`** — with
the default dependency set it is ordered after `basic.target` and can never be
placed before the boot's filesystem targets.

---

## 5. Decisions (locked)

| Topic | Decision |
|---|---|
| Base branch | `medicam` → new `medicam_clean`; `medicam_nand` = reference only |
| Init | systemd 256, `journald` **volatile** |
| Rootfs | **256 M ext4**, no auto-grow (no `e2fsprogs`) |
| Auth | root password (crypt hash in defconfig) + `PermitRootLogin yes` + `PasswordAuthentication yes`; serial console also asks for the password; key-based auth out of scope |
| Hostname | unique per board at first boot: `medicam-<last 6 hex of eth0 MAC>`, set before `systemd-networkd`; the MAC must come from the EEPROM (F24 / task 8.4) |
| Timezone | **UTC** everywhere (tzdata kept, no `BR2_TARGET_LOCALTIME`) |
| Wireless | minimal **Wi-Fi client**: `wpa_supplicant` (no AP/EAP/WPS), `iw`, `wireless-regdb`, util-linux `rfkill`, `linux-firmware` Ralink; kernel `rt2800usb` unchanged |
| Bluetooth | **no BlueZ**; kernel BT stays compiled in (add BlueZ later if a use case appears) |
| Firewall | **drop `iptables` + `nftables`** (also no conntrack); revisit later |
| Camera tooling | `v4l2grab` only (no `v4l-utils`, no streaming stack) |
| NAND layout | **deferred to stage 1.5**, after the trimmed rootfs size is measured; **4 Gbit = floor** for a cost-reduced revision |
| Persistent volume | `/data` mounted from NAND, `/home` → `/data/home` symlink, mount unit resolves the MTD partition **by label** |
| Desktop script channel | Ethernet + DHCP, target by hostname |
| User app | out of scope; only the path/unit contract (section 11) |

---

## 6. Stage 0 — workspace hygiene (≈30 min)

Verified state before this stage: the Windows checkout is **already** on
`medicam_clean` @ `a02b79a` (plan committed), tree clean, equal to
`origin/medicam_clean`. Only the WSL side needs work.

1. Windows: nothing to do (`git rev-parse HEAD` = `a02b79a...`, `git status` clean).
2. Reset the WSL checkout (on the mis-named branch `origin/medicam` @ `b5443b5`):
   `git fetch --all --prune` (or `git fetch local`) ->
   `git checkout -B medicam_clean origin/medicam_clean` (offline alternative:
   `local/medicam_clean`) -> `git branch -D 'origin/medicam'` to drop the name that
   collides with the remote-tracking ref. Verify `git rev-parse HEAD` equals the
   Windows one and `git status --porcelain` is empty. `medicam_nand` stays a local
   branch - its content is what step 4 ports from.
3. Port `.gitattributes` from `medicam_nand` (see F18) as a separate commit.
4. Do **not** merge `medicam_nand`. Port list, reviewed file by file, later:
   `at91bootstrap_nand.fragment`, `uboot-nand.fragment`, `uboot-env-nand.txt`,
   `genimage-nand.cfg`, `post-image-pre.sh`, `flash-nand.sh`, `README_Medicam.md`.

**Exit criteria:** both checkouts on `medicam_clean`, same commit, clean tree.

---

## 7. Stage 1 — lean SD image (≈1.5–2 days incl. 2 builds)

Deliverable: SD image that boots, logs in on serial and over SSH as root with a
password, and contains all infrastructure needed by later stages.

### 7.1 Tasks

| # | Task | Files |
|---|---|---|
| 1.1 | Apply the package manifest (7.3) | `configs/sam9x60_medicam_defconfig` |
| 1.2 | `BR2_TARGET_ROOTFS_EXT2_SIZE="256M"`; `# BR2_PACKAGE_SYSTEMD_HWDB is not set`; drop `BR2_PACKAGE_DT_OVERLAY_MCHP` (+FIT); keep `BR2_TARGET_TZ_INFO=y` with no localtime | same |
| 1.3 | Wire the board overlay: add `$(BR2_EXTERNAL_MCHP_PATH)/board/jk/sam9x60_medicam/fs-overlay/` to `BR2_ROOTFS_OVERLAY` and create the tree | defconfig + overlay |
| 1.4 | Overlay: `etc/ssh/sshd_config` (add `Include /etc/ssh/sshd_config.d/*.conf`, `PermitRootLogin yes`, `PasswordAuthentication yes`); `etc/systemd/system/multi-user.target.wants/sshd.service` → `/usr/lib/systemd/system/sshd.service`; `etc/motd`; `etc/systemd/journald.conf` (`Storage=volatile`); `data/` directory; `home` → `data/home` symlink | overlay |
| 1.5 | Overlay: `usr/local/sbin/medicam-hostname.sh` + `etc/systemd/system/medicam-hostname.service` — `Type=oneshot`, `RemainAfterExit=yes`, `After=local-fs.target`, `Before=systemd-networkd.service`; derives `medicam-<6 hex>` from `/sys/class/net/eth0/address`, writes `/etc/hostname`, calls `hostname`; falls back to 6 chars of `/etc/machine-id` when no MAC | overlay |
| 1.6 | Root password: `BR2_TARGET_ENABLE_ROOT_LOGIN=y` + `BR2_TARGET_GENERIC_ROOT_PASSWD` = a `$6$` crypt hash (store the hash only). **Each `$` must be doubled** (`$$6$$...`), otherwise make expands it and the value silently becomes a cleartext password; the hash must start with `$1$`/`$5$`/`$6$` (`openssl passwd -6 ...`) or Buildroot treats it as plaintext. It ends up in `.config`, the defconfig and the build log | defconfig |
| 1.7 | **Fix `board/microchip/sam9x60/at91_dt.fragment`**: strip the `+` prefixes. Keep the intended content (`OVERLAY_FS`, `NAMESPACES`, cgroup set, `EXT4_FS_POSIX_ACL`, `TMPFS_POSIX_ACL`, `SYN_COOKIES`); leave netfilter decisions out | fragment file |
| 1.8 | DTS: add `&trng { status = "okay"; };` | `board/jk/sam9x60_medicam/at91-sam9x60_medicam.dts` |
| 1.9 | **Guard `board/microchip/at91/post_build.sh`**: wrap the `mv dhcpd.service` / `rm wpa_supplicant.service` steps in existence checks (`[ -f … ] `) so a trimmed package set does not fail the build | `board/microchip/at91/post_build.sh` |
| 1.10 | Additions: `BR2_PACKAGE_UTIL_LINUX_RFKILL=y`, `BR2_PACKAGE_LINUX_FIRMWARE=y` + `BR2_PACKAGE_LINUX_FIRMWARE_RALINK_RT2XX=y` (all three symbols confirmed present in buildroot 2025.02); `BR2_PACKAGE_WGET=y` is **already** in the defconfig (F15 satisfied) | defconfig |
| 1.11 | Build (**clean**, see F22: `make clean && make`), flash, verify (section 12), record numbers (rootfs MiB, `sdcard.img` MiB, `mtdinfo` geometry) | — |

Suggested commit granularity (one concern per commit):

```
configs: trim sam9x60_medicam to a base system image
board: add sam9x60_medicam rootfs overlay (sshd, journald, /data, motd)
board: set unique hostname from MAC at first boot
linux: repair at91_dt fragment (was a saved diff, no options applied)
dts: enable TRNG on sam9x60_medicam
build: make at91 post-build script tolerant of dropped packages
```

### 7.2 Overlay layout (as implemented)

```
board/jk/sam9x60_medicam/
├── post-build.sh                          # /home -> data/home + /data/home (see below)
└── fs-overlay/
    ├── data/                              # stage 1: plain dir; stage 1.5: mount point
    ├── etc/motd
    ├── etc/ssh/sshd_config                # Include sshd_config.d/*.conf, PermitRootLogin yes
    ├── etc/ssh/sshd_config.d/             # left for the desktop script
    ├── etc/systemd/journald.conf.d/10-medicam.conf   # Storage=volatile, RuntimeMaxUse=8M
    ├── etc/systemd/system/medicam-hostname.service
    ├── usr/lib/systemd/system-preset/85-medicam.preset
    └── usr/local/sbin/medicam-hostname.sh
```

Two deviations from the "symlinks are preferred" rule, both forced by the Windows
checkout (`core.symlinks=false` — a committed symlink becomes a plain file there):

* **Unit enablement via preset** `85-medicam.preset`
  (`enable sshd.service`, `enable medicam-hostname.service`). Buildroot runs
  `systemctl --root=$(TARGET_DIR) preset-all` as a rootfs *pre-command* hook, i.e.
  after the overlays are copied, so the preset is equivalent to the
  `multi-user.target.wants/` symlink but survives git on any host.
* **`/home -> data/home` via `post-build.sh`**, not as an overlay entry: the
  target already has an empty `/home` directory and the overlay is copied with
  `rsync -a --ignore-times`, which cannot replace a directory with a symlink.
  Post-build scripts run after the overlay copy.

Drop-ins instead of whole-file replacement where systemd/sshd support them
(`journald.conf.d`, `sshd_config.d`): our settings survive package updates.
`sshd_config` itself is replaced because the stock file has no `Include` line.

### 7.3 Package manifest

**KEEP** — systemd (+networkd, timesyncd, journald), openssh, libopenssl(+`openssl`
CLI), ca-certificates, util-linux (binaries + **rfkill**), bash, grep, nano, kmod
(+tools), strace, usbutils, wget, tzdata, time, which, iproute2, ethtool,
tcpdump, netcat-openbsd, rsync, wpa_supplicant (CLI only), iw, wireless-regdb,
i2c-tools, spi-tools, libgpiod(+tools), linux-tools-iio, v4l2grab, evtest,
fb-test-app, mtd (+UBI tools).

**DROP**

| Group | Packages (size) |
|---|---|
| systemd/misc | systemd-hwdb (13.0), vim+runtime (13.3), **file (8.3 — `/usr/share/misc/magic.mgc`, only rpm selects it)**, kbd (2.0, but see 3.2: systemd pulls it back for the vconsole keymap), bash-completion (0.8), htop, neofetch, tree (busybox applet symlink remains), lua, cjson |
| Python | python3 (17.7), pip (5.5), setuptools (4.1), cryptography (3.3), can (0.9), cffi+pycparser (1.1), canopen, ipy, serial-asyncio, smbus-cffi, spidev, mpio, python-cryptoauthlib, sqlite (1.2) |
| Dev/bench | gdb+gdb-server+gdb-debugger (6.2), lmbench (2.0), trace-cmd (0.7), coremark, dhrystone, whetstone |
| Curiosity glue | cryptoauthlib (+curiosity flag), p11-kit (2.3), libp11, gnutls+tools (2.1, drags libunistring 1.7, nettle, libgcrypt 1.1), wilcmchp_firmware (0.7), dt-overlay-mchp (+FIT) |
| Networking | dhcp (2.1), dhcpcd (0.3), dhcp-server (+relay, delayed-ack), radvd, bridge-utils, ifupdown, nftables (0.6), iptables (0.9), nfs-utils (0.5), can-utils (0.5), net-tools (0.4), iperf3, mii-diag, phy-tool, traceroute, lrzsz |
| Wireless/BT | hostapd (+EAP/WPS) (1.3), wireless-tools, crda, bluez5_utils (2.5) + dbus (0.5) + libglib2 (3.8) |
| Board extras | mpg123 (0.8), dosfstools (+3 sub-options), setserial, rng-tools |

**ADD** — `BR2_PACKAGE_UTIL_LINUX_RFKILL`, `BR2_PACKAGE_LINUX_FIRMWARE` +
`…_RALINK_RT2XX`, `BR2_PACKAGE_WGET`.

Result: rootfs **211 → 63 MiB** (estimate was 110–115), `sdcard.img`
**529 → 273 MiB** (16 MiB FAT + 256 MiB ext4 + 1 MiB offset).

### 7.4 Exit criteria (stage 1 "done") — **all met on 2026-10-28**

1. Boots from SD; serial login **requires the root password** ✔ — the external
   tree's systemd autologin patch is neutralised by
   `fs-overlay/etc/systemd/system/serial-getty@.service.d/10-no-autologin.conf`;
   the journal shows `login[..]: invalid password for 'UNKNOWN' on 'ttyS0'`.
2. `ssh root@medicam-xxxxxx` works with the password ✔; `systemctl is-active sshd`
   = `active`, `is-enabled` = `enabled` ✔; hostname **`medicam-48db74`** = last 6
   hex of the eth0 MAC, `/etc/hosts` follows ✔. Two boards get different names
   (each rootfs has its own machine-id) — but the identity is card-bound, see
   **F24** and the new stage 1.5 task 8.4.
3. `du -sm /` = **50 MiB** on the board (55 MiB in `output/target`), `df` 47.6 MiB
   of 229.9 M; `sdcard.img` = 273 MiB, `zImage` 5.62 MiB — ✔ **recorded**.
4. `mtdinfo /dev/mtd0`: `erasesize 262144`, `pagesize 4096`, **`oobsize 224`**,
   **7** partitions (measured — the DTS has 7 nodes, not 8); kernel reports
   `Micron MT29F8G08ABACAWP, 1024 MiB, SLC, page 4096, OOB 224` ✔.
   **This value gates stage 2 (F2 confirmed: PMECC_OOB must become 224).**
5. `lsusb` works ✔ (it warns "unable to initialize usb spec" because `usb.ids` is
   missing — open item 10.6); a USB stick (`346d:5678`) shows up as `/dev/sda1`
   (58.6 G) and mounts read-only ✔.
6. No build-time regressions: `make` completes with the trimmed set (F7 fixed) ✔.
7. Boot log contains only known-benign messages — classification in LOG 7.12,
   and `CONFIG_MAGIC_SYSRQ` + `CONFIG_BPF_SYSCALL`/`CONFIG_CGROUP_BPF` removed the
   two warnings that were ours to fix.

---

## 8. Stage 1.5 — chip decision + persistent `/data` (≈2–3 h)

### 8.1 Chip decision (driven by the stage 1 measurement)

Content to fit (measured): rootfs **63 MiB** + FRP (~15 MiB) + user app (~20 MiB)
+ `/data` ≈ 98 MiB of the usable volume.

| Chip | Raw | Usable UBIFS | Assessment |
|---|---|---|---|
| 2 Gbit | 256 MiB | ~233 MiB | **Now viable for single-slot**: 98 used, ~135 MiB for `/data`; no A/B, no media, GC margin thin |
| **4 Gbit** | 512 MiB | ~480 MiB | **Recommended**: rootfs + ~380 MiB data; A/B possible as 100 + 100 + 280 |
| 8 Gbit (populated) | 1 GiB | ~960 MiB | Comfortable: A/B + media storage |

Note: 2 Gbit x8 parts are commonly 2 KiB page / 128 KiB block
(e.g. MT29F2G08ABAEA), which changes PEB/LEB size, `numpebs`,
`vid-header-offset`, the partition table and the bootstrap PMECC config. If a
2–4 Gbit part is chosen, prefer a **4 KiB page / 256 KiB block** variant
(e.g. MT29F4G08ABACA-class) so DTS, UBI and bootstrap settings are reused
unchanged.

**Decision (2026-10-28): 4 Gbit ABACA-class = production part, 8 Gbit board =
test bed.** The production pick MT29F2G08ABAEAWP was measured from the datasheet
as 2 KiB page / 64 B OOB / 128 KiB block — a geometry change, not a size change
(PMECC + UBI rework, and not validatable on the 8 Gbit board), so it was
rejected. 4 Gbit ABACA-class keeps the current 4K/256K/224 geometry: only
`numpebs` and the DTS `ubi` size differ. Tree targets the 8 Gbit test bed; the
2G/4G/8G deltas are in README "NAND layout".

### 8.2 Freeze the layout in four places — **[x] frozen 2026-10-28**

DTS kernel = 8 MiB, `ubi` partition = full die (label `ubi`);
`uboot-env-nand.txt`, `genimage-nand.cfg`, `flash-nand.sh` committed as frozen
stage-2 source (tree targets the 8 Gbit test bed; 4 Gbit = the three-number
delta in README).

The same table must appear in: (a) the DTS `partitions`, (b) `uboot-env*.txt`
`mtdparts`/bootargs, (c) `genimage*.cfg`, (d) `flash-nand.sh`. Minimal-change
variant (adopts the `medicam_nand` offsets, which are already self-consistent,
and only extends the UBI region to the real die size):

| Offset | Size | Partition | Content |
|---|---|---|---|
| `0x000000` | 256 KiB | at91bootstrap | `boot.bin.pmecc` |
| `0x040000` | 768 KiB | u-boot | `u-boot.bin` (580 KiB today; keep an eye on it, F19) |
| `0x100000` | 256 KiB | env (redundant) | `uboot-env.bin` |
| `0x140000` | 256 KiB | env (primary) | `uboot-env.bin` |
| `0x180000` | 512 KiB | device tree | `at91-sam9x60_medicam.dtb` |
| `0x200000` | 8 MiB | kernel | `zImage` (5.6 MiB today) |
| `0xA00000` | rest of die | `ubi` | UBIFS volumes |

Resulting UBI space: 1 GiB die → MTD `0xA00000…0x40000000` ≈ **1014 MiB**
(4056 PEB of 256 KiB, ≈ 960 MiB usable UBIFS after the ~2 % bad-block reserve);
4 Gbit → ≈ 502 MiB MTD (≈ 480 MiB usable); 2 Gbit → ≈ 246 MiB MTD (≈ 233 MiB usable).

Suggested volumes: `rootfs` (≈ 300 MiB) + `data` (rest) for a single-slot setup;
or `rootfs_a`/`rootfs_b` (150 + 150) + `data` later. Volumes, not extra MTD
partitions, so `ubimkvol`/`ubirsvol` can resize `/data` in the field.

### 8.3 `/data` mount infrastructure (name-based, layout-agnostic) — **[x] implemented 2026-10-28**

`medicam-data.service` + `data.mount` (`What=ubi0:data`, `Type=ubifs`, `noatime`)
+ `medicam-data-init.service` (creates `/data/home` after mount; mount units
have no `ExecStartPost` — verified) + `medicam-data.sh`. MTD resolved by label,
`ubiattach` when absent, `ubimkvol` at maximum size (rest of UBI, die-agnostic)
on first boot. `data` volume only; `rootfs` volume deferred to stage 2.

**`DefaultDependencies=no` on `medicam-data.service` is mandatory** (F29): the
unit must run before `local-fs.target`, which is impossible for a unit that
keeps the default dependency set (`After=basic.target`), and systemd resolves the
resulting cycle by deleting jobs at random — at worst `medicam-data.service`,
so `data.mount` and every `RequiresMountsFor=/data` unit silently stay out of the
boot. Ordering as built (copy of `systemd-remount-fs.service`):
`DefaultDependencies=no`, `After=local-fs-pre.target`, `Before=data.mount
local-fs.target shutdown.target`, `Wants=local-fs-pre.target`,
`Conflicts=shutdown.target`.

1. `etc/systemd/system/data.mount` (`What=/dev/ubiblock…` **or** UBIFS on
   `ubi0:data`, `Where=/data`, `Type=ubifs`) plus
   `medicam-data.service` (`Before=local-fs.target`), a oneshot that:
   * resolves the MTD index by **label** from `/sys/class/mtd/mtd*/name`
     (never hardcode `-m 6`),
   * `ubiattach -p /dev/mtdN` when `/dev/ubi0` is absent,
   * `ubimkvol` + `mkfs.ubifs` when the `data` volume does not exist,
   * then lets `data.mount` mount it.
2. `RequiresMountsFor=/data` in every unit that writes there.
3. Keep `/etc` on the rootfs (no `/etc` overlay) — updates must stay predictable.

### 8.4 Board identity in the EEPROM (F24) — **implemented 2026-10-28**

The MAC (and therefore the hostname) currently comes from
`/etc/machine-id` via systemd-udevd's `MACAddressPolicy=persistent`, so it changes
whenever the SD card is rewritten — unacceptable for "target the board as
`medicam-<mac6>`" (section 11) and for field updates. The board has a blank
24C256 (32 KiB) on I2C0@0x50 exactly for this kind of data.

1. Define a small record at EEPROM offset 0: magic `MCM1`, 1-byte format version,
   6-byte MAC, 16-byte board serial (ASCII), CRC-8/CRC-16. Everything reads/writes
   through `/sys/bus/i2c/devices/0-0050/eeprom`.
2. `usr/local/sbin/medicam-identity.sh` + `medicam-identity.service`
   (`Before=systemd-networkd.service`, `After=local-fs.target`, ordered before
   `medicam-hostname.service`): if the record is valid → `ip link set dev eth0
   address <mac>`; if invalid → generate a locally-administered MAC from the
   TRNG, write the record, apply it. Idempotent, no rewrite when valid (EEPROM
   endurance).
3. Hostname keeps deriving from the MAC → becomes board-bound and survives
   reflashing. Also `MACAddressPolicy=none` for eth0 (`.link` file) so udev stops
   overriding it, and the identity unit becomes the single source of truth.
4. Factory provisioning is out of scope: first boot programs the EEPROM; the
   desktop script can later overwrite the serial/MAC fields.

   Implementation: `medicam-identity.sh` + `medicam-identity.service` +
   `etc/systemd/network/10-medicam-eth0.link`, record format
   `MCM1 1 mac=<12hex> serial=<16> crc=<cksum>` (96 bytes at offset 0).
   Verified on hardware, including the acceptance test: an SD rewrite changed
   `/etc/machine-id` (21290f5f… → df552997…) and the kernel picked a fresh random
   MAC, yet the board came back with the same MAC `2a:45:d5:48:db:74` and hostname
   `medicam-48db74`, with zero EEPROM rewrites (LOG 7.15). The blank-record path
   works but is only proven manually — test it on a spare board.

**Exit criteria (1.5):** `/data` is mounted from NAND after a reboot and survives
reflashing the SD rootfs; `/home` resolves into `/data/home`; a 50 MiB write +
reboot + read-back passes; **the MAC and hostname stay identical across an SD
rewrite**.

---

## 9. Stage 2 — NAND boot (done; verified on hardware 2026-10-28)

Precondition: stage 1 `mtdinfo` confirmed the geometry (F2) and the layout is
frozen (8.2). All tasks below are implemented and exercised on the board; the
measured evidence lives in LOG 9.12–9.15. Deviations from the original plan are
marked **[as-built]**.

| # | Task |
|---|---|
| 2.1 | `at91bootstrap_nand.fragment`: `# CONFIG_PMECC_OOB_256 is not set` + `CONFIG_PMECC_OOB_224=y`; the regenerated `boot.bin.pmecc` carries `eccOffset = 120` (was 152) and `spareSize = 224` — verified by decoding the 208-byte header |
| 2.2 | `uboot-nand.fragment`: `CONFIG_ENV_IS_IN_NAND`, `ENV_OFFSET=0x140000`, `ENV_OFFSET_REDUND=0x100000`, `ENV_SIZE=0x20000`, frozen fallback `BOOTARGS`/`BOOTCOMMAND`. **[as-built]** no `CONFIG_DEFAULT_DEVICE_TREE` override — there is no medicam DTS in the U-Boot tree, and the runtime DTB comes from NAND anyway |
| 2.3 | `uboot-env-nand.txt`: frozen bootargs (`ubi.mtd=6 root=ubi0:rootfs`), no `mtdparts` on the cmdline (the DTS is the single source of truth), `bootcmd` reads kernel 8 MiB @0x200000 + dtb @0x180000 and `bootz` |
| 2.4 | UBIFS/UBI target options: LEB `0x3e000`, min-IO `0x1000`, UBI PEB `0x40000`. **[as-built]** `UBI_SUBSIZE` stays 512 only because genimage/the fs target need the symbol; the *actual* flashing geometry is an empty `ubiformat` with kernel defaults (no `-s`, no `-O`) — the frozen sub-page 0x200 / VID 0x200 assumption is wrong for this chip: measured LEB 253952, VID offset 4096, data offset 8192 (LOG 9.13) |
| 2.5 | `genimage-nand.cfg` + `post-image-pre.sh` (copies `*.bin.pmecc` → `boot.bin.pmecc`, regenerates `uboot-env.bin` from source with a version-robust `mkenvimage` lookup). **[as-built]** flash `numpebs = 4096` = the WHOLE die, not the UBI-region 4056: genimage sizes the raw image from `numpebs` and the ubi partition ends at the die end 0x40000000 (first build failed with “size of partitions … exceeds flash size”) |
| 2.6 | `flash-nand.sh` — **[as-built]** the rootfs is NOT flashed with `ubiformat -f`: (a) `mkfs.ubifs` output is a multiple of the LEB, not the PEB; (b) on a bare image `ubiformat` takes the `novtbl` path and creates NO volume table, so `root=ubi0:rootfs` would find nothing; (c) `rootfs.ubi` (ubinize) sets `vol_flags=autoresize`, which would swallow the rest of the die and leave nothing for `/data`. Correct flow: `flash_erase` → `ubiformat -y` (empty, kernel geometry) → `ubiattach -m6` → `ubimkvol -N rootfs -S 1238` (~300 MiB) → `ubiupdatevol`. Raw partitions stay `nandwrite -p` (no `-n`: the `.pmecc` file is a 208-byte header + raw code with no embedded ECC). Also: `/dev/mtd0` is a **char** device (test with `[ -c ]`, not `[ -b ]`); `ubidetach -m6` before touching the UBI region (SD boots have ubi0 attached for `/data`); auto-mount the payload FAT at `/boot` |
| 2.7 | Flashing paths: **A (primary)** rescue SD → `flash-nand.sh` → power off → remove SD → NAND boots. **[as-built]** the rescue card is assembled by `make-rescue-sd.sh` from BOTH builds (NAND build's `sdcard.img` + SD-variant `boot.bin`/`u-boot.bin` **and the SD env as `uboot.env`** + NAND `u-boot-nand.bin` + `flash-nand.sh`); shipping the NAND env as `uboot.env` made the card unbootable (bad CRC → curiosity DTB). **B (recovery)** SAM-BA `-b sam9x60d1g` + `-a nandflash:1:8:0xc2605007`, no `::no_extram` (F4) |
| 2.8 | **[x]** Boots with the SD card removed: `RomBOOT → AT91Bootstrap 4.0.11 → U-Boot 2024.07 → kernel 6.12.22 → systemd 256`, `/` on `ubi0:rootfs`, `/data` on `ubi0:data`, identity preserved. **[ ]** the 10× reboot / 5× power-cut matrix is still outstanding (LOG 9.15) |

**Exit criteria:** `RomBOOT → AT91Bootstrap 4.0.11 → U-Boot → kernel → systemd`
with no SD card ✔; SSH reachable ✔ (direct switch; the Wi-Fi bridge drops the
board's RX); `/data` mounted ✔; **10 × reboot and 5 × hard power-cut — pending.**
Known behaviour: ~30 s delay before `RomBOOT` when no SD card is inserted (F26).

---

## 10. Stage 3 — hardening / later

* **Remaining trim candidates (measured, not yet done — ≈ 7 MiB):**
  `kbd` + keymaps + consolefonts ≈ 5 MiB (the board has no display: setting
  `BR2_PACKAGE_SYSTEMD_VCONSOLE_DEFAULT_KEYMAP=""` drops the whole chain),
  `libstdc++` 1.8 MiB + gdb.py (nothing is C++; `BR2_TOOLCHAIN_BUILDROOT_CXX` off).
  Each change needs a clean rebuild (F22), so batch them with the stage 1.5 work.
  Note: busybox applet symlinks (e.g. `usr/bin/tree`) reappear even when the
  standalone package is dropped — they cost no space and are not a regression.
* Watchdog supervision: `&watchdog` is enabled in the DTS; set
  `RuntimeWatchdogSec=` in `/etc/systemd/system.conf`.
* Optional persistent journal: `Storage=persistent` with `SystemMaxUse=` and
  `/var/log/journal` moved onto `/data`.
* A/B rootfs volumes (4/8 Gbit only) + U-Boot env switching + `fw_setenv`
  (needs the `uboot-tools` target package).
* Read-only rootfs + overlayfs (unblocked by the F1 fragment fix).
* Firewall, only if a rule set is designed (F10).
* MCU temperature (F28): no on-die sensor exists. Either an NTC on a free ADC
  pin (`CONFIG_THERMAL` + `CONFIG_GENERIC_ADC_THERMAL` + thermal zone, app
  unchanged) or an LM75-compatible I2C part (`lm75` is already a module, app
  needs a hwmon fallback). Both need a board revision; `Tm` stays absent until
  then.
* Local media storage for the camera, if required (large-capacity NAND only).

---

## 11. Stage 4 — user-application contract (out of scope, fixed here)

The desktop script produces this layout on a freshly booted board:

```
/data/frp/frpc.toml                      # FRP client configuration
/data/app/<name>                         # stripped binary
/data/app/<name>.env                     # optional EnvironmentFile
/data/app/state/                         # persistent state
/usr/lib/systemd/system/<name>.service   # installed by the script
/etc/systemd/system/multi-user.target.wants/<name>.service -> …   # enabled by the script
```

Unit requirements (so it survives reboots and NAND/mount ordering):

```ini
[Unit]
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/data

[Service]
ExecStart=/data/app/<name>
Restart=always
RestartSec=2
StateDirectory=<name>
EnvironmentFile=-/data/app/<name>.env
StandardOutput=journal

[Install]
WantedBy=multi-user.target
```

Script reaches the board as `medicam-<mac6>` over Ethernet + DHCP (root password
from stage 1; key-based auth out of scope, so `sshpass` or a per-device password
change is the script's business). A USB RNDIS/ECM gadget on the DEBUG port is a
possible later alternative (F20) — not implemented now.

---

## 12. Verification matrix (run at every stage)

| Check | Command / expectation |
|---|---|
| Boot / console | serial 115200 8N1, `Welcome to the SAM9X60 MediCam` |
| SSH | `ssh root@medicam-xxxxxx`; `systemctl is-active sshd` → `active` |
| Hostname | `hostname` → `medicam-xxxxxx`; unique across two boards; DHCP lease matches |
| Size | `du -sm /`; `ls -l output/images/sdcard.img` (record in this file) |
| Wi-Fi | `rfkill list`; `iw dev`; RT5370 plugged → `wlan0` present; `wpa_supplicant` associates |
| NAND geometry | `mtdinfo /dev/mtd0` → erasesize 262144, pagesize 4096, oobsize **224**; `dmesg \| grep -i pmecc` |
| NAND data | `mount \| grep /data`; 50 MiB write, reboot, read-back |
| Boot transaction after a reboot | `journalctl -b \| grep -c 'ordering cycle'` → **0**; `systemctl is-active medicam-data.service data.mount medicam-data-init.service` → active ×3; every unit with `RequiresMountsFor=/data` started on its own. **Static, and the real criterion:** `./check-boot-order.sh root@<board>` → exit 0 (162 units / 453 edges / 0 cycles as of 2026-10-29) — a reboot alone is not evidence, systemd breaks cycles by deleting a job at random (F29) |
| NAND boot | SD removed: `RomBOOT` → bootstrap → U-Boot → kernel → systemd |
| Layout consistency | `git grep -n "0x[aA]00000\|numpebs\|mtdparts"` — DTS, env, genimage and flash script must agree |

---

## 13. Risks and rollbacks

| Risk | Mitigation |
|---|---|
| Trimmed config breaks the build (`post_build.sh`, F7) | Task 1.9 before the first build; keep `medicam` pristine for diffing |
| Fragment fix changes more kernel config than expected | Diff `output/build/linux-custom/.config` before/after; keep the fragment minimal |
| OOB 224 assumption wrong | Stage 1 `mtdinfo` decides before any bootstrap change |
| NAND boot never works | Stage 1.5 (`/data` on NAND) is already the shippable fallback; SAM-BA `-d sam9x60d1g` for recovery |
| Root password committed to git | Store only the crypt hash; document per-device rotation in the desktop script |
| CRLF corruption of scripts/fragments from the Windows checkout (F18) | `.gitattributes` from `medicam_nand`; build only in WSL |
| NAND-only update is impractical | SD rescue is the primary flashing path (F21) |
| Thin U-Boot/kernel partitions (F19) | Kernel 8 MiB; monitor `u-boot.bin` size after enabling extra drivers |

Rollback at any stage: every stage is a separate commit on `medicam_clean`;
reverting the stage's commits and rebuilding reproduces the previous image.
`medicam` and `medicam_nand` are never modified by this work.

---

## 14. Appendix A — reproduction commands for the measurements

```bash
# package/image sizes (WSL)
cd ~/src/buildroot-mchp
grep -c '^BR2_PACKAGE_[A-Za-z0-9_]*=y' .config
ls output/build | wc -l
du -sm output/target
ls -l output/images/{sdcard.img,rootfs.ext2,boot.vfat}

# per-package installed sizes
awk -F, '{print $1}' output/build/packages-file-list.txt | sort -u   # package names
# (sizes: lstat each file from packages-file-list.txt against output/target)

# kernel facts
grep -E '^CONFIG_(MTD|MTD_UBI|UBIFS|MTD_BLOCK|USB_|BT_|CFG80211|MAC80211|RT2800|NETFILTER|NF_)' \
     output/build/linux-custom/.config

# at91bootstrap PMECC config
grep -iE 'PMECC|NAND' output/build/at91bootstrap3-*/.config

# on the board
mtdinfo /dev/mtd0 ; dmesg | grep -iE 'nand|pmecc' ; du -sm /
```

## 15. Appendix B — MediCam board files today

```
board/jk/sam9x60_medicam/
├── at91-sam9x60_medicam.dts     # full board DTS: EBI/NAND, I2C0 EEPROM+OV2640,
│                                # SPI1 spidev, FLX2/FLX5 USART, MACB0 RMII, ISI,
│                                # HLCDC disabled, USB0/1/2, watchdog, ADC, RTT/RTC
├── genimage.cfg                 # boot.vfat 16M (zImage, dtb, boot.bin, u-boot.bin, uboot.env)
│                                # + rootfs.ext4; offset 1M
└── uboot-env.txt                # bootcmd loads zImage + dtb from FAT and bootz
                                 # bootargs: root=/dev/mmcblk0p2, cma=16m
```

`configs/sam9x60_medicam_defconfig` — see section 3.1 for the exact delta against
the curiosity headless configuration.

Note: `board/jk/sam9x60_medicam/` on branch `medicam_nand` additionally contains
`fs-overlay/`, `genimage-nand.cfg`, `post-image-pre.sh`, `flash-nand.sh`,
`uboot-env-nand.txt`, `uboot-nand.fragment`, `at91bootstrap_nand.fragment`,
`sam-ba-flash-nand.ps1`, `README_Medicam.md` — ported selectively (section 6).
