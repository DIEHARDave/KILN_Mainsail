#!/bin/sh
#####################################################################
# KILN_Mainsail root hook: Mainsail on port 80, Fluidd on port 81
#
# Kiln's nginx.conf (read-only image) serves Fluidd on port 80 only.
# This hook builds /run/nginx/kiln-mainsail.conf from it, with its server
# block twice:
#   port 80: root /data/ad5x/web/mainsail (instead of fluidd-root.conf)
#   port 81: Kiln's server as it is (Fluidd, fluidd-root.conf)
# Both keep all of Kiln's locations (Moonraker API, websocket, webcams,
# screen). Then it restarts nginx on that file, with Kiln's pid file, so
# S63nginx stop/reload still work. If the build or "nginx -t" fails,
# Kiln's own nginx stays as it is (Fluidd on 80).
#
# Kiln OS has no general root boot hook; S64ad5x-camera (root, after
# S63nginx) sources /data/ad5x/camera.conf, so install.sh adds
#   . /data/ad5x/mainsail-hook.sh
# there. It is sourced again on every camera restart: does nothing when
# nginx already runs this config. Names are prefixed (ms_): it runs
# inside S64ad5x-camera's start().
#
# "mainsail-hook.sh off": back to Kiln's own nginx (uninstall.sh).
#####################################################################

MS_HOOK_VERSION=1

MS_ROOT=/data/ad5x/web/mainsail
MS_KILN_CONF=/etc/nginx/nginx.conf
MS_CONF=/run/nginx/kiln-mainsail.conf
MS_PID=/run/nginx/nginx.pid
MS_NGINX=/usr/sbin/nginx

ms_log() { logger -t kiln-mainsail "$*"; }

# nginx's master process runs with config $1
ms_running_with() {
	[ -f $MS_PID ] || return 1
	tr '\0' ' ' < /proc/$(cat $MS_PID)/cmdline 2>/dev/null | grep -q -- "-c $1"
}

ms_build() {
	awk -v ms="$MS_ROOT" '
	# relative includes are relative to the main config file: make them
	# point at /etc/nginx, not /run/nginx
	$0 ~ /include[ \t]+[^\/ \t]/ { sub(/include[ \t]+/, "include /etc/nginx/") }
	# the server block, kept to print twice
	!done && /^[ \t]*server[ \t]*\{/ { inblk = 1 }
	inblk {
		blk[n++] = $0
		line = $0; sub(/#.*/, "", line)
		depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
		if (depth == 0) {
			inblk = 0; done = 1
			for (i = 0; i < n; i++) {
				l = blk[i]
				if (l ~ /include[ \t]+\/run\/nginx\/fluidd-root\.conf;/) {
					sub(/include.*/, "root " ms ";", l); found_root = 1
				}
				print l
			}
			print ""
			for (i = 0; i < n; i++) {
				l = blk[i]
				if (sub(/listen[ \t]+80[ \t]+default_server;/, "listen 81;", l))
					found_listen = 1
				print l
			}
		}
		next
	}
	{ print }
	END { if (!found_root || !found_listen) exit 1 }
	' $MS_KILN_CONF > $MS_CONF.new
}

ms_on() {
	[ -f $MS_ROOT/index.html ] || { ms_log "no Mainsail in $MS_ROOT"; return; }
	ms_running_with $MS_CONF && return
	mkdir -p /run/nginx
	if ! ms_build; then
		ms_log "Kiln's nginx.conf changed shape: Fluidd stays on port 80"
		rm -f $MS_CONF.new; return
	fi
	if ! $MS_NGINX -t -q -c $MS_CONF.new 2>/dev/null; then
		ms_log "nginx -t failed on the built config: Fluidd stays on port 80"
		rm -f $MS_CONF.new; return
	fi
	mv $MS_CONF.new $MS_CONF
	chmod 644 $MS_CONF
	start-stop-daemon -K -q -p $MS_PID
	sleep 1
	start-stop-daemon -S -q -x $MS_NGINX -p $MS_PID -- -c $MS_CONF
	ms_log "Mainsail on port 80, Fluidd on port 81"
}

ms_off() {
	ms_running_with $MS_CONF || return 0
	start-stop-daemon -K -q -p $MS_PID
	sleep 1
	rm -f $MS_CONF
	/etc/init.d/S63nginx start
	ms_log "Kiln's nginx back: Fluidd on port 80"
}

case "$1" in
off) ms_off ;;
*) ms_on ;;
esac
