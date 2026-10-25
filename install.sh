#!/bin/sh
# KILN_Mainsail: the root part (a plugin runs as user klipper and can't).
# Run once as root after cloning, and again after an update that changes
# root/mainsail-hook.sh:
#   sh /data/ad5x/plugins/mainsail/install.sh
# - downloads the latest Mainsail release into /data/ad5x/web/mainsail
#   (only when missing; Moonraker updates it after that, Fluidd/Mainsail >
#   Software Updates)
# - copies root/mainsail-hook.sh to /data/ad5x/mainsail-hook.sh
#   (root-owned, so the clone that Moonraker updates as klipper is never
#   run as root) and adds its line to /data/ad5x/screen.conf (sourced as
#   root at every boot by Kiln's screen service; a stopgap, since Kiln
#   has no plugin boot hook and v0.0.24+ no longer runs camera.conf)
# - switches nginx: Mainsail on port 80, Fluidd on port 81 (or the other
#   way round, if WEB swapped them), and starts the watcher WEB relies on
set -e
# Root shells here have umask 077: nginx (www-data) must read Mainsail
umask 022
HOOK=/data/ad5x/mainsail-hook.sh
CONF=/data/ad5x/screen.conf
OLD_CONF=/data/ad5x/camera.conf
WEB=/data/ad5x/web/mainsail
URL=https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip
LINE=". $HOOK"
D=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "install.sh: run as root"; exit 1; }
grep -qs '^[[:space:]]*\[ -f \$CONF \] && \. \$CONF' /etc/init.d/S65ad5x-screen &&
	grep -qs "^CONF=$CONF\$" /etc/init.d/S65ad5x-screen &&
	grep -qs fluidd-root.conf /etc/nginx/nginx.conf || {
	echo "install.sh: not the Kiln OS this was written for"
	echo "  (S65ad5x-screen must source $CONF, nginx.conf include fluidd-root.conf)"
	exit 1
}

if [ ! -f $WEB/index.html ]; then
	echo "downloading Mainsail ..."
	rm -rf $WEB.new
	python3 - "$URL" "$WEB.new" <<'EOF'
import io, sys, urllib.request, zipfile
data = urllib.request.urlopen(sys.argv[1], timeout=60).read()
zipfile.ZipFile(io.BytesIO(data)).extractall(sys.argv[2])
EOF
	[ -f $WEB.new/index.html ] || { echo "install.sh: download failed"; exit 1; }
	chown -R klipper:klipper $WEB.new
	mv $WEB.new $WEB
	echo "Mainsail $(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' $WEB/release_info.json) in $WEB"
fi
chmod -R a+rX $WEB

cp "$D/root/mainsail-hook.sh" $HOOK.new
chown root:root $HOOK.new
chmod 755 $HOOK.new
mv $HOOK.new $HOOK
echo "installed $HOOK (version $(sed -n 's/^MS_HOOK_VERSION=//p' $HOOK))"

# Hook versions up to 3 were sourced from camera.conf, which Kiln now
# reads as settings only (and logs our line as skipped)
if grep -qxF "$LINE" $OLD_CONF 2>/dev/null; then
	sed -i -e '/^# KILN_Mainsail plugin/d' -e "\\|^\\. $HOOK\$|d" $OLD_CONF
	grep -qv '^[[:space:]]*\(#.*\)\{0,1\}$' $OLD_CONF || rm -f $OLD_CONF
	echo "removed the old hook line from $OLD_CONF"
fi

if ! grep -qxF "$LINE" $CONF 2>/dev/null; then
	[ -f $CONF ] && cp -p $CONF $CONF.before-kiln-mainsail
	printf '# KILN_Mainsail plugin (uninstall.sh removes these two lines)\n%s\n' \
		"$LINE" >> $CONF
	echo "added the hook to $CONF"
fi
chown root:root $CONF
chmod 644 $CONF

# A new hook version: its watcher runs the old code, stop it (the hook
# starts the new one), and rebuild the nginx config from it
start-stop-daemon -K -q -p /run/kiln-mainsail-watch.pid 2>/dev/null || true
rm -f /run/kiln-mainsail-watch.pid
sh $HOOK
if [ -f /run/nginx/kiln-mainsail.conf ]; then
	if grep -qs "^web_port80 = .fluidd" /home/klipper/printer_data/config/variables.cfg; then
		echo "Fluidd on port 80, Mainsail on port 81 (WEB swaps them)"
	else
		echo "Mainsail on port 80, Fluidd on port 81 (WEB swaps them)"
	fi
else
	echo "nginx not switched, Fluidd stays on port 80: see /var/log/messages (kiln-mainsail)"
fi
