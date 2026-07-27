# Microchip Buildroot External - Medicam build

## Install System Dependencies

The following system build dependencies are required.

    sudo apt-get install subversion build-essential bison flex gettext \
    libncurses5-dev texinfo autoconf automake libtool mercurial git-core \
    gperf gawk expat curl cvs libexpat-dev bzr unzip bc python3-dev \
    wget cpio rsync xxd bmap-tools libssl-dev python3-pip python3-distutils

In some cases, buildroot will notify that additional host dependencies are
required.  It will let you know what those are.

## SAM9X60 MediCam — NAND Boot Build

The `sam9x60_medicam_nand_defconfig` produces, in a single build, both an SD
card image (`sdcard.img`) for rescue and a raw NAND image (`medicam-nand.img`)
for production. The SD card also contains every NAND-part file plus a
`/usr/bin/flash-nand.sh` helper script that automates writing the NAND from
the running SD boot.

Tested target hardware:
- SAM9X60D1G-I/4FB (DDR2 SiP, 128 MiB)
- MT29F8G08ABACAWP-IT:C (8 Gbit / 1 GiB NAND, 4 KiB page, 256 KiB eraseblock)
  or the smaller experiment-board 128 MiB NAND (same geometry)

Layout (must match the DTS, U-Boot env, and flash-nand.sh):

| Offset | Size | Part | File written |
|---:|---:|---|---|
| 0x000000 | 256 KiB | at91bootstrap | `boot.bin.pmecc` |
| 0x040000 | 768 KiB | u-boot | `u-boot.bin` |
| 0x100000 | 256 KiB | env (redundant) | `uboot-env.bin` (redundant copy) |
| 0x140000 | 256 KiB | env (primary) | `uboot-env.bin` (primary copy) |
| 0x180000 | 512 KiB | device tree | `at91-sam9x60_medicam.dtb` |
| 0x200000 | 8 MiB | kernel | `zImage` |
| 0xa00000 | 118 MiB | rootfs | `rootfs.ubifs` (UBI) |

Build (Debian/Ubuntu host; for Windows see WSL2 note below):

    cd buildroot-mchp
    BR2_EXTERNAL=$PWD/../buildroot-external-microchip \
        make sam9x60_medicam_nand_defconfig
    BR2_EXTERNAL=$PWD/../buildroot-external-microchip \
        make

The build produces (in `output/images/`):
- `sdcard.img` — bootable SD card with ext4 rootfs + a 256 MiB FAT holding
  every NAND-part file (so the running SD system has access to them) +
  `/usr/bin/flash-nand.sh` installed via the rootfs overlay.
- `medicam-nand.img` — 128 MiB raw NAND image, partition contents
  concatenated (no partition table, no UBI header).

To flash the NAND from a running SD boot on the board:

    # boot from SD, log in
    flash-nand.sh           # flash everything (with y/N confirmation)
    flash-nand.sh kernel    # flash only the kernel
    flash-nand.sh rootfs    # flash only the UBI rootfs
    flash-nand.sh uboot     # flash only u-boot
    flash-nand.sh dtb       # flash only the device tree
    flash-nand.sh bootstrap # flash only at91bootstrap
    flash-nand.sh env       # flash both env copies

After `flash-nand.sh` finishes:
1. `poweroff`
2. Remove the SD card (so the ROM picks NAND, not SDMMC)
3. Power on — the board boots from NAND.

For details on the design rationale, partition geometry, and PMECC settings
see [PLAN_NAND.md](PLAN_NAND.md).

### Editing `uboot-env-nand.txt`

`post-image-pre.sh` regenerates `output/images/uboot-env.bin` from
`board/jk/sam9x60_medicam/uboot-env-nand.txt` on every `make`, so edits
to the env source take effect immediately. Both `medicam-nand.img` and
`sdcard.img` are then re-stamped by genimage and reflect the change.

## Building under WSL2 (Windows)

If your host is Windows, build inside WSL2 (Debian). Cloning into the WSL
native filesystem (`~/src/...`) is strongly recommended over `/mnt/d/...` to
avoid CRLF line-ending issues in scripts.

Two extra setup steps that a fresh WSL2 install needs:

    # 1. Install missing packages (only on a fresh WSL image)
    sudo apt install bison flex libssl-dev python3-pip python3-distutils xxd

    # 2. Strip Windows paths from $PATH (they contain spaces, which
    #    breaks Buildroot's dependency checker). The snippet below goes
    #    at the TOP of ~/.bashrc so it runs even in non-interactive
    #    `bash -c` invocations (i.e. from `wsl -- bash ...`):

    clean_path() {
        local p out=""
        local IFS=':'
        local -a parts
        read -ra parts <<< "$PATH"
        for p in "${parts[@]}"; do
            case "$p" in
                *[' '\"$'\t']*) ;;
                /mnt/?/*) ;;
                *) out="${out:+${out}:}${p}" ;;
            esac
        done
        echo "$out"
    }
    if [ -n "${PATH:-}" ]; then
        export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$(clean_path)"
    fi
    unset -f clean_path

