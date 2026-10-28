# MediCam base image — implementation plan

Status: **agreed, not yet implemented.** Implementation happens in later sessions,
stage by stage, on branch `medicam_clean` (created from `medicam`).

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
**Consequence: a systemd-based trimmed image has a floor of ≈ 85 MiB**, expect
≈ 110–115 MiB after the trim in section 7.3.

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
uses `core.autocrlf=true`, so the *working tree* there is CRLF while the *blobs*
are LF. Measured: `git grep -Il -F -e $'' HEAD -- .` → **0 files**, i.e. the
repository content is LF-clean and no renormalisation is needed; the CRLF seen in
`at91-sam9x60_medicam.dts`, `genimage.cfg`, `uboot-env.txt`,
`board/microchip/sam9x60/at91_dt.fragment` and `board/microchip/at91/post_build.sh`
is checkout-only (`tr -cd '' < file | wc -c` → 543/17/25 on the Windows tree,
0 in the index). The real hazards are therefore (a) files **created** on the
Windows side with a tool that bypasses git's filters, and (b) **lost +x bits**.
`medicam` has no `.gitattributes`; `medicam_nand` added one pinning `*.sh` (+x),
`*.dts`, `*.fragment`, `*_defconfig` to LF. Port it in **stage 0** (extended to the
`*.service`/`*.mount`/`*.preset`/`*.cfg` files stage 1 adds) and keep the audit
`git ls-files -s -- '*.sh' | awk '$1=="100644"{print "not exec:",$4}'` empty.

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

---

## 5. Decisions (locked)

| Topic | Decision |
|---|---|
| Base branch | `medicam` → new `medicam_clean`; `medicam_nand` = reference only |
| Init | systemd 256, `journald` **volatile** |
| Rootfs | **256 M ext4**, no auto-grow (no `e2fsprogs`) |
| Auth | root password (crypt hash in defconfig) + `PermitRootLogin yes` + `PasswordAuthentication yes`; serial console also asks for the password; key-based auth out of scope |
| Hostname | unique per board at first boot: `medicam-<last 6 hex of eth0 MAC>`, set before `systemd-networkd` |
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
| 1.11 | Build, flash, verify (section 12), record numbers (rootfs MiB, `sdcard.img` MiB, `mtdinfo` geometry) | — |

Suggested commit granularity (one concern per commit):

```
configs: trim sam9x60_medicam to a base system image
board: add sam9x60_medicam rootfs overlay (sshd, journald, /data, motd)
board: set unique hostname from MAC at first boot
linux: repair at91_dt fragment (was a saved diff, no options applied)
dts: enable TRNG on sam9x60_medicam
build: make at91 post-build script tolerant of dropped packages
```

### 7.2 Overlay layout (target)

```
board/jk/sam9x60_medicam/fs-overlay/
├── data/                                  # mount point for the NAND volume (stage 1: plain dir)
├── home -> data/home                      # symlink
├── etc/motd
├── etc/ssh/sshd_config
├── etc/systemd/journald.conf
├── etc/systemd/system/medicam-hostname.service
├── etc/systemd/system/multi-user.target.wants/sshd.service -> /usr/lib/systemd/system/sshd.service
└── usr/local/sbin/medicam-hostname.sh
```

Enablement rule: Buildroot cannot run `systemctl enable` in a chroot, so units are
enabled by shipping the `multi-user.target.wants/` symlink (deterministic) — or,
equivalently, by a preset file at
`usr/lib/systemd/system-preset/85-medicam.preset` (`enable sshd.service`), since
`systemctl --root=$(TARGET_DIR) preset-all` runs as a rootfs pre-command hook,
i.e. **after** overlays are copied. Symlinks are preferred.

### 7.3 Package manifest

**KEEP** — systemd (+networkd, timesyncd, journald), openssh, libopenssl(+`openssl`
CLI), ca-certificates, util-linux (binaries + **rfkill**), bash, grep, nano, kmod
(+tools), strace, usbutils, wget, file, tzdata, time, which, iproute2, ethtool,
tcpdump, netcat-openbsd, rsync, wpa_supplicant (CLI only), iw, wireless-regdb,
i2c-tools, spi-tools, libgpiod(+tools), linux-tools-iio, v4l2grab, evtest,
fb-test-app, mtd (+UBI tools).

**DROP**

| Group | Packages (size) |
|---|---|
| systemd/misc | systemd-hwdb (13.0), vim+runtime (13.3), kbd (2.0), bash-completion (0.8), htop, neofetch, tree, lua, cjson |
| Python | python3 (17.7), pip (5.5), setuptools (4.1), cryptography (3.3), can (0.9), cffi+pycparser (1.1), canopen, ipy, serial-asyncio, smbus-cffi, spidev, mpio, python-cryptoauthlib, sqlite (1.2) |
| Dev/bench | gdb+gdb-server+gdb-debugger (6.2), lmbench (2.0), trace-cmd (0.7), coremark, dhrystone, whetstone |
| Curiosity glue | cryptoauthlib (+curiosity flag), p11-kit (2.3), libp11, gnutls+tools (2.1, drags libunistring 1.7, nettle, libgcrypt 1.1), wilcmchp_firmware (0.7), dt-overlay-mchp (+FIT) |
| Networking | dhcp (2.1), dhcpcd (0.3), dhcp-server (+relay, delayed-ack), radvd, bridge-utils, ifupdown, nftables (0.6), iptables (0.9), nfs-utils (0.5), can-utils (0.5), net-tools (0.4), iperf3, mii-diag, phy-tool, traceroute, lrzsz |
| Wireless/BT | hostapd (+EAP/WPS) (1.3), wireless-tools, crda, bluez5_utils (2.5) + dbus (0.5) + libglib2 (3.8) |
| Board extras | mpg123 (0.8), dosfstools (+3 sub-options), setserial, rng-tools |

**ADD** — `BR2_PACKAGE_UTIL_LINUX_RFKILL`, `BR2_PACKAGE_LINUX_FIRMWARE` +
`…_RALINK_RT2XX`, `BR2_PACKAGE_WGET`.

Expected result: rootfs **211 → ~110–115 MiB**, `sdcard.img` **529 → ~273 MiB**.

### 7.4 Exit criteria (stage 1 "done")

1. Boots from SD; serial login **requires the root password**.
2. `ssh root@medicam-xxxxxx` works with the password; `systemctl is-active sshd`
   is `active`; the DHCP lease/DNS name matches `medicam-xxxxxx`; two boards on
   the same LAN get different names.
3. `du -sm /` ≈ 110 MiB and `output/images/sdcard.img` ≈ 273 MiB — **recorded**.
4. `mtdinfo /dev/mtd0` reports `erasesize 262144`, `pagesize 4096`,
   **`oobsize 224`**, 8 partitions; `dmesg | grep -i pmecc` clean.
   **This value gates stage 2.**
5. `lsusb` works; a USB mass-storage stick mounts.
6. No build-time regressions: `make` completes with the trimmed set (proves F7 fixed).

---

## 8. Stage 1.5 — chip decision + persistent `/data` (≈2–3 h)

### 8.1 Chip decision (driven by the stage 1 measurement)

Content to fit: rootfs (~110 MiB) + FRP (~15 MiB) + user app (~20 MiB) + `/data`.

| Chip | Raw | Usable UBIFS | Assessment |
|---|---|---|---|
| 2 Gbit | 256 MiB | ~233 MiB | **Not sufficient**: 110 + data ≈ 96 % full (UBIFS GC degrades), no A/B, no media |
| **4 Gbit** | 512 MiB | ~480 MiB | **Floor**: rootfs + ~350 MiB data; A/B possible as 150 + 150 + 180 |
| 8 Gbit (populated) | 1 GiB | ~960 MiB | Comfortable: A/B + media storage |

Note: 2 Gbit x8 parts are commonly 2 KiB page / 128 KiB block
(e.g. MT29F2G08ABAEA), which changes PEB/LEB size, `numpebs`,
`vid-header-offset`, the partition table and the bootstrap PMECC config. If a
2–4 Gbit part is chosen, prefer a **4 KiB page / 256 KiB block** variant
(e.g. MT29F4G08ABACA-class) so DTS, UBI and bootstrap settings are reused
unchanged.

### 8.2 Freeze the layout in four places

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

### 8.3 `/data` mount infrastructure (name-based, layout-agnostic)

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

**Exit criteria:** `/data` is mounted from NAND after a reboot and survives
reflashing the SD rootfs; `/home` resolves into `/data/home`; a 50 MiB write +
reboot + read-back passes.

---

## 9. Stage 2 — NAND boot attempt (≈2–3 days, hardware-bound)

Precondition: stage 1 `mtdinfo` confirmed the geometry (F2) and the layout is
frozen (8.2).

| # | Task |
|---|---|
| 2.1 | `board/jk/sam9x60_medicam/at91bootstrap_nand.fragment`: `# CONFIG_PMECC_OOB_256 is not set` + `CONFIG_PMECC_OOB_224=y` (adjust to `mtdinfo`); rebuild, verify the regenerated `boot.bin.pmecc` header has `eccOffset = 120` (was 152) |
| 2.2 | Port `uboot-nand.fragment`: `CONFIG_ENV_IS_IN_NAND`, `ENV_OFFSET=0x140000`, `ENV_OFFSET_REDUND=0x100000`, `ENV_SIZE=0x20000`, redundant env, compile-in fallback `BOOTARGS`/`BOOTCOMMAND` (`nand read` kernel + dtb, `bootz`) so a corrupt env still boots |
| 2.3 | Port `uboot-env-nand.txt`: `bootargs=console=ttyS0,115200 earlyprintk ubi.mtd=<n> root=ubi0:rootfs rootfstype=ubifs rw rootwait cma=16m atmel.pm_modes=standby,ulp0`; `bootdelay=1`; bootcmd reads kernel/dtb from NAND |
| 2.4 | UBIFS/UBI target options: `BR2_TARGET_ROOTFS_UBIFS` with LEB `0x3e000`, min-IO `0x1000`, subpage `0x200`; UBI `pebsize 0x40000`, `numpebs` = UBI MTD size / 256 KiB, volume name `rootfs` |
| 2.5 | Port `genimage-nand.cfg` + `post-image-pre.sh` (regenerate `uboot-env.bin` from source, copy `*.bin.pmecc` → `boot.bin.pmecc`); sizes must match 8.2 |
| 2.6 | Rewrite `flash-nand.sh` for the frozen layout: `nandwrite` per raw partition (bootstrap PMECC'd, u-boot, env ×2, dtb, kernel), then `ubiformat /dev/mtd<ubi>` + `ubiupdatevol /dev/ubi0_0` for the rootfs. **Never raw-`nandwrite` a UBI image into the UBI region.** |
| 2.7 | Flashing paths: **A (primary)** boot SD → run `flash-nand.sh` → power off → remove SD → NAND boots. **B (recovery)** SAM-BA `-d sam9x60d1g` + `-a nandflash:1:8:0xc2605007` (no `::no_extram`), documented with the DDR2 explanation (F4) |
| 2.8 | Boot with the SD card removed; validate, then repeat power-cut testing |

**Exit criteria:** `RomBOOT → AT91Bootstrap 4.0.11 → U-Boot → kernel → systemd`
with no SD card; SSH reachable; `/data` mounted; 10 × reboot and 5 × hard
power-cut without corruption.
**On failure:** capture the DBGU log, keep stage 1.5 as the shipping
configuration (SD rootfs + NAND `/data`), record findings in this file.

---

## 10. Stage 3 — hardening / later

* Watchdog supervision: `&watchdog` is enabled in the DTS; set
  `RuntimeWatchdogSec=` in `/etc/systemd/system.conf`.
* Optional persistent journal: `Storage=persistent` with `SystemMaxUse=` and
  `/var/log/journal` moved onto `/data`.
* A/B rootfs volumes (4/8 Gbit only) + U-Boot env switching + `fw_setenv`
  (needs the `uboot-tools` target package).
* Read-only rootfs + overlayfs (unblocked by the F1 fragment fix).
* Firewall, only if a rule set is designed (F10).
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
