#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# make_clean_no_host.sh — clean a buildroot output tree WITHOUT touching the
# host directory, so the cross toolchain and host tools are NOT recompiled.
#
# Why this exists (PLAN F22 + R1):
#   * Buildroot has no "dirclean" target (that is a Yocto/OpenEmbedded thing).
#   * `make clean` deletes output/host (verified: buildroot Makefile clean: ->
#     rm -rf ... $(HOST_DIR) ...), forcing a ~30-50% host rebuild on the next
#     `make`.
#   * A plain rm of the package/target/images dirs achieves the same "clean"
#     result for F22 (stale files left in output/target by disabled packages)
#     while keeping output/host and dl/ intact.
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

# Remove everything `make clean` removes, EXCEPT host/ (and .config + dl/).
rm -rf "$O_DIR/build" \
       "$O_DIR/target" \
       "$O_DIR/staging" \
       "$O_DIR/images" \
       "$O_DIR/legal-info" \
       "$O_DIR/graphs" \
       "$O_DIR/per-package" \
       "$O_DIR/pkg-stats."* 2>/dev/null || true

host_size=$(du -sh "$O_DIR/host" 2>/dev/null | cut -f1)
echo "cleaned $O_DIR  (host preserved: $O_DIR/host, ${host_size:-?})"
echo "next: make  (or for the NAND tree: make O=$O_DIR)"
