#!/bin/sh
#####################################################################
# KILN_Mainsail root hook: Mainsail on port 80, Fluidd on port 81
# (or the other way round: WEB swaps them)
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
# The WEB macro (plugin.cfg) saves web_port80 = 'mainsail' or 'fluidd' in
# Klipper's variables.cfg. That file is writable by user klipper: it is
# parsed, never sourced. 'fluidd' swaps the two roots (Fluidd on 80,
# Mainsail on 81). A watcher ("mainsail-hook.sh watch", started once per
# boot) applies a change within about 3 s.
#
# Kiln OS has no general root boot hook; S64ad5x-camera (root, after
# S63nginx) sources /data/ad5x/camera.conf, so install.sh adds
#   . /data/ad5x/mainsail-hook.sh
# there. It is sourced again on every camera restart: does nothing when
# nginx already runs the same config. Names are prefixed (ms_): it runs
# inside S64ad5x-camera's start().
#
# Kiln OS's own update entries ("Kiln OS", klipper, moonraker) have
# configured_type kiln_os / kiln_app. Fluidd lists any type, Mainsail
# drops the ones it doesn't know. ms_patch edits Mainsail's bundle so it
# stores them as web entries (version > version, Update button, release
# link from remote_url). Mainsail's own updates replace the bundle: the
# watcher patches the new one (index.html's inode changes). On the
# Mainsail port /assets/ is revalidated instead of cached for 30 days, so
# browsers pick up the patched file.
#
# "mainsail-hook.sh off": back to Kiln's own nginx (uninstall.sh).
#####################################################################

MS_HOOK_VERSION=3

MS_ROOT=/data/ad5x/web/mainsail
MS_KILN_CONF=/etc/nginx/nginx.conf
MS_CONF=/run/nginx/kiln-mainsail.conf
MS_PID=/run/nginx/nginx.pid
MS_NGINX=/usr/sbin/nginx
MS_VARS=/home/klipper/printer_data/config/variables.cfg
MS_HOOK=/data/ad5x/mainsail-hook.sh
MS_WATCH_PID=/run/kiln-mainsail-watch.pid
MS_PATCHED=/run/kiln-mainsail.patched

ms_log() { logger -t kiln-mainsail "$*"; }

# Mainsail's update store: let it keep Kiln's update entries. In the
# minified bundle the line is
#   if([`web`,`web_beta`,`python`,`executable`].includes(o)){await
#   e(`storeWebRepo`,{...a,name:t});continue}
# (names change per build); a kiln_os / kiln_app branch goes in front.
# Files stay owned by klipper (rewritten in place), so Moonraker can
# still update Mainsail. Once per bundle: MS_PATCHED holds index.html's
# inode. A bundle still being unpacked (Mainsail update) gets 10 tries.
ms_tries=0
ms_patch() {
	ms_ino=$(ls -i $MS_ROOT/index.html 2>/dev/null | awk '{print $1}')
	[ -n "$ms_ino" ] || return
	[ "$(cat $MS_PATCHED 2>/dev/null)" = "$ms_ino" ] && return
	ms_js=$(grep -l 'storeWebRepo`,{' $MS_ROOT/assets/*.js 2>/dev/null | head -n 1)
	if [ -z "$ms_js" ]; then
		ms_tries=$((ms_tries + 1))
		[ $ms_tries -lt 10 ] && return
		ms_log "Mainsail's update store not found: Kiln OS updates not listed"
		echo "$ms_ino" > $MS_PATCHED; ms_tries=0; return
	fi
	echo "$ms_ino" > $MS_PATCHED; ms_tries=0
	grep -q '`kiln_os`' "$ms_js" && return
	ms_id='([A-Za-z_$][A-Za-z0-9_$]*)'
	sed -E 's/if\(\[`web`,`web_beta`,`python`,`executable`\]\.includes\('"$ms_id"'\)\)\{await '"$ms_id"'\(`storeWebRepo`,\{\.\.\.'"$ms_id"',name:'"$ms_id"'\}\);continue\}/if([`kiln_os`,`kiln_app`].includes(\1)){let kiln_u=(\3.remote_url||``).split(`\/`);await \2(`storeWebRepo`,{owner:kiln_u[3],repo_name:kiln_u[4],...\3,configured_type:`web`,name:\4});continue}&/' \
		"$ms_js" > "$ms_js.kiln"
	if grep -q '`kiln_os`' "$ms_js.kiln"; then
		cat "$ms_js.kiln" > "$ms_js"
		# the service worker caches the file by name (revision null): a
		# revision makes browsers fetch the patched copy
		ms_f=assets/${ms_js##*/}
		if [ -f $MS_ROOT/sw.js ]; then
			sed "s|url:\"$ms_f\",revision:null|url:\"$ms_f\",revision:\"kiln-$ms_ino\"|" \
				$MS_ROOT/sw.js > $MS_ROOT/sw.js.kiln
			cat $MS_ROOT/sw.js.kiln > $MS_ROOT/sw.js
			rm -f $MS_ROOT/sw.js.kiln
		fi
		ms_log "Mainsail patched: lists Kiln OS updates"
	else
		ms_log "Mainsail's update store changed shape: Kiln OS updates not listed"
	fi
	rm -f "$ms_js.kiln"
}

# nginx's master process runs with config $1
ms_running_with() {
	[ -f $MS_PID ] || return 1
	tr '\0' ' ' < /proc/$(cat $MS_PID)/cmdline 2>/dev/null | grep -q -- "-c $1"
}

# The UI that WEB put on port 80: fluidd or mainsail (the default)
ms_port80() {
	ms_v=$(awk -F' = ' '$1 == "web_port80" {
		v = $2; gsub(/^["\047]|["\047]$/, "", v); print v; exit
	}' $MS_VARS 2>/dev/null)
	[ "$ms_v" = fluidd ] && echo fluidd || echo mainsail
}

# ms_build UI: the config with UI on port 80
ms_build() {
	awk -v ms="$MS_ROOT" -v sw=$([ "$1" = fluidd ] && echo 1 || echo 0) '
	# one copy of the server block; port81: listen 81, mainsail: its root
	function out(port81, mainsail,   i, l) {
		for (i = 0; i < n; i++) {
			l = blk[i]
			if (mainsail && l ~ /include[ \t]+\/run\/nginx\/fluidd-root\.conf;/) {
				sub(/include.*/, "root " ms ";", l); found_root = 1
			}
			# Mainsail assets revalidated (304s), not cached 30 days:
			# browsers get the bundle ms_patch rewrote under the same name
			if (mainsail && l ~ /expires[ \t]+30d;/)
				sub(/expires.*/, "add_header Cache-Control \"no-cache\";", l)
			if (port81 && sub(/listen[ \t]+80[ \t]+default_server;/, "listen 81;", l))
				found_listen = 1
			print l
		}
	}
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
			out(0, !sw)
			print ""
			out(1, sw)
		}
		next
	}
	{ print }
	END { if (!found_root || !found_listen) exit 1 }
	' $MS_KILN_CONF > $MS_CONF.new
}

ms_on() {
	[ -f $MS_ROOT/index.html ] || { ms_log "no Mainsail in $MS_ROOT"; return; }
	ms_patch
	mkdir -p /run/nginx
	ms_ui=$(ms_port80)
	if ! ms_build $ms_ui; then
		ms_log "Kiln's nginx.conf changed shape: Fluidd stays on port 80"
		rm -f $MS_CONF.new; return
	fi
	if ms_running_with $MS_CONF && cmp -s $MS_CONF.new $MS_CONF; then
		rm -f $MS_CONF.new; return
	fi
	if ! $MS_NGINX -t -q -c $MS_CONF.new 2>/dev/null; then
		ms_log "nginx -t failed on the built config: nginx left as it is"
		rm -f $MS_CONF.new; return
	fi
	mv $MS_CONF.new $MS_CONF
	chmod 644 $MS_CONF
	start-stop-daemon -K -q -p $MS_PID
	sleep 1
	start-stop-daemon -S -q -x $MS_NGINX -p $MS_PID -- -c $MS_CONF
	if [ $ms_ui = fluidd ]; then
		ms_log "Fluidd on port 80, Mainsail on port 81"
	else
		ms_log "Mainsail on port 80, Fluidd on port 81"
	fi
}

ms_watch() {
	ms_last=$(ms_port80)
	while sleep 3; do
		ms_patch
		ms_now=$(ms_port80)
		[ "$ms_now" = "$ms_last" ] && continue
		ms_last=$ms_now
		ms_on
	done
}

ms_watch_stop() {
	start-stop-daemon -K -q -p $MS_WATCH_PID 2>/dev/null
	rm -f $MS_WATCH_PID
}

ms_off() {
	ms_watch_stop
	ms_running_with $MS_CONF || return 0
	start-stop-daemon -K -q -p $MS_PID
	sleep 1
	rm -f $MS_CONF
	/etc/init.d/S63nginx start
	ms_log "Kiln's nginx back: Fluidd on port 80"
}

case "$1" in
off) ms_off ;;
watch) ms_watch ;;
*)
	ms_on
	if ! { [ -f $MS_WATCH_PID ] && kill -0 "$(cat $MS_WATCH_PID)" 2>/dev/null; }; then
		start-stop-daemon -S -b -m -p $MS_WATCH_PID -x /bin/sh -- $MS_HOOK watch
	fi
	;;
esac
