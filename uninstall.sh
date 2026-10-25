#!/bin/sh
# KILN_Mainsail: remove the root part (install.sh), as root:
#   sh /data/ad5x/plugins/mainsail/uninstall.sh          keep Mainsail's files
#   sh /data/ad5x/plugins/mainsail/uninstall.sh --purge  delete them too
# Fluidd goes back to port 80. Then DISABLE_PLUGIN NAME=mainsail and
# delete /data/ad5x/plugins/mainsail.
HOOK=/data/ad5x/mainsail-hook.sh

[ "$(id -u)" = 0 ] || { echo "uninstall.sh: run as root"; exit 1; }
[ -f $HOOK ] && sh $HOOK off
# screen.conf now, camera.conf up to hook version 3
for CONF in /data/ad5x/screen.conf /data/ad5x/camera.conf; do
	[ -f $CONF ] || continue
	sed -i -e '/^# KILN_Mainsail plugin/d' -e "\\|^\\. $HOOK\$|d" $CONF
	# nothing left but comments and blank lines: it was ours
	grep -qv '^[[:space:]]*\(#.*\)\{0,1\}$' $CONF || rm -f $CONF
done
rm -f $HOOK
[ "$1" = --purge ] && rm -rf /data/ad5x/web/mainsail
echo "KILN_Mainsail root part removed; Fluidd on port 80"
