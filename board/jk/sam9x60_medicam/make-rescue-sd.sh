#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# make-rescue-sd.sh — assemble the field/programming SD card for stage 2
# (NAND boot). Result: sdcard-rescue.img — an SD that BOOTS FROM SD (SD
# bootloaders) and carries everything flash-nand.sh needs to program the NAND.
#
# Why this combines TWO builds (see PLAN section 8 / LOG 9):
#   * The NAND build's own sdcard.img carries all NAND payloads on its 256 MiB
#     FAT partition (boot.bin.pmecc, u-boot.bin, uboot-env.bin, zImage, dtb,
#     rootfs.ubifs) — but its bootloaders are NAND variants and cannot boot
#     from SD (they look for U-Boot on NAND).
#   * Boot-from-SD requires SD-variant bootloaders, which only the SD build
#     produces (Buildroot builds one bootloader variant per defconfig).
#   * So: base = NAND sdcard.img, then swap boot.bin/u-boot.bin for the SD
#     variants, keep the NAND u-boot as u-boot-nand.bin (flash-nand.sh reads
#     that name — see its PARTITIONS table), add flash-nand.sh.
#   * zImage and dtb are identical in both builds — no swap needed.
#
# The FAT partition starts at byte offset 1 MiB (genimage offset = 1M in both
# genimage.cfg and genimage-nand.cfg). mtools addresses it with the "@@offset"
# syntax, offset in BYTES (verified against a built sdcard.img).
#
# Usage (run in WSL; needs mtools):
#   make-rescue-sd.sh [nand_output] [sd_output] [/dev/sdX]
#     nand_output  default: ~/src/buildroot-mchp/output-nand
#     sd_output    default: ~/src/buildroot-mchp/output
#     /dev/sdX     optional: also dd the result onto a plugged SD card
#   Result: <nand_output>/images/sdcard-rescue.img
#
# Field flow:
#   Etcher/dd sdcard-rescue.img -> insert SD -> boot (serial 115200 8N1) ->
#   /boot/flash-nand.sh -> power off -> remove SD -> board boots from NAND.

set -eu

NAND_DIR=${1:-"$HOME/src/buildroot-mchp/output-nand"}
SD_DIR=${2:-"$HOME/src/buildroot-mchp/output"}
DEV=${3:-}

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FLASH_SH="$HERE/flash-nand.sh"
BASE_IMG="$NAND_DIR/images/sdcard.img"
OUT_IMG="$NAND_DIR/images/sdcard-rescue.img"

# FAT partition offset in the base image (bytes): 1 MiB.
FAT_OFF=1048576

die() { echo "make-rescue-sd.sh: ERROR: $*" >&2; exit 1; }

command -v mcopy >/dev/null 2>&1 || die "mtools not installed (run: sudo apt install mtools)"
command -v mdir  >/dev/null 2>&1 || die "mtools not installed (run: sudo apt install mtools)"

[ -f "$BASE_IMG" ]            || die "NAND sdcard.img not found: $BASE_IMG (build sam9x60_medicam_nand_defconfig first)"
[ -f "$SD_DIR/images/boot.bin" ]   || die "SD boot.bin not found: $SD_DIR/images/boot.bin (build sam9x60_medicam_defconfig first)"
[ -f "$SD_DIR/images/u-boot.bin" ] || die "SD u-boot.bin not found: $SD_DIR/images/u-boot.bin"
[ -f "$NAND_DIR/images/u-boot.bin" ] || die "NAND u-boot.bin not found: $NAND_DIR/images/u-boot.bin"
[ -f "$FLASH_SH" ]            || die "flash-nand.sh not found next to this script"

echo "==> base NAND image : $BASE_IMG"
echo "==> SD bootloaders  : $SD_DIR/images/{boot.bin,u-boot.bin}"
echo "==> output          : $OUT_IMG"

cp -f "$BASE_IMG" "$OUT_IMG"

# mcopy into the FAT partition at byte offset 1 MiB. -o allows overwriting
# (the NAND image's boot.bin/u-boot.bin are replaced by the SD variants).
mcopy -o -i "$OUT_IMG"@"@"$FAT_OFF "$SD_DIR/images/boot.bin"      ::/boot.bin
mcopy -o -i "$OUT_IMG"@"@"$FAT_OFF "$SD_DIR/images/u-boot.bin"    ::/u-boot.bin
mcopy -o -i "$OUT_IMG"@"@"$FAT_OFF "$NAND_DIR/images/u-boot.bin"  ::/u-boot-nand.bin
mcopy -o -i "$OUT_IMG"@"@"$FAT_OFF "$FLASH_SH"                    ::/flash-nand.sh

echo "==> boot partition now contains:"
mdir -i "$OUT_IMG"@"@"$FAT_OFF ::/

if [ -n "$DEV" ]; then
    [ -b "$DEV" ] || die "$DEV is not a block device"
    echo
    echo "This will OVERWRITE the entire SD card $DEV."
    printf 'Continue? [y/N] '
    read -r ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) die "aborted by user" ;;
    esac
    echo "==> writing $OUT_IMG -> $DEV"
    dd if="$OUT_IMG" of="$DEV" bs=1M conv=fsync status=progress
    echo "==> done. Eject the card, insert it in the board, boot on serial."
else
    echo
    echo "==> sdcard-rescue.img ready. Write it with balenaEtcher (or:"
    echo "    sudo dd if=$OUT_IMG of=/dev/sdX bs=1M conv=fsync)."
fi
