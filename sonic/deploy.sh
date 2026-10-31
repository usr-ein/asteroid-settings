#!/usr/bin/env bash
# Sonic Screwdriver: run the fork's asteroid-settings on the watch.
#
#   sonic/deploy.sh           install sonic/out/asteroid-settings.so
#   sonic/deploy.sh --stock   go back to the stock Settings app
#   sonic/deploy.sh --status  show which Settings app the launcher starts
#
# The stock /usr/bin/asteroid-settings and /usr/lib/asteroid-settings.so are
# never modified. The launcher starts Settings by name, and its PATH has
# /usr/local/bin before /usr/bin. So /usr/local/bin/asteroid-settings
# (sonic/watch/asteroid-settings) takes over, and starts the fork's build from
# /usr/local/lib/sonic-settings/. --stock deletes that script.
# Icons the stock theme lacks (sonic/icons/) go to
# /usr/share/icons/asteroid/sonic/; --stock leaves them, unused.
# Nothing restarts: a Settings app that is already open keeps its build until
# it is closed.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
watch=${SONIC_WATCH:-sonic-screwdriver}
lib=$here/out/asteroid-settings.so

# Wakelocks time out after 5 minutes, so a deploy that dies midway can't keep
# the watch awake.
wakelock_ns=300000000000
status='
	pid=$(systemctl --user -M ceres@ show -p MainPID --value asteroid-launcher)
	path=$(tr "\0" "\n" < /proc/$pid/environ 2>/dev/null | sed -n "s/^PATH=//p")
	echo "the launcher starts: $(PATH=${path:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin} command -v asteroid-settings)"
	[ -f /usr/local/bin/asteroid-settings ] && echo "override: installed (fork enabled)" || echo "override: none (stock Settings)"
	[ -f /usr/local/lib/sonic-settings/asteroid-settings.so ] && echo "installed build: $(sha256sum /usr/local/lib/sonic-settings/asteroid-settings.so | cut -c1-12)"
	running=$(for p in /proc/[0-9]*; do
		a0=$(tr "\0" "\n" < $p/cmdline 2>/dev/null | head -n 1)
		case "$a0" in */asteroid-settings.so) echo "pid ${p#/proc/} $a0" ;; esac
	done)
	[ -n "$running" ] && echo "open now (close it to switch builds): $running" || echo "open now: no"
	true'

case "${1:-}" in
--status)
	ssh "$watch" "$status"
	;;
--stock)
	ssh "$watch" "rm -f /usr/local/bin/asteroid-settings; $status"
	;;
"")
	[ -f "$lib" ] || { echo "no build at $lib; run sonic/build.sh first" >&2; exit 1; }
	file "$lib" | grep -q 'ELF 32-bit LSB.*ARM' || { echo "$lib is not a 32-bit ARM library" >&2; exit 1; }
	ssh "$watch" "echo 'sonic_settings $wakelock_ns' > /sys/power/wake_lock; rm -rf /tmp/sonic-settings; mkdir -p /tmp/sonic-settings"
	files=("$lib" "$here/watch/asteroid-settings")
	[ ! -d "$here/icons" ] || files+=("$here/icons")
	scp -q -r "${files[@]}" "$watch:/tmp/sonic-settings/"
	ssh "$watch" "set -e
		cd /tmp/sonic-settings
		d=/usr/local/lib/sonic-settings
		mkdir -p \$d
		if [ -f \$d/asteroid-settings.so ]; then cp -p \$d/asteroid-settings.so \$d/asteroid-settings.so.prev; fi
		install -m 755 asteroid-settings.so \$d/asteroid-settings.so.new
		mv \$d/asteroid-settings.so.new \$d/asteroid-settings.so
		install -D -m 755 asteroid-settings /usr/local/bin/asteroid-settings
		for f in icons/*.svg; do
			if [ -f \$f ]; then install -D -m 644 \$f /usr/share/icons/asteroid/sonic/\${f#icons/}; fi
		done
		cd / && rm -rf /tmp/sonic-settings
		echo sonic_settings > /sys/power/wake_unlock
		$status"
	;;
*)
	echo "usage: $0 [--stock | --status]" >&2
	exit 64
	;;
esac
