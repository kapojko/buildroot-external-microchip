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

Hostname
--------
Every board would otherwise be `sam9x60_medicam` (BR2_TARGET_GENERIC_HOSTNAME),
so `medicam-hostname.service` (from fs-overlay) renames the board at first boot
to `medicam-<last 6 hex digits of the eth0 MAC>`, before systemd-networkd starts.
Fallback when eth0 has no MAC: first 6 hex digits of `/etc/machine-id`.

Persistent data
---------------
`/data` is the upload/persistent area; `/home` is a symlink to `/data/home`.
In stage 1 `/data` is a plain directory in the rootfs; stage 1.5 mounts the NAND
UBI volume over it.

Layout of this directory
------------------------
at91-sam9x60_medicam.dts       board device tree (NAND, I2C0, SPI1, USARTs, MACB0,
                               ISI/OV2640, USB, watchdog, TRNG)
genimage.cfg                   SD image: 1 MiB offset, 16 MiB boot.vfat
                               (zImage, dtb, boot.bin, u-boot.bin, uboot.env),
                               256 MiB ext4 rootfs
uboot-env.txt                  U-Boot environment (bootz from FAT)
post-build.sh                  rootfs post-build: /home -> data/home symlink
fs-overlay/                    rootfs overlay: sshd_config, journald.conf.d,
                               motd, medicam-hostname.service + helper,
                               systemd preset, /data mount point
