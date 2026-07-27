#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# flash-nand.sh — write SAM9X60-Medicam NAND from files on the SD card boot
# partition. Operator boots from SD with the medicam-nand build, mounts the
# boot partition at /boot, runs this script, powers off, removes the SD card,
# and the next power-on boots directly from NAND.
#
# Usage:
#   flash-nand.sh                # flash everything (with confirmation prompt)
#   flash-nand.sh all            # same as above, skips prompt
#   flash-nand.sh bootstrap      # flash only at91bootstrap
#   flash-nand.sh uboot          # flash only u-boot
#   flash-nand.sh env            # flash both u-boot env copies
#   flash-nand.sh dtb            # flash only the device tree
#   flash-nand.sh kernel         # flash only the kernel
#   flash-nand.sh rootfs         # flash only the UBI rootfs
#
# Partition layout (must match DTS / U-Boot mtdparts):
#   mtd0   at91bootstrap    256 KiB   raw, PMECC-encoded
#   mtd1   u-boot           768 KiB   raw
#   mtd2   env_redundant    128 KiB   raw
#   mtd3   env              128 KiB   raw
#   mtd4   device tree      512 KiB   raw
#   mtd5   kernel             8 MiB   raw (zImage)
#   mtd6   rootfs           118 MiB   UBI (formatted)

set -eu

BOOT=/boot

log()  { printf '\033[1;32m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[%s] WARN:\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# Erase-block geometry. The MT29F8G08 has 256 KiB erase blocks.
EB_KB=256

# Partition layout: name|device|file-on-boot|eraseblocks|kind
#   kind: raw=flash_erase + nandwrite; ubi=flash_erase + ubiformat
#   "env" is intentionally omitted here — handled by flash_env_both() because
#   it needs to write to BOTH mtd2 (redundant) and mtd3 (primary).
PARTITIONS="
bootstrap|/dev/mtd0|boot.bin.pmecc|1|raw
uboot|/dev/mtd1|u-boot.bin|6|raw
dtb|/dev/mtd4|at91-sam9x60_medicam.dtb|4|raw
kernel|/dev/mtd5|zImage|32|raw
rootfs|/dev/mtd6|rootfs.ubifs|472|ubi
"

confirm() {
    [ "${ASSUME_YES:-0}" = "1" ] && return 0
    printf '\nThis will ERASE and rewrite the on-board NAND flash.\n'
    printf 'Continue? [y/N] '
    read -r ans
    case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) die "aborted by user" ;;
    esac
}

check_prereqs() {
    command -v flash_erase >/dev/null || die "flash_erase not found (install mtd-utils)"
    command -v nandwrite    >/dev/null || die "nandwrite not found (install mtd-utils)"
    command -v ubiformat    >/dev/null || die "ubiformat not found (install mtd-utils)"

    [ -d "$BOOT" ]           || die "$BOOT not mounted"
    [ -b /dev/mtd0 ]         || die "/dev/mtd0 missing — kernel did not register NAND"

    # Show operator what's there.
    echo
    log "NAND partitions detected:"
    if [ -r /proc/mtd ]; then
        cat /proc/mtd
    else
        ls -l /dev/mtd*
    fi
    echo
}

write_raw() {
    # $1 = device, $2 = file on $BOOT, $3 = eraseblock count
    dev=$1; file=$2; cnt=$3
    [ -f "$BOOT/$file" ] || die "missing $BOOT/$file"
    log "Erasing $dev ($cnt x ${EB_KB} KiB)..."
    flash_erase "$dev" 0 "$cnt"
    log "Writing $BOOT/$file -> $dev"
    nandwrite -p "$dev" "$BOOT/$file"
}

write_ubi() {
    # $1 = device, $2 = file on $BOOT, $3 = eraseblock count
    dev=$1; file=$2; cnt=$3
    [ -f "$BOOT/$file" ] || die "missing $BOOT/$file"
    log "Erasing $dev ($cnt x ${EB_KB} KiB)..."
    flash_erase "$dev" 0 "$cnt"
    log "Formatting $dev as UBI with $BOOT/$file"
    # -s 512: sub-page size (MT29F8G08 supports 512B sub-pages)
    # -O 2048: default layout volume size hint
    ubiformat "$dev" -f "$BOOT/$file" -s 512 -O 2048
}

flash_partition() {
    name=$1
    line=$(printf '%s\n' "$PARTITIONS" | grep -E "^$name[|]" || true)
    [ -n "$line" ] || die "unknown partition: $name (known: all, $(printf '%s\n' "$PARTITIONS" | cut -d'|' -f1 | tr '\n' ' '))"

    IFS='|' read -r _ dev file cnt kind <<EOF
$line
EOF

    case "$kind" in
        raw) write_raw "$dev" "$file" "$cnt" ;;
        ubi) write_ubi "$dev" "$file" "$cnt" ;;
        *)   die "unknown kind '$kind' for $name" ;;
    esac
}

flash_env_both() {
    # mtd2 (redundant) and mtd3 (primary) get identical copies.
    # Each partition is one 256 KiB eraseblock, count = 1.
    write_raw /dev/mtd2 uboot-env.bin 1
    write_raw /dev/mtd3 uboot-env.bin 1
}

flash_all() {
    flash_partition bootstrap
    flash_partition uboot
    flash_env_both
    flash_partition dtb
    flash_partition kernel
    flash_partition rootfs
}

main() {
    check_prereqs

    target=${1:-interactive}

    case "$target" in
        all)
            ASSUME_YES=1
            flash_all
            ;;
        bootstrap|uboot|env|dtb|kernel|rootfs)
            confirm
            if [ "$target" = "env" ]; then
                flash_env_both
            else
                flash_partition "$target"
            fi
            ;;
        interactive|"")
            confirm
            flash_all
            ;;
        *)
            die "unknown argument: $target"
            ;;
    esac

    echo
    log "=== Flash complete ==="
    if [ "$target" = "all" ] || [ "$target" = "interactive" ] || [ -z "$target" ]; then
        echo
        echo "To boot from NAND:"
        echo "  1. power off the board"
        echo "  2. REMOVE the SD card (so the ROM doesn't pick SDMMC first)"
        echo "  3. power on"
        echo
        echo "If the board reverts to SDMMC, double-check the at91bootstrap PMECC"
        echo "settings against the actual NAND chip."
    fi
}

main "$@"