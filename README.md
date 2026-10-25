# KILN_Mainsail

A [Kiln OS](https://github.com/djvalic/kiln-os) plugin for the Flashforge
AD5X that runs [Mainsail](https://github.com/mainsail-crew/mainsail) next
to Fluidd:

| Port | Web interface |
|---|---|
| 80 (`http://<printer>/`) | Mainsail |
| 81 (`http://<printer>:81/`) | Fluidd |

> **The boot hook is a stopgap.** This plugin needs a root boot hook,
> and Kiln OS has none for plugins. `camera.conf`, used before, has been
> read as settings only since Kiln v0.0.24, so `install.sh` now uses
> `/data/ad5x/screen.conf`, which Kiln's screen service still runs as a
> shell script at boot. A later Kiln release may close that too; then,
> after each reboot, Fluidd is back on port 80 until you run
> `sh /data/ad5x/mainsail-hook.sh` as root. A proper hook was requested
> in [djvalic/kiln-os#13](https://github.com/djvalic/kiln-os/issues/13).
> Installed before this change? Run `install.sh` again as root (it moves
> the line out of `camera.conf`).

Both talk to the same Moonraker and Klipper and show the same cameras
(`/webcam/`, ...) and touch screen view (`/screen/`). Settings are kept
separately: each UI has its own.

Mainsail is updated from the web UI (Software Updates, `mainsail`), like
Kiln's own Fluidd.

## Swapping the ports: `WEB`

Run `WEB` in the console to swap the two: Fluidd on port 80, Mainsail on
port 81. Run it again to swap back. nginx restarts with the new order
within about 3 seconds, so reload the page. The choice is kept across
reboots (`web_port80` in `variables.cfg`).

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

When `WEB` has saved `web_port80 = 'fluidd'`, the two roots are swapped:
port 80 keeps Kiln's Fluidd line, port 81 gets Mainsail's. The macro
runs as user `klipper` and can't restart nginx, so the hook also starts a
small root watcher (`mainsail-hook.sh watch`, once per boot) that checks
`variables.cfg` every 3 seconds and rebuilds the config when the value
changes. The file is only parsed, never run.

**Kiln OS updates in Mainsail.** Kiln lists its own updates (`Kiln OS`,
`klipper`, `moonraker`) under types Mainsail doesn't know, so plain
Mainsail hides them; Fluidd shows them. The hook patches Mainsail's
bundle in place so it lists them like any web client: version, Update
button, release link. The watcher patches again after a Mainsail update.
On the Mainsail port, `/assets/` is revalidated instead of cached for
30 days, so browsers load the patched file. If a Mainsail release changes
that code, the patch is skipped and `/var/log/messages` says so.

If Kiln's nginx.conf ever changes shape, or the check fails, nothing is
switched: Fluidd stays on port 80, and `/var/log/messages` has a
`kiln-mainsail` line saying why.

**Boot hook.** Kiln OS has no root boot hook for plugins. Its screen
service (`S65ad5x-screen`, root, runs after nginx starts) sources
`/data/ad5x/screen.conf`, so `install.sh` adds
`. /data/ad5x/mainsail-hook.sh` there. The screen service runs this
even with the screen stream switched off (`SCREEN=off`). A screen
restart sources it again, but it does nothing while nginx already runs
the Mainsail config. [KILN_Camera](https://github.com/DIEHARDave/KILN_Camera)
and [KILN_NFC](https://github.com/DIEHARDave/KILN_NFC) use the same
file; they don't interfere.

`/etc/init.d/S63nginx restart` brings back Kiln's plain nginx (Fluidd on
80) until the next boot. To switch back without rebooting, run
`sh /data/ad5x/mainsail-hook.sh`.

**Updating from 1.0.0:** `WEB` needs the new hook. Run `install.sh` once
more as root after the update; until then `WEB` saves the setting but
nothing applies it. The same goes for the Kiln OS entries in Mainsail
(hook version 3).

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
