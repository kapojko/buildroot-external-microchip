#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# MediCam rootfs post-build script.
#
# Everything that can be shipped as a plain file lives in fs-overlay/. Only
# changes that cannot be expressed there are done here:
#
#  * /home must become a symlink into the persistent volume. The target already
#    has an (empty) /home directory and the overlay is copied with
#    "rsync -a --ignore-times", which cannot replace a directory with a
#    symlink - so it has to be done after the overlay copy, i.e. here.
#  * a symlink cannot be committed from the Windows checkout either
#    (core.symlinks=false), so it must be created at build time.

set -eu

TARGET_DIR="${1:?usage: $0 <target-dir>}"

# /home -> data/home, i.e. /data/home once the NAND volume is mounted (stage 1.5).
rm -rf "${TARGET_DIR}/home"
ln -s data/home "${TARGET_DIR}/home"

# Stage 1 has no NAND mount yet: /data is a plain directory in the rootfs image,
# so give the /home symlink a target to resolve to.
mkdir -p "${TARGET_DIR}/data/home"
