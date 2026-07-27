#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# post-image-pre.sh — runs BEFORE genimage.sh as part of
# BR2_ROOTFS_POST_IMAGE_SCRIPT (chain).
#
# Two responsibilities:
#   (1) Copy at91bootstrap3 *.bin.pmecc into BINARIES_DIR as boot.bin.pmecc.
#       at91bootstrap3.mk only copies *.bin (the SDMMC/QSPI variant); the
#       NAND build needs the PMECC-encoded *.bin.pmecc.
#   (2) Re-derive output/images/uboot-env.bin from the env source file if
#       the source is newer than the cached binary. Buildroot's
#       host-uboot-tools mtime check does NOT invalidate when only the
#       source text changes, leading to a stale env being baked into
#       medicam-nand.img. See board/jk/sam9x60_medicam/uboot-env-nand.txt.

set -eu

BINARIES_DIR=${BINARIES_DIR:-output/images}
BUILD_DIR=${BUILD_DIR:-output/build}
EXTERNAL_TREE=${BR2_EXTERNAL_MCHP_PATH:-$(cd "$(dirname "$0")/../../.." && pwd)}

shopt -s nullglob

# ----- (1) boot.bin.pmecc -----
matches=( "${BUILD_DIR}"/at91bootstrap3-*/build/binaries/*.bin.pmecc )

if [ ${#matches[@]} -eq 0 ]; then
    echo "post-image-pre.sh: ERROR: no at91bootstrap3 *.bin.pmecc found under ${BUILD_DIR}" >&2
    echo "post-image-pre.sh: The NAND build requires PMECC-encoded bootstrap (USE_PMECC=y)." >&2
    echo "post-image-pre.sh: Either rebuild on a Unix-like host (the .pmecc target uses Python/ln -sf)" >&2
    echo "post-image-pre.sh: or set PMECC n/a for your toolchain." >&2
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
MKENVIMAGE="${BUILD_DIR}/host-uboot-tools-2021.07/tools/mkenvimage"

if [ ! -f "${ENV_SRC}" ]; then
    echo "post-image-pre.sh: ERROR: env source not found at ${ENV_SRC}" >&2
    exit 1
fi

if [ ! -x "${MKENVIMAGE}" ]; then
    echo "post-image-pre.sh: ERROR: mkenvimage not at ${MKENVIMAGE}" >&2
    echo "post-image-pre.sh: (host-uboot-tools not built yet — run 'make' first)" >&2
    exit 1
fi

# Always regenerate. cost is ~1 ms; eliminates the stale-env trap.
# Mirror the BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE settings from
# configs/sam9x60_medicam_nand_defconfig:
#   size 0x40000 (256 KiB), redundant flag set.
"${MKENVIMAGE}" -r -s 0x40000 -o "${ENV_DST}" "${ENV_SRC}"
echo "post-image-pre.sh: regenerated ${ENV_DST} from ${ENV_SRC}"
