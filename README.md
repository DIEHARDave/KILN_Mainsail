# KILN_Mainsail

A [Kiln OS](https://github.com/djvalic/kiln-os) plugin for the Flashforge
AD5X that runs [Mainsail](https://github.com/mainsail-crew/mainsail) next
to Fluidd:

| Port | Web interface |
|---|---|
| 80 (`http://<printer>/`) | Mainsail |
| 81 (`http://<printer>:81/`) | Fluidd |

Both talk to the same Moonraker and Klipper and show the same cameras
(`/webcam/`, ...) and touch screen view (`/screen/`). Settings are kept
separately: each UI has its own.

Mainsail is updated from the web UI (Software Updates, `mainsail`), like
Kiln's own Fluidd.

## Install

Two parts: the plugin itself (runs as user `klipper`), and a root part
that a plugin can't install by itself. Over SSH as root (Kiln's default
password is `root`):

```sh
cd /data/ad5x/plugins
su klipper -s /bin/sh -c 'git clone https://github.com/DIEHARDave/KILN_Mainsail.git mainsail'
sh /data/ad5x/plugins/mainsail/install.sh
```

`install.sh` downloads the latest Mainsail release (about 3 MB) into
`/data/ad5x/web/mainsail`, then switches nginx over. Mainsail is on port
80 as soon as it finishes.

Then in the console (Mainsail, Fluidd or HelixScreen):

```
ENABLE_PLUGIN NAME=mainsail
```

This restarts Klipper and Moonraker. After that, Software Updates lists
`mainsail` (the UI) and `kiln-mainsail` (this plugin). The plugin also
adds pass-through `PAUSE` / `RESUME` macros, because Mainsail warns
without them.

## Updates

- **Mainsail:** Software Updates > `mainsail`.
- **This plugin:** Software Updates > `kiln-mainsail`. If the update
  changed `root/mainsail-hook.sh`, run `install.sh` again as root.

## How it works

Kiln's `nginx.conf` sits on the read-only system partition and serves
Fluidd on port 80. Only the line that points at Fluidd's folder,
`/run/nginx/fluidd-root.conf`, is written at boot. The hook
(`root/mainsail-hook.sh`, copied to `/data/ad5x/mainsail-hook.sh` and
owned by root) does this at boot:

1. It reads Kiln's `nginx.conf` and writes `/run/nginx/kiln-mainsail.conf`
   with the server block twice:
   - port 80 with `root /data/ad5x/web/mainsail;`;
   - port 81 exactly as Kiln has it (Fluidd).

   Every location (Moonraker API, websocket, webcams, screen) is copied
   from Kiln's file. So a Kiln update that changes nginx.conf is picked up
   at the next boot.
2. It checks the new file with `nginx -t`, then restarts nginx on it. It
   uses Kiln's pid file, so `S63nginx stop` and `S63nginx reload` still
   work.

If Kiln's nginx.conf ever changes shape, or the check fails, nothing is
switched: Fluidd stays on port 80, and `/var/log/messages` has a
`kiln-mainsail` line saying why.

**Boot hook.** Kiln OS has no general root boot hook. Its camera service
(`S64ad5x-camera`, root, runs after nginx starts) sources
`/data/ad5x/camera.conf`, so `install.sh` adds
`. /data/ad5x/mainsail-hook.sh` there. The camera service runs this
whether or not you have a camera. A camera restart sources it again, but
it does nothing while nginx already runs the Mainsail config.
[KILN_Camera](https://github.com/DIEHARDave/KILN_Camera) uses the same
file; the two don't interfere.

`/etc/init.d/S63nginx restart` brings back Kiln's plain nginx (Fluidd on
80) until the next boot. To switch back without rebooting, run
`sh /data/ad5x/mainsail-hook.sh`.

## Uninstall

As root:

```sh
sh /data/ad5x/plugins/mainsail/uninstall.sh            # keeps Mainsail's files
sh /data/ad5x/plugins/mainsail/uninstall.sh --purge    # deletes them too
```

Fluidd is back on port 80 right away. Then run
`DISABLE_PLUGIN NAME=mainsail` and delete `/data/ad5x/plugins/mainsail`.

## License

GPLv3, like Klipper and Kiln OS. Mainsail itself is GPLv3, by the
Mainsail crew.
