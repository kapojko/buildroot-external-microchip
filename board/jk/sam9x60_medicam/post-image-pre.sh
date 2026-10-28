#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# post-image-pre.sh — runs BEFORE genimage.sh as part of
# BR2_ROOTFS_POST_IMAGE_SCRIPT (chain). Stage 2 (PLAN 2.5).
#
# Two responsibilities:
#   (1) Copy at91bootstrap3 *.bin.pmecc into BINARIES_DIR as boot.bin.pmecc.
#       at91bootstrap3.mk only copies *.bin (the SDMMC/QSPI variant); the
#       NAND build needs the PMECC-encoded *.bin.pmecc for the bootstrap
#       partition.
#   (2) Re-derive output/images/uboot-env.bin from the env source file.
#       Buildroot's host-uboot-tools mtime check does NOT invalidate when only
#       the source text changes, leading to a stale env being baked into
#       medicam-nand.img and the rescue sdcard.img. We always regenerate.
#
# The mkenvimage flags mirror configs/sam9x60_medicam_nand_defconfig:
#   size 0x40000 (256 KiB), redundant flag set.

set -eu

BINARIES_DIR=${BINARIES_DIR:-output/images}
BUILD_DIR=${BUILD_DIR:-output/build}
EXTERNAL_TREE=${BR2_EXTERNAL_MCHP_PATH:-$(cd "$(dirname "$0")/../../.." && pwd)}

shopt -s nullglob

# ----- (1) boot.bin.pmecc -----
matches=( "${BUILD_DIR}"/at91bootstrap3-*/build/binaries/*.bin.pmecc )

if [ ${#matches[@]} -eq 0 ]; then
    echo "post-image-pre.sh: ERROR: no at91bootstrap3 *.bin.pmecc found under ${BUILD_DIR}" >&2
    echo "post-image-pre.sh: The NAND build requires a PMECC-encoded bootstrap (USE_PMECC)." >&2
    echo "post-image-pre.sh: Check the at91bootstrap_nand.fragment (PMECC_OOB_224)." >&2
    exit 1
fi

if [ ${#matches[@]} -gt 1 ]; then
    echo "post-image-pre.sh: WARNING: multiple .bin.pmecc files found, using first:" >&2
    printf '  %s\n' "${matches[@]}" >&2
fi

src="${matches[0]}"
dst="${BINARIES_DIR}/boot.bin.pmecc"

mkdir -p "${BINARIES_DIR}"
cp -f "${src}" "${dst}"
echo "post-image-pre.sh: copied $(basename "${src}") -> ${dst}"

# ----- (2) uboot-env.bin fresh-from-source -----
ENV_SRC="${EXTERNAL_TREE}/board/jk/sam9x60_medicam/uboot-env-nand.txt"
ENV_DST="${BINARIES_DIR}/uboot-env.bin"

if [ ! -f "${ENV_SRC}" ]; then
    echo "post-image-pre.sh: ERROR: env source not found at ${ENV_SRC}" >&2
    exit 1
fi

# Version-robust path: host-uboot-tools-<version>/tools/mkenvimage
mkenv=$(ls -d "${BUILD_DIR}"/host-uboot-tools-*/tools/mkenvimage 2>/dev/null | head -1 || true)
if [ -z "${mkenv}" ] || [ ! -x "${mkenv}" ]; then
    echo "post-image-pre.sh: ERROR: mkenvimage not found under ${BUILD_DIR}/host-uboot-tools-*" >&2
    echo "post-image-pre.sh: (host-uboot-tools not built yet — run 'make' first)" >&2
    exit 1
fi

# Always regenerate (cost ~1 ms); mirrors BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE_*
# in configs/sam9x60_medicam_nand_defconfig: size 0x40000, redundant flag set.
"${mkenv}" -r -s 0x40000 -o "${ENV_DST}" "${ENV_SRC}"
echo "post-image-pre.sh: regenerated ${ENV_DST} from ${ENV_SRC}"
