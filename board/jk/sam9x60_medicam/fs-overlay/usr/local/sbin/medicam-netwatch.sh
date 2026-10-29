#!/bin/sh
# MediCam: eth0 receive-path watchdog -- workaround for PLAN F31.
#
# Started by medicam-netwatch.timer once a minute. Type=oneshot, so systemd
# never starts it while a previous run is still active: no overlap, no lock.
# One pass, no state file, no backoff:
#
#   carrier down                -> nothing to fix, exit
#   carrier up, IPv4 present    -> the port works, exit
#   carrier up, no IPv4         -> candidate. networkd is retrying DHCPv4 at
#                                  that moment, so TX is not silent and a
#                                  frozen rx_packets means the receive path
#                                  delivers nothing.
#                                  Sample rx_packets 3 times, 10 s apart: any
#                                  advance = frames arrive, the lease is only
#                                  late -> exit. Three equal samples = stuck.
#
# Stuck -> ip link down, 10 s, ip link up, networkctl reconfigure, and one
# daemon.err journal record with the counters before and after.

IF=eth0
DOWN_SECONDS=10
SAMPLES=3
INTERVAL=10

rx()      { cat "/sys/class/net/$IF/statistics/rx_packets" 2>/dev/null || echo 0; }
tx()      { cat "/sys/class/net/$IF/statistics/tx_packets" 2>/dev/null || echo 0; }
carrier() { cat "/sys/class/net/$IF/carrier" 2>/dev/null || echo 0; }
has_v4()  { ip -4 -o addr show dev "$IF" 2>/dev/null | grep -q ' inet '; }

note() { logger -p daemon.err -t medicam-netwatch "$*"; }

[ "$(carrier)" = 1 ] || exit 0
has_v4 && exit 0

rx0=$(rx)
tx0=$(tx)

i=0
while [ "$i" -lt "$SAMPLES" ]; do
	sleep "$INTERVAL"
	[ "$(rx)" != "$rx0" ] && exit 0
	[ "$(carrier)" = 1 ] || exit 0
	i=$((i + 1))
done

note "eth0: carrier up, no IPv4, rx_packets frozen at $rx0 for $((SAMPLES * INTERVAL)) s (tx=$tx0) - reopening the link"

ip link set "$IF" down
sleep "$DOWN_SECONDS"
ip link set "$IF" up
command -v networkctl >/dev/null && networkctl reconfigure "$IF" >/dev/null 2>&1

sleep 5
if has_v4; then
	note "eth0: reopened after ${DOWN_SECONDS} s down: rx_packets $rx0 -> $(rx), IPv4 acquired"
else
	note "eth0: reopened after ${DOWN_SECONDS} s down: rx_packets $rx0 -> $(rx), still no IPv4"
fi

exit 0
