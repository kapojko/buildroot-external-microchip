#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# Give every MediCam board a unique hostname so the desktop script can address it
# as medicam-<last 6 hex digits of the eth0 MAC>, e.g. medicam-1a2b3c.
#
# Without this, every board is "sam9x60_medicam" (BR2_TARGET_GENERIC_HOSTNAME)
# and two boards on the same LAN cannot be told apart (plan F16).
#
# Runs from medicam-hostname.service before systemd-networkd, so the DHCP
# hostname and the resulting DNS record carry the final name.
# Fallback (no eth0 MAC available): first 6 hex digits of /etc/machine-id.

set -eu

NAME=""

if [ -r /sys/class/net/eth0/address ]; then
	mac="$(tr -d ':\n' < /sys/class/net/eth0/address)"
	if [ "${#mac}" -eq 12 ]; then
		NAME="medicam-${mac#??????????}"
	fi
fi

if [ -z "${NAME}" ] && [ -r /etc/machine-id ]; then
	machine_id="$(tr -d '-\n' < /etc/machine-id)"
	NAME="medicam-$(printf '%s' "${machine_id}" | cut -c1-6)"
fi

# Nothing usable: keep whatever hostname the image was built with.
[ -n "${NAME}" ] || exit 0

printf '%s\n' "${NAME}" > /etc/hostname

# Keep the local "127.0.1.1 <hostname>" entry in sync with the new name.
if grep -q '^127\.0\.1\.1' /etc/hosts; then
	sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${NAME}/" /etc/hosts
else
	printf '127.0.1.1\t%s\n' "${NAME}" >> /etc/hosts
fi

hostname "${NAME}" 2>/dev/null || true

exit 0
