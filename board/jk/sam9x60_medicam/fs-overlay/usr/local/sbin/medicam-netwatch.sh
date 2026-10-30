#!/bin/sh
# MediCam: eth0 receive-path watchdog -- workaround for PLAN F31 (v2).
#
# Started by medicam-netwatch.timer every 30 s. One pass per run; the healthy
# path never sleeps: the previous run's counters and timestamp are kept in
# /run (tmpfs, RAM only), so consecutive runs measure a real ~30 s window.
#
# Two independent signatures, each with its own short history:
#
#   dead  - carrier up, RX frozen, TX advancing. The PHY/MAC reports a live
#           link and we are transmitting, but not a single frame arrives. This
#           is the "stuck" state of F31 (measured 135 s and 481 s on the board).
#           Armed only after RX was ever seen to move (rx_moved) or a DHCP
#           lease was ever acquired (had_v4), so a clean link with no DHCP
#           server is left alone. A board that boots straight into the stuck
#           state is covered by a small boot-phase allowance.
#
#   dirty - FCS/CRC errors growing. The receive path delivers frames, but a
#           large fraction of them is corrupt; the port can even have an IPv4
#           address from a short good window (this is the state that hurt the
#           operator on 2026-10-29). Signature: crc errors per window above a
#           floor and either >5 % of the received attempts or >=0.5 err/s.
#
# Any hit is only evidence; a recovery is attempted when the history shows
# DEAD_HITS hits in the last DEAD_WIN windows, or DIRTY_HITS in the last
# DIRTY_WIN windows. A single burst or a single clean window therefore cannot
# trigger, and an intermittent fault is still caught.
#
# Recovery: ip link down, DOWN_SECONDS, up, networkctl reconfigure, then the
# result is verified over VERIFY_SECONDS (RX moving, CRC flat). One retry with
# a longer down period. At most MAX_ACTIONS actions per ACTION_PERIOD; after
# that the script logs "giving up" and stops touching the link until it is
# demonstrably alive again -- a bad cable must not become a flapping link.
#
# Tunables are the constants below; every one can be overridden from the
# environment (handy for a one-off run with a private state file).

IF=${IF:-eth0}
STATE=${STATE:-/run/medicam-netwatch.state}
PLOG=${PLOG:-/data/var/log/netwatch.log}

DEAD_HITS=${DEAD_HITS:-2}       # hits needed ...
DEAD_WIN=${DEAD_WIN:-3}         # ... within this many windows
DIRTY_HITS=${DIRTY_HITS:-3}
DIRTY_WIN=${DIRTY_WIN:-5}

CRC_MIN=${CRC_MIN:-5}           # absolute FCS errors per window
CRC_RATIO_PCT=${CRC_RATIO_PCT:-5}   # percent of received attempts
CRC_RATE_MIN=${CRC_RATE_MIN:-15}    # absolute errors per window (>=0.5/s at 30 s)

DOWN_SECONDS=${DOWN_SECONDS:-10}
RETRY_DOWN_SECONDS=${RETRY_DOWN_SECONDS:-30}
VERIFY_SECONDS=${VERIFY_SECONDS:-30}

MAX_ACTIONS=${MAX_ACTIONS:-3}
ACTION_PERIOD=${ACTION_PERIOD:-1800}
BOOT_ALLOW_SECONDS=${BOOT_ALLOW_SECONDS:-600}
BOOT_MAX_ACTIONS=${BOOT_MAX_ACTIONS:-2}

WINDOW_MIN=${WINDOW_MIN:-20}    # shorter gap: not a window, keep waiting
WINDOW_MAX=${WINDOW_MAX:-300}   # longer gap: re-baseline (reboot/suspend)

now()       { date +%s; }
rx()        { cat "/sys/class/net/$IF/statistics/rx_packets" 2>/dev/null || echo 0; }
tx()        { cat "/sys/class/net/$IF/statistics/tx_packets" 2>/dev/null || echo 0; }
crc()       { cat "/sys/class/net/$IF/statistics/rx_crc_errors" 2>/dev/null || echo 0; }
carrier()   { cat "/sys/class/net/$IF/carrier" 2>/dev/null || echo 0; }
ccount()    { cat "/sys/class/net/$IF/carrier_changes" 2>/dev/null || echo 0; }
has_v4()    { ip -4 -o addr show dev "$IF" 2>/dev/null | grep -q ' inet '; }

log()    { logger -p daemon.info -t medicam-netwatch "$*"; }
err()    { logger -p daemon.err  -t medicam-netwatch "$*"; persist "$*"; }

persist() {
	d=${PLOG%/*}
	[ -d "$d" ] || mkdir -p "$d" 2>/dev/null
	printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$PLOG" 2>/dev/null
}

isnum() { case ${1:-x} in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

popcount() {
	h=$1 n=0
	while [ "$h" -ne 0 ]; do n=$((n + (h & 1))); h=$((h >> 1)); done
	echo "$n"
}

# write_state TS RX TX CRC CARRIER CC HAD_V4 RX_MOVED DEAD_HIST DIRTY_HIST ACTS ACTS_TS BOOTACTS GAVEUP
write_state() {
	printf 'v2 %s %s %s %s %s %s %s %s %s %s %s %s %s %s\n' "$@" > "$STATE.tmp" 2>/dev/null \
		&& mv -f "$STATE.tmp" "$STATE" 2>/dev/null
}

# --- previous run -----------------------------------------------------------
valid=0
if [ -r "$STATE" ]; then
	read -r sv sts srx stx scrc scar scc shv srxm sdead sdirty sacts sacts_ts sboot sgave < "$STATE"
	valid=1
	[ "$sv" = v2 ] || valid=0
	for f in "$sts" "$srx" "$stx" "$scrc" "$scar" "$scc" "$shv" "$srxm" \
		 "$sdead" "$sdirty" "$sacts" "$sacts_ts" "$sboot" "$sgave"; do
		isnum "$f" || valid=0
	done
fi

c=$(carrier)
r=$(rx)
t=$(tx)
cr=$(crc)
cc=$(ccount)
v4=0
has_v4 && v4=1

if [ "$valid" != 1 ]; then
	# first run after boot / unreadable state: baseline only
	write_state "$(now)" "$r" "$t" "$cr" "$c" "$cc" "$v4" 0 0 0 0 0 0 0
	exit 0
fi

# sticky facts: a lease/known RX seen once stays valid for this boot
hv=$shv
rxm=$srxm
[ "$v4" = 1 ] && hv=1

if [ "$c" != 1 ]; then
	# no link: nothing to judge, drop the history
	write_state "$(now)" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" 0 0 "$sacts" "$sacts_ts" "$sboot" "$sgave"
	exit 0
fi

ts=$(now)
dt=$((ts - sts))
if [ "$dt" -lt "$WINDOW_MIN" ]; then
	exit 0
fi
if [ "$dt" -gt "$WINDOW_MAX" ]; then
	write_state "$ts" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" 0 0 "$sacts" "$sacts_ts" "$sboot" "$sgave"
	exit 0
fi

rx_d=$((r - srx))
tx_d=$((t - stx))
crc_d=$((cr - scrc))
if [ "$rx_d" -lt 0 ] || [ "$tx_d" -lt 0 ] || [ "$crc_d" -lt 0 ]; then
	# counters reset or wrapped: start a new baseline
	write_state "$ts" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" 0 0 "$sacts" "$sacts_ts" "$sboot" "$sgave"
	exit 0
fi

[ "$rx_d" -gt 0 ] && rxm=1

up=0
read -r up rest < /proc/uptime 2>/dev/null || up=0
up=${up%%.*}

# --- classify this window ---------------------------------------------------
dead_hit=0
boot_phase=0
if [ "$rx_d" -eq 0 ] && [ "$tx_d" -gt 0 ]; then
	if [ "$hv" = 1 ] || [ "$rxm" = 1 ]; then
		dead_hit=1
	elif [ "$up" -lt "$BOOT_ALLOW_SECONDS" ] && [ "$sboot" -lt "$BOOT_MAX_ACTIONS" ]; then
		dead_hit=1
		boot_phase=1
	fi
fi

dirty_hit=0
if [ "$crc_d" -ge "$CRC_MIN" ]; then
	if [ $((crc_d * 100)) -ge $((CRC_RATIO_PCT * (crc_d + rx_d))) ] \
	   || [ "$crc_d" -ge "$CRC_RATE_MIN" ]; then
		dirty_hit=1
	fi
fi

dead_hist=$(( ((sdead << 1) | dead_hit) & ((1 << DEAD_WIN) - 1) ))
dirty_hist=$(( ((sdirty << 1) | dirty_hit) & ((1 << DIRTY_WIN) - 1) ))
dead_cnt=$(popcount "$dead_hist")
dirty_cnt=$(popcount "$dirty_hist")

# --- evidence log: silent while healthy, one line per anomalous window ------
if [ "$dead_hit" = 1 ] || [ "$dirty_hit" = 1 ] || [ "$sdead" -ne 0 ] || [ "$sdirty" -ne 0 ]; then
	log "eth0: window ${dt}s rx_d=$rx_d tx_d=$tx_d crc_d=$crc_d (rx=$r tx=$t crc=$cr v4=$v4 carrier=$c) dead=$dead_hist/$dead_cnt dirty=$dirty_hist/$dirty_cnt"
fi
if [ "$dead_hist" = 0 ] && [ "$dirty_hist" = 0 ] && { [ "$sdead" -ne 0 ] || [ "$sdirty" -ne 0 ]; }; then
	log "eth0: clean again"
	sgave=0
fi

# --- act? -------------------------------------------------------------------
if [ "$dead_cnt" -lt "$DEAD_HITS" ] && [ "$dirty_cnt" -lt "$DIRTY_HITS" ]; then
	write_state "$ts" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" "$dead_hist" "$dirty_hist" "$sacts" "$sacts_ts" "$sboot" "$sgave"
	exit 0
fi

reason="receive path"
[ "$dirty_cnt" -ge "$DIRTY_HITS" ] && reason="CRC errors"
[ "$dead_cnt" -ge "$DEAD_HITS" ] && reason="RX frozen"

# budget housekeeping: a quiet period clears the counters
if [ "$sacts" -gt 0 ] && [ $((ts - sacts_ts)) -gt "$ACTION_PERIOD" ]; then
	sacts=0
	sacts_ts=0
	sgave=0
fi

if [ "$sgave" = 1 ]; then
	# already gave up: keep the link up, keep the evidence lines coming
	write_state "$ts" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" "$dead_hist" "$dirty_hist" "$sacts" "$sacts_ts" "$sboot" "$sgave"
	exit 0
fi

if [ "$sacts" -ge "$MAX_ACTIONS" ]; then
	sgave=1
	err "eth0: $reason persists after $sacts actions in $((ACTION_PERIOD / 60)) min - giving up, leaving the link up (rx_d=$rx_d tx_d=$tx_d crc_d=$crc_d v4=$v4); will retry after a clean window or a carrier change"
	write_state "$ts" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" "$dead_hist" "$dirty_hist" "$sacts" "$sacts_ts" "$sboot" "$sgave"
	exit 0
fi

sacts=$((sacts + 1))
[ "$sacts_ts" = 0 ] && sacts_ts=$ts
[ "$boot_phase" = 1 ] && sboot=$((sboot + 1))

recover() {
	rd=$1
	err "eth0: $reason (dead=$dead_hist/$dead_cnt dirty=$dirty_hist/$dirty_cnt), reopening link: down ${rd}s. window ${dt}s: rx_d=$rx_d tx_d=$tx_d crc_d=$crc_d (rx=$r tx=$t crc=$cr v4=$v4 carrier=$c)"
	ip link set "$IF" down
	sleep "$rd"
	ip link set "$IF" up
	command -v networkctl >/dev/null 2>&1 && networkctl reconfigure "$IF" >/dev/null 2>&1

	i=0
	while [ "$i" -lt 20 ]; do [ "$(carrier)" = 1 ] && break; sleep 1; i=$((i + 1)); done
	v0=$(rx); w0=$(crc)
	sleep "$VERIFY_SECONDS"
	v1=$(rx); w1=$(crc)
	vc=no
	has_v4 && vc=yes
	if [ "$(carrier)" = 1 ] && [ "$w1" = "$w0" ] && { [ "$v1" -gt "$v0" ] || [ "$vc" = yes ]; }; then
		err "eth0: recovered after ${rd}s down: rx $v0->$v1 crc $w0->$w1 carrier=$(carrier) v4=$vc"
		rxm=1
		return 0
	fi
	err "eth0: recovery after ${rd}s down did NOT verify: rx $v0->$v1 crc $w0->$w1 carrier=$(carrier) v4=$vc"
	return 1
}

recover "$DOWN_SECONDS" || {
	if [ "$sacts" -lt "$MAX_ACTIONS" ]; then
		sacts=$((sacts + 1))
		recover "$RETRY_DOWN_SECONDS" || true
	fi
}

r=$(rx); t=$(tx); cr=$(crc); c=$(carrier); cc=$(ccount)
write_state "$(now)" "$r" "$t" "$cr" "$c" "$cc" "$hv" "$rxm" 0 0 "$sacts" "$sacts_ts" "$sboot" "$sgave"
exit 0
