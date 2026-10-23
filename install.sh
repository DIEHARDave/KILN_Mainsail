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
#   run as root) and adds its line to /data/ad5x/camera.conf
# - switches nginx: Mainsail on port 80, Fluidd on port 81
set -e
# Root shells here have umask 077: nginx (www-data) must read Mainsail
umask 022
HOOK=/data/ad5x/mainsail-hook.sh
CONF=/data/ad5x/camera.conf
WEB=/data/ad5x/web/mainsail
URL=https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip
LINE=". $HOOK"
D=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "install.sh: run as root"; exit 1; }
grep -qs "$CONF" /etc/init.d/S64ad5x-camera &&
	grep -qs fluidd-root.conf /etc/nginx/nginx.conf || {
	echo "install.sh: not the Kiln OS this was written for"
	echo "  (S64ad5x-camera must read $CONF, nginx.conf include fluidd-root.conf)"
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

if ! grep -qxF "$LINE" $CONF 2>/dev/null; then
	[ -f $CONF ] && cp -p $CONF $CONF.before-kiln-mainsail
	printf '# KILN_Mainsail plugin (uninstall.sh removes these two lines)\n%s\n' \
		"$LINE" >> $CONF
	chmod 644 $CONF
	echo "added the hook to $CONF"
fi

# A new hook version: rebuild the nginx config from it
sh $HOOK off
sh $HOOK
if [ -f /run/nginx/kiln-mainsail.conf ]; then
	echo "Mainsail on port 80, Fluidd on port 81"
else
	echo "nginx not switched, Fluidd stays on port 80: see /var/log/messages (kiln-mainsail)"
fi
