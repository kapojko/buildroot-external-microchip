#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# make_clean_no_host.sh — clean a buildroot output tree WITHOUT touching the
# host toolchain/tools, so they are NOT recompiled.
#
# Why this exists (PLAN F22 + R1):
#   * Buildroot has no "dirclean" target (that is a Yocto/OpenEmbedding thing).
#   * `make clean` deletes output/host AND all of output/build — including the
#     host packages' stamp files — forcing a ~30-50% host rebuild on the next
#     `make`.
#   * Buildroot decides whether to (re)build a package from the stamp files in
#     output/build/<pkg>/ (.stamp_configured, .stamp_built, .stamp_host_installed,
#     ...). An intact output/host is NOT enough: remove the stamps and every
#     host package is recompiled and reinstalled anyway.
#
# What this script does:
#   * removes the TARGET-package build dirs (forcing their reinstall into a
#     fresh output/target — the F22 "stale files from dropped packages" fix);
#   * keeps every host-* build dir (and its stamps), so host packages are NOT
#     rebuilt;
#   * removes output/target, output/images, output/staging, etc. (regenerated).
#   * keeps output/host, .config and dl/.
#
# When is a clean needed at all?
#   * Only when the PACKAGE SET changes (F22). Toggling between the SD and NAND
#     defconfigs shares the same package set — just `make <defconfig> && make`,
#     no clean required.
#
# Usage (run in the WSL buildroot checkout):
#   make_clean_no_host.sh [buildroot_dir] [output_dir]
#     buildroot_dir  default: ~/src/buildroot-mchp
#     output_dir     default: $buildroot_dir/output
#
#   example (NAND tree): make_clean_no_host.sh ~/src/buildroot-mchp output-nand

set -eu

BR_DIR=${1:-"$HOME/src/buildroot-mchp"}
O_DIR=${2:-"$BR_DIR/output"}

[ -f "$BR_DIR/Makefile" ] || { echo "error: no buildroot Makefile in $BR_DIR" >&2; exit 1; }
[ -d "$O_DIR" ]           || { echo "error: no output dir $O_DIR" >&2; exit 1; }

cd "$BR_DIR"

# Remove TARGET-package build dirs (with their stamps -> they reinstall).
# Keep host-* dirs: their stamps stop buildroot recompiling the host.
if [ -d "$O_DIR/build" ]; then
    for d in "$O_DIR"/build/*/; do
        [ -d "$d" ] || continue
        name=${d%/}; name=${name##*/}
        case "$name" in
            host-*) continue ;;
        esac
        rm -rf "$d"
    done
fi

# Remove the assembled rootfs/images/staging (regenerated on the next make),
# but keep host/, .config and dl/.
rm -rf "$O_DIR/target" \
       "$O_DIR/images" \
       "$O_DIR/staging" \
       "$O_DIR/legal-info" \
       "$O_DIR/graphs" \
       "$O_DIR/per-package" \
       "$O_DIR/pkg-stats."* 2>/dev/null || true

host_size=$(du -sh "$O_DIR/host" 2>/dev/null | cut -f1)
echo "cleaned $O_DIR  (host preserved: $O_DIR/host, ${host_size:-?})"
echo "next: make  (or for the NAND tree: make O=$O_DIR)"
