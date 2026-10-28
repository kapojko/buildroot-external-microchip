#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Attach the NAND UBI partition and make sure the "data" volume exists, so
# data.mount can mount it at /data (plan stage 1.5, section 8.3).
#
# Die-agnostic by design:
#  * the UBI MTD partition is found by its label ("ubi"), never by a hardcoded
#    index - the frozen layout places it at mtd6 on 2/4/8 Gbit dies alike;
#  * the volume is created at the maximum size (= the rest of the UBI region),
#    so 2 Gbit, 4 Gbit and 8 Gbit dies all work without a change here.
#
# Idempotent: if UBI is already attached and the volume exists, this is a
# no-op ("never rewrite what is already there", same rule as the EEPROM).

set -eu

log() { printf 'medicam-data: %s\n' "$*"; }

# --- 1. Find the UBI MTD partition by label. -------------------------------
mtd_dev=""
for mtd in /sys/class/mtd/mtd[0-9]*; do
	[ -r "$mtd/name" ] || continue
	[ "$(cat "$mtd/name")" = "ubi" ] || continue
	mtd_dev="/dev/${mtd##*/}"
	break
done

if [ -z "$mtd_dev" ]; then
	log "no MTD partition labeled 'ubi' - /data unavailable (NAND absent?)"
	exit 0
fi
log "UBI MTD partition: $mtd_dev"

# --- 2. Attach if UBI is not present yet. ----------------------------------
if [ -e /dev/ubi0 ]; then
	log "UBI already attached"
else
	ubiattach -p "$mtd_dev" || { log "ubiattach $mtd_dev FAILED"; exit 1; }
	log "attached $mtd_dev as ubi0"
fi

# --- 3. Create the data volume once, at the maximum size. -------------------
if ubinfo /dev/ubi0 -N data >/dev/null 2>&1; then
	log "UBI volume 'data' already present"
else
	# -m = maximum available size (rest of the UBI region); die-agnostic.
	# (ubimkvol 2.2.1 requires an explicit size option; -s/--size needs a number,
	#  -m/--maxavsize sizes to the whole free region without parsing ubinfo.)
	ubimkvol /dev/ubi0 -N data -m || { log "ubimkvol 'data' FAILED"; exit 1; }
	log "created UBI volume 'data' (rest of the UBI region)"
fi
