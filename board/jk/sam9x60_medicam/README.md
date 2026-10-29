MediCam (SAM9X60D1G) — board files
==================================

Board: SAM9X60D1G SiP (128 MiB DDR2 in package), MT29F8G08ABACAWP 1 GiB parallel
NAND, OV2640 on ISI, 24C256 EEPROM @0x50 on I2C0, WS2812 on SPI1, USART2/USART5,
RMII Ethernet, USB host + USB device.

Documents in this directory
---------------------------
PLAN_base_image.md   implementation plan, findings (F1..F28), stages, verification
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

Boot chain and ROM behaviour
----------------------------
Two boot chains, one per defconfig (they differ only in the first two stages):

    SD card (stage 1):
      RomBOOT -> AT91Bootstrap 4.0.11 (sam9x60_curiositysd_uboot)
              -> U-Boot (sam9x60_curiosity_mmc), env in FAT: uboot.env
              -> fatload zImage + at91-sam9x60_medicam.dtb -> bootz

    NAND (stage 2):
      RomBOOT -> AT91Bootstrap 4.0.11 (sam9x60_curiositynf_uboot, NAND presets)
              -> U-Boot (sam9x60_curiosity_nandflash), env in NAND @0x140000
              -> nand read zImage (8 MiB @0x200000) + dtb (@0x180000) -> bootz
              -> root=ubi0:rootfs (UBIFS volume in the `ubi` MTD partition)

The bootloaders are the curiosity ones on purpose: same SiP, same DDR2, same
SDMMC0 padding. A `RomBOOT` line comes from the on-chip ROM, so it says nothing
about the image; after it, every line is AT91Bootstrap or U-Boot.

Decoding the AT91Bootstrap messages you will see on the DBGU (NAND build):

    1-Wire: reset fail / No 1-Wire chip found / Using default information
        The nf_uboot preset looks for a 1-Wire board-info EEPROM. This board has
        none (its identity lives in the 24C256 on I2C0, handled by Linux), so it
        falls back to defaults. Harmless: board sn 0x11600000, rev 0x0.
    NAND: ONFI flash detected / Manufacturer 0x2c Chip 0xd3
        0x2c = Micron; the MT29F8G08ABACAWP answers ONFI. Page 4096, spare 224.
    NAND: Switch to timing mode 3 / Disable On-Die ECC
        Timing mode 3 is the fastest ONFI timing the part supports; on-die ECC is
        disabled because the SAM9X60 PMECC does the ECC work.
    NAND: Initialize PMECC params, cap: 8, sector: 512
        8-bit correction over 512-byte sectors - matches the --pmecc values that
        the ROM read from the header at the start of the bootstrap page.
    NAND: Image: Copy 0xc0000 bytes from 0x40000 to 0x23f00000
        768 KiB of U-Boot read from the u-boot partition into DDR.

ROM boot sequence (datasheet DS60001579 section 17.1.4) - relevant to any
"why does it not boot instantly?" question:

* With **no Boot Configuration Packet (BCP)** in OTP, the ROM tries, in order:
  SDMMC0 -> SDMMC1 -> QSPI0 -> FLEXCOM0-SPI -> NAND Flash, then the SAM-BA
  monitor. A BCP (OTP, one-time) can restrict/reorder this, set the console pin
  and disable JTAG.
* The NAND path sends a reset command and then reads the first page **without
  ECC**. The first 208 bytes must be 52 copies of the same 32-bit PMECC header
  word (`eccOffset`, `sectorSize`, `eccBitReq`, `spareSize`, `nbSectorPerPage`,
  `usePmecc`, key 0xC); the ROM then re-reads with ECC and looks for the ARM
  exception vectors + the download size in vector 6 (< 32 KiB). Because the ROM
  decodes the page with the header the bootstrap carries, **the PMECC OOB size
  in at91bootstrap_nand.fragment must match the real chip** (224 here, not the
  curiosity preset's 256 - PLAN F2).
* SAM-BA 3.9.1 ships a `bootconfig` applet for exactly this, e.g.
  `sam-ba -p serial -d sam9x60d1g -a bootconfig -c readcfg:bcp-otp` or
  `-c writecfg:bcp-otp:DBGU,NFC_IOSET1`. Its text grammar offers
  `SDMMC0_IOSET1`, `QSPI0_IOSET1`, `FLEXCOMx_SPI_IOSETn`, `NFC_IOSET1` and the
  console choice - but **no card-detect option**, even though the SDMMC second
  word has an `ENABLE` bit plus PID/PIN for it. OTP is one-time programmable;
  OTPC emulation mode (SRAM, survives a warm reset, lost at power-off) can
  validate a packet before burning it.

Observed cold-boot behaviour (PLAN F26 - open, not an image problem):

* cold power-on with a **bootable** SD card: boots **immediately** (from SD);
* cold power-on with **the same card formatted blank**: ~20 s before `RomBOOT`;
* cold power-on with a blank card or **no** card: ~30 s before `RomBOOT`;
* **RESET** pressed at any moment, including during that wait: boots immediately.

Because the same physical card is immediate with valid content and slow once
formatted, the trigger is the card's **content**: the delay appears only when the
ROM finds no valid code on SD and falls back to NAND, i.e. it sits in the ROM's
NAND-fallback path. The mechanism is unknown and NAND readiness is not it
(`tPOR`/`tVSL` are microseconds-milliseconds, and a RESET a few seconds after
power-on boots from NAND at once).

Note the documented conflict: Microchip's TB3380 ("Booting from NAND Flash on
SAM9X60/SAM9X7", §4.5) says that if `RomBOOT` is not displayed the MPU is
probably held in reset / power sequencing is wrong. That does not describe this
board - the same hardware boots from NAND within seconds on a warm reset while
showing no `RomBOOT` for 20-30 s on a cold power-on with no valid SD code.
Nothing in Buildroot, AT91Bootstrap or U-Boot can change this.

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

**Do not give `medicam-data.service` the default dependency set.** It has to be
ordered before `local-fs.target`, which a unit with `DefaultDependencies=yes`
can never be (`After=basic.target`), and systemd resolves the resulting ordering
cycle by deleting a job at random. Measured 2026-10-29 (PLAN **F29**): on a NAND
boot it deleted `medicam-data.service/start`, so `data.mount` was dropped too and
`/data` was never mounted — the journal showed

    data.mount: Found ordering cycle on medicam-data.service/start
    data.mount: Job medicam-data.service/start deleted to break ordering cycle

while the user application (and `medicam-data-init.service`) simply never
entered the boot transaction. The unit therefore carries
`DefaultDependencies=no` plus the `systemd-remount-fs.service` ordering set
(`After=local-fs-pre.target`, `Before=data.mount local-fs.target shutdown.target`).
Quick check after any change to the boot-time units:

    journalctl -b | grep -c 'ordering cycle'        # must be 0
    systemctl is-active medicam-data.service data.mount medicam-data-init.service

Checking boot ordering (PLAN F29)
---------------------------------
A reboot is **not** evidence that the ordering graph is sane: systemd breaks an
ordering cycle by deleting one job, and which job it deletes is not stable. So
there is a static check:

    ./check-boot-order.sh root@192.168.3.17        # dump over ssh, then analyse
    sshpass -p 1 ./check-boot-order.sh root@...    # password auth
    ./check-boot-order.sh -f graph.txt             # analyse a saved dump
    ./check-boot-order.sh -f graph.txt old         # regression test of the
                                                   # checker (pre-fix unit)

It dumps the **effective** `After=`/`Before=` of every loaded unit (drop-ins and
implicit default dependencies already merged - exactly what the boot transaction
is built from), builds the "must start before" digraph and reports elementary
cycles: `0 = clean`, `1 = cycles found`, `2 = dump/analysis error`. Run it after
touching any `*.service`/`*.mount`/preset and once on a freshly flashed image.
It runs on the host (the target has no python3, only `systemctl` is needed).
Reference result (2026-10-29, NAND boot): 162 units, 453 edges, 0 unresolved,
**0 cycles**; the same graph with the pre-fix `medicam-data.service` yields 50.

MCU temperature (there is no on-die sensor)
-------------------------------------------
The SAM9X60 has **no temperature sensor at all** - not disabled, absent. PLAN
F28 has the evidence; the short version:

* DATASHEET features: "One 12-channel 12-bit ADC with 4/5-wire resistive
touchscreen support" and nothing else; the ADC register map has the touchscreen
registers (`ADC_TSMR`, `ADC_XPOSR`, `ADC_YPOSR`, `ADC_PRESSR` at 0xB0-0xBC) where
SAMA5D2 has `TEMPMR`/`TEMPON` (0x44).
* KERNEL: `sam9x60.dtsi` reuses `atmel,sama5d2-adc` -> `sama5d2_platform`, which
has no temp channel; the board's `iio:device0` exposes `in_voltage0..11` only.
* `CONFIG_AT91SAM9X_THERM` does not exist in the kernel tree at all (the symbol
named in DeviceProc-go's TODO is invented).
* BOARD today: `/sys/class/thermal` absent (`CONFIG_THERMAL` off), no hwmon
device, `i2cdetect -y 0` shows only 0x30 (OV2640) and 0x50 (EEPROM), PB14/AD3 is
muxed as ADC but unconnected.

So `Tm` (MCU temperature) needs an external part, added on a board revision.
Both routes give PCB/case temperature near the sensor, never the junction:

1. **NTC + fixed resistor on a free ADC pin** (AD0-AD3/AD6 = PB11, PB12, PB13,
   PB14, PB17 are unused on MediCam). Needs `CONFIG_THERMAL=y` +
   `CONFIG_GENERIC_ADC_THERMAL=y` in the kernel fragment and a DT node:

       thermal_sensor: thermal-sensor {
               compatible = "generic-adc-thermal";
               #thermal-sensor-cells = <0>;
               io-channels = <&adc 3>;          /* AD3 = PB14 */
               io-channel-names = "sensor-channel";
               temperature-lookup-table = <...>;  /* mC, raw */
       };

   plus a `thermal-zones` node pointing at it. Result: a real
   `/sys/class/thermal/thermal_zone0/temp` (milli-degrees) and the user
   application works unchanged.
2. **LM75-compatible I2C sensor** on the free I2C0 addresses 0x48-0x4F (TMP112,
   TMP75, LM75B, TCN75, MCP980x...). **No kernel rebuild**: `CONFIG_SENSORS_LM75=m`
   is already in the image (`lm75.ko` in `/lib/modules/.../kernel/drivers/hwmon/`,
   `modprobe lm75` verified on the board). Add a DT node:

       tmp112: temperature-sensor@48 {
               compatible = "ti,tmp112";
               reg = <0x48>;
       };

   Result: `/sys/class/hwmon/hwmon0/temp1_input` (milli-degrees). `lm75` is an
   hwmon driver and registers **no thermal zone**, so the application needs a
   hwmon fallback (`/sys/class/hwmon/hwmon*/temp1_input`, name `tmp112`).
   Test without touching the DTB, as soon as the part is fitted:

       echo tmp112 0x48 > /sys/bus/i2c/devices/i2c-0/new_device
       cat /sys/class/hwmon/hwmon0/temp1_input     # temp1_max/min = Tset/Thyst

   TMP112 notes: `ti,tmp112` is supported by `drivers/hwmon/lm75.c` (16-bit config
   register, forced 12-bit / 8 Hz, one-shot cleared) and listed in `lm75.yaml`,
   which forbids an `interrupts` property for it. 0.0625 °C/LSB, ±0.5 °C
   (0…65 °C), 1.4–3.6 V → runs from `VDD1_3V3`, address 0x48 = ADD0 to GND.

Neither route is enabled in the tree: no sensor is fitted, so `Tm` stays absent
(the app returns nil). Do **not** enable the `generic-adc-thermal` node before
the part is populated - a floating pin reports a plausible but meaningless
temperature.

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

Field flow (verified on hardware 2026-10-28):

    make-rescue-sd.sh                  # -> <nand_output>/images/sdcard-rescue.img
    # Etcher that image on an SD card, insert, power on
    /root/flash-nand.sh                # on the board (auto-mounts its own /boot)
    #   bootstrap -> u-boot -> env x2 -> dtb -> kernel (nandwrite -p, ECC on the fly)
    #   then rootfs: flash_erase -> ubiformat -y -> ubiattach -m6 ->
    #                ubimkvol -N rootfs -S 1238 (~300 MiB) -> ubiupdatevol
    power off, REMOVE the SD card, power on   # board boots from NAND

The SD card is only a programming/rescue medium. Notes from the bring-up:
* the rescue card **must** ship the SD environment as `uboot.env` (16 KiB) and
  the NAND environment as `uboot-env.bin` (256 KiB) — with the NAND env in
  `uboot.env` the SD U-Boot rejects it (bad CRC) and looks for the curiosity DTB;
* the rootfs is a UBIFS **volume** created explicitly, not `ubiformat -f
  rootfs.ubifs` (bare images get no volume table; `rootfs.ubi` would autoresize
  over the whole die and leave nothing for `/data`);
* factory bad blocks near the end of the die make the whole-chip erase report
  EIO; `flash_erase` then erases per block and skips them — expected;
* `/dev/mtd0` etc. are **char** devices.

Measured on the board: `/` = `ubi0:rootfs` 1238 LEBs (299.8 MiB, 28 MiB used),
`/data` = `ubi0:data` 2732 LEBs (661.6 MiB); PEB 256 KiB, LEB 253952, min-I/O
4096, **no sub-pages** (VID header offset 4096, data offset 8192); good PEBs
4052, bad 4, corrupted 0. Rootfs total is also physically smaller than stage 1
because the rootfs is UBIFS-compressed (rootfs.ubifs 33 MiB).

Known behaviour (PLAN F26): with **no SD card inserted** the ROM spends ~30 s on
its default SDMMC attempts before falling through to NAND; with a card inserted
it boots at once. Fixing it means programming a Boot Configuration Packet into
one-time OTP (see PLAN F26 for the three options) — accepted as-is for now.

Host / rebuild strategy
-----------------------
Each output tree owns its **own** host directory - 706 MiB (`output/host`) and
709 MiB (`output-nand/host`). They must never be shared:

    cd ~/src/buildroot-mchp
    make O=output-nand BR2_EXTERNAL=~/src/buildroot-external-microchip sam9x60_medicam_nand_defconfig
    make O=output-nand BR2_EXTERNAL=~/src/buildroot-external-microchip
    #  NO "ln -s output/host output-nand/host"!  See "why" below.

The two trees *looked* able to share one host via a symlink
(`ln -s output/host output-nand/host`), and the first pair of builds happened to
work because the tree that built last had its own `HOST_DIR` string baked into
the tools. It is not a supported configuration: `host-finalize` runs
`support/scripts/fix-rpath`, which calls
`patchelf --make-rpath-relative <HOST_DIR>` on all 445 host ELF files and
**drops every RPATH/RUNPATH entry that does not live below that tree's own
`HOST_DIR`**. So a build in tree A strips the `$ORIGIN`-relative entries that
tree B's tools need, and tree B fails at run time:

    output/host/bin/systemd-tmpfiles: error while loading shared libraries:
      libsystemd-shared-256.so: No such file or directory
    make: *** [fs/ext2/ext2.mk:65: output/images/rootfs.ext2] Error 127

Same for `host/bin/openssl` (falls back to the distro `libssl.so.3`,
`OPENSSL_3.4.0 not found`). The mangling is order-dependent (the last build
wins), which is why it looked like "the SD build broke after the NAND build".

Caveats:
* build the two trees **sequentially**, never in parallel (12 cores; two full
  builds in parallel only thrash - they no longer interfere, though);
* buildroot has **no `dirclean`** target, and `make clean` deletes that tree's
  `host/` (a ~50% rebuild). For a clean rebuild without touching the host use
  `make_clean_no_host.sh` (removes build/target/staging/images, keeps host + dl):

      board/jk/sam9x60_medicam/make_clean_no_host.sh            # SD tree
      board/jk/sam9x60_medicam/make_clean_no_host.sh ~/src/buildroot-mchp output-nand   # NAND tree

* **toggling between the two defconfigs needs NO clean** - the package set is
  identical; just `make <defconfig>` + `make`.
* a clean is only required when the package set changes (PLAN F22).
* both trees share `dl/` (no per-tree download dir), so a rebuild re-downloads
  nothing; `BR2_CCACHE_USE_BASEDIR=y` puts the base dir into the ccache hash,
  so the two trees do **not** share compiler-cache hits (a NAND full rebuild is
  a real compile, ~30-45 min on 12 cores).

Artifact checksums
------------------
`MD5SUMS` records the md5 of the deliverables of the last verified build
(2026-10-29). Paths are relative to the buildroot tree, so it is checked with:

    cd ~/src/buildroot-mchp
    md5sum -c ~/src/buildroot-external-microchip/board/jk/sam9x60_medicam/MD5SUMS

Regenerate it after every image build (rootfs timestamps/uuid change even for an
unchanged package set).

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
  - `genimage-nand.cfg`: flash `numpebs = 2048` (WHOLE 4 Gbit die; 4096 for the
    8 Gbit test bed) and the `ubi` partition size -> `0x1f600000`;
  - `flash-nand.sh`: `rootfs|...|4056|ubi` -> `2024` (the UBI-region PEB count
    `0x1f600000 / 0x40000 = 2024`, distinct from genimage's whole-die numpebs).
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
MD5SUMS                        md5 of the last verified build's images
                               (md5sum -c from the buildroot tree root)
post-image-pre.sh              NAND build: copies boot.bin.pmecc + regenerates
                               uboot-env.bin (run before genimage)
at91bootstrap_nand.fragment    at91bootstrap fragment: PMECC OOB 224, no curiosity
                               LED/EEPROM probe
uboot-nand.fragment            U-Boot fragment: ENV in NAND at 0x140000/0x100000,
                               frozen fallback bootargs/bootcmd
sam-ba-flash-nand.ps1          SAM-BA recovery flash (PowerShell, PLAN F4)
post-build.sh                  rootfs post-build: /home -> data/home symlink
check-boot-order.sh            host-side ordering-cycle check for a running
check-boot-order.py            board (PLAN F29): dump the unit graph, report
                               cycles; "old" mode re-creates the pre-fix bug
fs-overlay/                    rootfs overlay: sshd_config, journald.conf.d,
                               motd, medicam-hostname/identity/data services +
                               helpers, systemd preset, /data mount point
