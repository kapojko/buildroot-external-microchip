#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# check-boot-order.sh - dump the target's systemd ordering graph and report
# ordering cycles (PLAN F29). Host-side: the target only needs systemctl, the
# analysis runs here (buildroot needs python3 on the host anyway).
#
# Why: a cyclic ordering graph does not fail a boot - systemd deletes one job of
# the cycle to break it, and the victim is not stable across boots. That is how
# /data and the user application silently dropped out of the boot transaction
# while medicam-identity/-hostname still started (F29, LOG 11). A successful
# reboot is therefore not proof; this check is.
#
# Usage:
#   ./check-boot-order.sh root@192.168.3.17      # dump over ssh, then analyse
#   sshpass -p 1 ./check-boot-order.sh root@...  # same, password auth
#   ./check-boot-order.sh -f graph.txt           # analyse a saved dump
#   ./check-boot-order.sh -f graph.txt old       # regression test of the checker:
#                                                # pre-fix medicam-data.service
#                                                # must show the cycle again
#
# Exit status: 0 = no ordering cycle, 1 = cycles found, 2 = dump/analysis error.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
analyze=$here/check-boot-order.py

usage() {
	sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

[ -r "$analyze" ] || { echo "missing $analyze" >&2; exit 2; }

if [ "${1:-}" = "-f" ]; then
	[ $# -ge 2 ] || usage
	dump=$2
	shift 2
elif [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then
	host=$1
	shift
	dump=$(mktemp)
	trap 'rm -f "$dump"' EXIT
	# One ssh call: list the loaded units, then ask systemctl for the effective
	# After=/Before= of all of them at once ("--" because -.mount starts with -).
	# Effective means drop-ins and the implicit default dependencies are
	# already merged - exactly what the boot transaction is built from.
	if ! ssh -o BatchMode=no "$host" '
		systemctl list-units --all --plain --no-legend | awk "{print \$1}" \
			> /tmp/medicam-units.txt
		systemctl show -p Id -p After -p Before -- $(cat /tmp/medicam-units.txt)
	' > "$dump"; then
		echo "dump from $host failed" >&2
		exit 2
	fi
else
	usage
fi

echo "# unit graph from ${host:-$dump}"
exec python3 "$analyze" "$dump" "$@"
