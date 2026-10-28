MediCam (SAM9X60D1G) — board files
==================================

Board: SAM9X60D1G SiP (128 MiB DDR2 in package), MT29F8G08ABACAWP 1 GiB parallel
NAND, OV2640 on ISI, 24C256 EEPROM @0x50 on I2C0, WS2812 on SPI1, USART2/USART5,
RMII Ethernet, USB host + USB device.

Documents in this directory
---------------------------
PLAN_base_image.md   implementation plan, findings (F1..F21), stages, verification
                     matrix. Section 0 holds the working rules for future sessions.
LOG_base_image.txt   reproducible build/verify log, step by step, with measured
                     values. Update it in the same commit as the stage it documents.

Build from a clean checkout
----------------------------
Host: WSL2 Debian (full host preparation: LOG_base_image.txt section 1).

1. Host preparation (once). The Windows PATH must not leak into WSL, otherwise
   the Windows make/gcc/find shadow the Linux ones:

       sudo tee /etc/wsl.conf >/dev/null <<'EOF'
       [interop]
       appendWindowsPath = false
       EOF
       # then, from PowerShell:  wsl --shutdown
       sudo apt install -y git make binutils build-essential diffutils gcc g++ bash \
            patch gzip bzip2 perl tar cpio unzip rsync file bc findutils wget \
            libssl-dev libncurses-dev ca-certificates

2. Two sibling trees (the external tree must be reachable from the buildroot one):

       git clone -b linux4microchip-2025.04 \
           https://github.com/linux4microchip/buildroot-mchp.git ~/src/buildroot-mchp
       git clone -b medicam_clean \
           https://github.com/kapojko/buildroot-external-microchip.git \
           ~/src/buildroot-external-microchip

3. Configure and build:

       cd ~/src/buildroot-mchp
       make BR2_EXTERNAL=../buildroot-external-microchip sam9x60_medicam_defconfig
       make -j$(nproc) 2>&1 | tee ~/src/build-medicam.log

   A cold build takes ~30-45 min and downloads ~500 MB of linux-firmware data
   (only the Ralink RT2xx blobs are installed). An incremental build takes
   minutes: BR2_EXTERNAL is only needed for the defconfig selection, the
   resulting .config carries it.

4. Result: `output/images/sdcard.img` (~273 MiB) — write it to an SD card
   (balenaEtcher on Windows, `dd` on Linux), insert, boot on the DBGU console
   at 115200 8N1.

**`make` never removes files from `output/target`.** After disabling packages,
the old files stay there and still end up in the images. Two ways out:

* dropping one package (no toolchain change) — delete its files by hand, then
  just regenerate the images (seconds, no recompile):
  `rm -f <files of that package in output/target>` +
  `rm -f output/images/{rootfs.ext2,rootfs.tar,sdcard.img,boot.vfat}` + `make`;
* anything that changes the toolchain or several packages at once — clean:

       make clean && make -j$(nproc)      # dl/ is kept, nothing re-downloads

One harmless message is expected during image creation:

       "/.../target/home" already exists and is not a directory.

`makedevs` applies the `d /home` entry of `system/device_table.txt` to our
`/home -> data/home` symlink (exit code stays 0, the symlink survives). The
runtime counterpart of that rule is masked by `fs-overlay/etc/tmpfiles.d/home.conf`.

Boot chain (SD card, stage 1)
-----------------------------
RomBOOT -> AT91Bootstrap 4.0.11 (sam9x60_curiositysd_uboot) -> U-Boot
(sam9x60_curiosity_mmc) -> zImage + at91-sam9x60_medicam.dtb from the FAT
partition (bootz). The bootloaders are the curiosity ones on purpose: same SiP,
same DDR2, same SDMMC0 wiring.

Root password
-------------
The image ships a root password so that the serial console and SSH both ask for
it (PLAN decision "Auth": password login, no key auth yet).

* Current value: `1` — an intentionally known, weak first-boot password, stored
  in the defconfig **only as a crypt hash** (`$6$`, SHA-512).
* To change it, put the new hash in
  `configs/sam9x60_medicam_defconfig`:

      # 1. generate a hash ($1$=md5, $5$=sha256, $6$=sha512)
      HASH=$(openssl passwd -6 -salt medicam 'new-password')

      # 2. Buildroot/kconfig runs the value through make, so double every '$'
      echo "$HASH" | sed 's/\$/$$/g'
      #   e.g. $6$medicam$abc...  ->  $$6$$medicam$$abc...

      # 3. paste the doubled value
      BR2_TARGET_GENERIC_ROOT_PASSWD="$$6$$medicam$$abc..."

* A value that does **not** start with `$1$`/`$5$`/`$6$` is taken as a plaintext
  password and hashed at build time — that leaks the password into `.config` and
  the build log, so always use the hash form.
* Rebuild (or `make openssh-rebuild` is not enough — the shadow file is written
  during target-finalize, so `make` again after the defconfig change).
* Per-device rotation is the desktop script's business (PLAN section 11).

Board identity
---------------
The SoC has no factory MAC address, so the MAC (and the hostname derived from it)
is stored in the on-board 24C256 EEPROM, I2C0 @0x50 - otherwise it would come
from systemd's machine-id hash and change on every SD rewrite.

* record, 96 ASCII bytes at EEPROM offset 0:
  `MCM1 1 mac=<12 hex> serial=<16 chars> crc=<cksum>` (cksum over the prefix)
* `medicam-identity.service` runs before `medicam-hostname.service` and
  `systemd-networkd`; a valid record is applied and never rewritten, a blank or
  corrupt one is programmed once (adopting the current address, else a
  TRNG-generated locally-administered MAC)
* inspect: `dd if=/sys/bus/i2c/devices/0-0050/eeprom bs=96 count=1 | tr -d '\x00'`
* reset (new identity on next boot): zero the first 96 bytes -
  `dd if=/dev/zero of=/sys/bus/i2c/devices/0-0050/eeprom bs=96 count=1 conv=notrunc`
* the `serial` field stays `0000000000000000` until factory/desktop provisioning
  writes it (same record, same checksum rule)
* the DHCP client id is the MAC as well (`eth0.network.d/10-client-id.conf`,
  `ClientIdentifier=mac`): networkd's default DUID comes from the machine-id, so
  without this a reflash looks like a new client to the router and the board can
  sit without an address for minutes (observed: 4.5 min)

Hostname
--------
Every board would otherwise be `sam9x60_medicam` (BR2_TARGET_GENERIC_HOSTNAME),
so `medicam-hostname.service` (from fs-overlay) renames the board at first boot
to `medicam-<last 6 hex digits of the eth0 MAC>`, before systemd-networkd starts.
Fallback when eth0 has no MAC: first 6 hex digits of `/etc/machine-id`.

Persistent data
---------------
`/data` is the upload/persistent area; `/home` is a symlink to `/data/home`.
Since stage 1.5 `/data` is a UBIFS volume on the NAND UBI region, mounted at
boot by `data.mount` (prepared by `medicam-data.service`; before stage 1.5 it
was a plain directory in the rootfs). The desktop script and the user
application reach it through the contract in PLAN section 11
(`RequiresMountsFor=/data`).

Two builds and the field flow (stage 2)
----------------------------------------
There are two defconfigs; both are kept. Buildroot builds one bootloader
variant per build, so neither can do the other's job:

| Defconfig | Tree | Produces | Role |
|---|---|---|---|
| `sam9x60_medicam_defconfig` | `output/` (in-tree) | SD-runtime `sdcard.img` | fallback + dev/debug image |
| `sam9x60_medicam_nand_defconfig` | `output-nand/` (`O=`) | NAND payloads + a rescue base image (256 M FAT carrying every payload incl. `rootfs.ubifs`) | the field/programming build |

The NAND build's own `sdcard.img` cannot boot from SD (its bootloaders are
NAND variants). The **rescue card** is assembled from both builds:

    make-rescue-sd.sh            # default: output-nand/ + output/
    #  base   = NAND sdcard.img  (256 M FAT: all NAND payloads)
    #  swap   = SD boot.bin / u-boot.bin  (so the card boots from SD)
    #  add    = u-boot-nand.bin (NAND u-boot payload) + flash-nand.sh
    #  result = <nand_output>/images/sdcard-rescue.img
    #  needs  mtools on the host (sudo apt install mtools)

Field flow: Etcher `sdcard-rescue.img` -> boot -> `/boot/flash-nand.sh` -> power
off -> remove the SD card -> the board boots from NAND (no SD needed). The SD
card is only a programming/rescue medium; the SD defconfig stays as the
fallback shipping config and the everyday dev image.

Host / rebuild strategy
-----------------------
The NAND tree reuses the SD tree's host toolchain instead of recompiling it:

    cd ~/src/buildroot-mchp
    make O=output-nand BR2_EXTERNAL=~/src/buildroot-external-microchip sam9x60_medicam_nand_defconfig
    ln -s output/host output-nand/host     # share the 723 MiB host (paths stay valid)
    make O=output-nand BR2_EXTERNAL=~/src/buildroot-external-microchip

Caveats:
* build the two trees **sequentially**, never in parallel (shared host dir);
* buildroot has **no `dirclean`** target, and `make clean` deletes `output/host`
  (a ~50% rebuild). For a clean rebuild without touching the host use
  `make_clean_no_host.sh` (removes build/target/staging/images, keeps host + dl):

      board/jk/sam9x60_medicam/make_clean_no_host.sh            # SD tree
      board/jk/sam9x60_medicam/make_clean_no_host.sh ~/src/buildroot-mchp output-nand   # NAND tree

* **toggling between the two defconfigs needs NO clean** - the package set is
  identical; just `make <defconfig>` + `make`.
* a clean is only required when the package set changes (PLAN F22).

Recovery (SAM-BA)
-----------------
If the SD rescue path is unavailable (dead rootfs, first bring-up), flash the
raw `medicam-nand.img` over USB-CDC with `sam-ba-flash-nand.ps1` (PowerShell,
run on Windows). It uses `-b sam9x60d1g` (correct SiP DDR2 preset, PLAN F4) and
`-a nandflash:1:8:0xc2605007` with the applet buffer in DRAM (no `::no_extram`).
Writing ~1 GiB over serial is slow - the SD rescue path is the primary one
(PLAN F21).

NAND layout (frozen)
--------------------
The same table is frozen in the DTS partitions node, `uboot-env-nand.txt`,
`genimage-nand.cfg` and `flash-nand.sh`:

| Offset | Size | Partition | Content |
|---:|---:|---|---|
| 0x000000 | 256 KiB | at91bootstrap | `boot.bin.pmecc` |
| 0x040000 | 768 KiB | u-boot | `u-boot.bin` |
| 0x100000 | 256 KiB | env (redundant) | `uboot-env.bin` |
| 0x140000 | 256 KiB | env (primary) | `uboot-env.bin` |
| 0x180000 | 512 KiB | device tree | `at91-sam9x60_medicam.dtb` |
| 0x200000 | 8 MiB | kernel | `zImage` |
| 0xa00000 | rest of die | ubi | UBIFS volumes |

The UBI region holds UBIFS *volumes* (stage 1.5: `data` only; stage 2 adds
`rootfs`). `medicam-data.sh` finds the region by its label (`ubi`), never by a
hardcoded index, and sizes the `data` volume to the rest of the UBI region.

Changing the NAND density (2 / 4 / 8 Gbit)
------------------------------------------
* **8 Gbit <-> 4 Gbit: a size change only** (same geometry, recommended path).
  The current MT29F8G08ABACAWP and the production MT29F4G08ABACA-class both are
  4 KiB page / 256 KiB block / OOB 224. Everything transfers; the UBI region
  grows/shrinks. In the tree (8 Gbit test bed) the ubi partition is
  `0xa00000..0x40000000` = `0x3f600000`. For 4 Gbit change exactly three
  numbers:
  - DTS: `ubi@a00000` reg -> `<0xa00000 0x1f600000>` (ends at `0x20000000`);
  - `genimage-nand.cfg`: `numpebs = 2024` and the `ubi` partition size ->
    `0x1f600000`;
  - `flash-nand.sh`: `rootfs|...|4056|ubi` -> `2024`.
* **2 Gbit (e.g. MT29F2G08ABAEAWP): a geometry change, not a size change.**
  Measured from the datasheet: 2,112-byte page (2,048 + 64), 128 KiB block -
  i.e. 2 KiB page / 64 B OOB / 128 KiB block. That invalidates the whole
  stage-2 stack built here: bootstrap PMECC (different OOB/page => eccOffset
  and the PMECC_OOB_* config), UBI geometry (PEB 128 KiB, LEB 0x1f000,
  min-I/O 2 KiB, numpebs ~1968, vid-header-offset), genimage flash geometry,
  and it cannot be validated on the 8 Gbit board at all. Avoid unless the
  board is re-designed around it; if it is ever needed, do it as a separate
  configuration, never by editing this one.

Layout of this directory
------------------------
at91-sam9x60_medicam.dts       board device tree (NAND, I2C0, SPI1, USARTs, MACB0,
                               ISI/OV2640, USB, watchdog, TRNG)
genimage.cfg                   SD image: 1 MiB offset, 16 MiB boot.vfat
                               (zImage, dtb, boot.bin, u-boot.bin, uboot.env),
                               256 MiB ext4 rootfs
uboot-env.txt                  U-Boot environment (SD boot: bootz from FAT)
uboot-env-nand.txt             U-Boot environment (NAND boot, stage 2, frozen)
genimage-nand.cfg              NAND build images (stage 2, frozen)
flash-nand.sh                  SD-rescue NAND flasher (stage 2, frozen)
make-rescue-sd.sh              assemble the rescue SD from both builds (mtools)
make_clean_no_host.sh          clean a buildroot output without touching host
post-image-pre.sh              NAND build: copies boot.bin.pmecc + regenerates
                               uboot-env.bin (run before genimage)
at91bootstrap_nand.fragment    at91bootstrap fragment: PMECC OOB 224, no curiosity
                               LED/EEPROM probe
uboot-nand.fragment            U-Boot fragment: ENV in NAND at 0x140000/0x100000,
                               frozen fallback bootargs/bootcmd
sam-ba-flash-nand.ps1          SAM-BA recovery flash (PowerShell, PLAN F4)
post-build.sh                  rootfs post-build: /home -> data/home symlink
fs-overlay/                    rootfs overlay: sshd_config, journald.conf.d,
                               motd, medicam-hostname/identity/data services +
                               helpers, systemd preset, /data mount point
