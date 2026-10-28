#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Establish a stable board identity before the network comes up.
#
# The SoC has no factory MAC address: `ethtool -P eth0` returns
# 00:00:00:00:00:00, the DTS has no local-mac-address, and the kernel logs
# "invalid hw address, using random". What the board ends up with is a hash of
# /etc/machine-id produced by systemd-udevd's MACAddressPolicy=persistent, i.e.
# an address that changes whenever the rootfs image is rewritten - and the
# hostname is derived from it (plan F24). The MAC therefore has to live in
# hardware: the on-board 24C256 EEPROM (32 KiB, I2C0 @0x50), together with a
# board serial that factory provisioning or the desktop script can later set.
#
# Record layout: 96 bytes at EEPROM offset 0, ASCII, space padded:
#
#   MCM1 1 mac=<12 hex digits> serial=<16 chars> crc=<cksum>
#
# where <cksum> is `cksum` over everything in front of " crc=". An invalid or
# blank record is written once (EEPROM endurance: never rewritten while valid).

set -eu

EEPROM=/sys/bus/i2c/devices/0-0050/eeprom
IFACE=eth0
RECLEN=96
DEFAULT_SERIAL=0000000000000000

log() { printf 'medicam-identity: %s\n' "$*"; }

[ -e "$EEPROM" ] || { log "no EEPROM at $EEPROM, keeping the runtime MAC"; exit 0; }

current_mac() { cat "/sys/class/net/$IFACE/address" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# 1. Try to read a valid record.
# ---------------------------------------------------------------------------
mac=""
serial=""
record=$(dd if="$EEPROM" bs=$RECLEN count=1 2>/dev/null | tr -d '\000' || true)

if printf '%s' "$record" | grep -q '^MCM1 1 '; then
	body=$(printf '%s' "$record" | sed 's/ crc=.*$//')
	want=$(printf '%s' "$record" | sed -n 's/.* crc=\([0-9][0-9]*\).*/\1/p')
	have=$(printf '%s\n' "$body" | cksum | cut -d' ' -f1)
	candidate=$(printf '%s' "$body" | sed -n 's/.*mac=\([0-9a-fA-F]\{12\}\).*/\1/p')
	if [ -n "$want" ] && [ "$want" = "$have" ] && [ "${#candidate}" -eq 12 ]; then
		mac=$candidate
		serial=$(printf '%s' "$body" | sed -n 's/.*serial=\([^ ]*\).*/\1/p')
		log "EEPROM identity ok: mac=$mac serial=$serial"
	else
		log "EEPROM record is not valid (crc $have, expected $want), re-programming"
	fi
fi

# ---------------------------------------------------------------------------
# 2. Nothing usable: adopt the current address, or generate one from the TRNG.
# ---------------------------------------------------------------------------
if [ -z "$mac" ]; then
	cur=$(current_mac | tr -d ':')
	if [ "${#cur}" -eq 12 ] && [ "$cur" != "000000000000" ]; then
		# Adopting the address the board is using now keeps the hostname stable
		# across the transition to this scheme.
		mac=$cur
		log "adopting the current MAC $mac"
	else
		gen=$(od -An -tx1 -N6 /dev/hwrng 2>/dev/null | tr -d ' \n' || true)
		[ "${#gen}" -eq 12 ] || { log "no MAC available (no EEPROM, no TRNG), giving up"; exit 0; }
		# locally administered (bit 1 of the first octet) and unicast
		first=$(printf '%02x' $(( (0x$(printf '%s' "$gen" | cut -c1-2) | 0x02) & 0xfe )))
		mac="$first$(printf '%s' "$gen" | cut -c3-)"
		log "generated MAC $mac from the TRNG"
	fi

	serial=${MEDICAM_SERIAL:-$DEFAULT_SERIAL}
	body="MCM1 1 mac=$mac serial=$serial"
	crc=$(printf '%s\n' "$body" | cksum | cut -d' ' -f1)
	line="$body crc=$crc"
	if printf '%-'$RECLEN's' "$line" | dd of="$EEPROM" bs=$RECLEN count=1 conv=notrunc 2>/dev/null; then
		log "EEPROM programmed: $line"
	else
		log "EEPROM write FAILED (write-protected?); this MAC will not survive a reboot"
	fi
fi

# ---------------------------------------------------------------------------
# 3. Apply it.
# ---------------------------------------------------------------------------
mac_colon=$(printf '%s' "$mac" | sed 's/../&:/g; s/:$//')
if [ "$(current_mac)" = "$mac_colon" ]; then
	log "$IFACE already uses $mac_colon"
else
	ip link set dev "$IFACE" address "$mac_colon" && log "$IFACE MAC set to $mac_colon"
fi
