# Building and running this Settings app on the watch

The Sonic Screwdriver fork of asteroid-settings, for a TicWatch Pro 3 Ultra
(AsteroidOS 2.1 rubyfish image). Branch `asteroidos-2.1` is upstream's `2.1` tag
plus this tooling. The tag is the Settings app the watch shipped with (package
asteroid-settings 2.1-r1): all 19 QML files in the stock
`/usr/lib/asteroid-settings.so` are byte-identical to it, and the binary's
resource table names exactly those files. Each change lands as a pull request
into `asteroidos-2.1`, and is merged after it has run on the watch.

## Build

```sh
sonic/build.sh            # incremental
sonic/build.sh --clean    # from an empty build directory
```

The output is `sonic/out/asteroid-settings.so`, stripped, with its debug symbols
in `sonic/out/asteroid-settings.so.debug`.

The build runs in Docker with AsteroidOS's 2.1 SDK. The image and the SDK are
the launcher fork's (usr-ein/asteroid-launcher), so the SDK is installed once:
- **Docker image** `sonic-asteroid-launcher-sdk:2.1`. `sonic/Dockerfile` is a
  copy of the launcher fork's, so either fork can build the image.
- **SDK:** the Docker volume `sonic-asteroid-sdk-2.1`. Whichever fork builds
  first downloads the installer (1.2 GB, SHA-512 checked) into
  `~/.cache/sonic-screwdriver/asteroid-sdk-2.1/`, and installs it (about
  6.5 GB). Its Qt 5.15.16, libasteroidapp, mce and connman-qt are the exact
  builds on the watch. The SDK is x86_64-only, so the container is
  `linux/amd64` and runs under Rosetta on Apple Silicon.
- **Build tree:** the Docker volume `sonic-asteroid-settings-build`.

The watch is the `sonic-screwdriver` host in `~/.ssh/config`. Set `SONIC_WATCH`
to use another.

## Run it on the watch

```sh
sonic/deploy.sh           # install sonic/out/asteroid-settings.so
sonic/deploy.sh --stock   # back to the stock Settings app
sonic/deploy.sh --status  # which Settings app the launcher starts
```

The stock `/usr/bin/asteroid-settings` and `/usr/lib/asteroid-settings.so` are
never modified.
- **How the fork takes over:**
  - The launcher starts an app with the `Exec` name in its `.desktop` file
    (`asteroid-settings`), through `QProcess::startDetached`. The quick panel's
    Settings button does the same.
  - Its PATH is `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`, so
    `/usr/local/bin/asteroid-settings` comes before the stock script.
- **What `deploy.sh` installs:**
  - the build, as `/usr/local/lib/sonic-settings/asteroid-settings.so`, with the
    previous build kept as `asteroid-settings.so.prev`;
  - `/usr/local/bin/asteroid-settings`, from `sonic/watch/asteroid-settings`.
    Like the stock script, it starts the app through the qt5 booster
    (`invoker --single-instance --type=qt5`). If the build is missing, it
    starts the stock app;
  - the icons in `sonic/icons/`, into `/usr/share/icons/asteroid/sonic/` (see
    [Icons](#icons)).
- **Nothing restarts,** and no open app closes. A Settings app that is already
  open keeps its build until it is closed. `--status` shows it.
- **`--stock`** deletes `/usr/local/bin/asteroid-settings`, so the next start
  of Settings is the stock app.
- **Translations:** the app reads the stock translations in
  `/usr/share/translations/`, which `deploy.sh` doesn't touch. So strings the
  fork adds are in English, whatever the language.

To uninstall completely:
1. Run `sonic/deploy.sh --stock`.
2. Delete `/usr/local/lib/sonic-settings/`.
3. Once the launcher fork is uninstalled too, delete
   `/usr/share/icons/asteroid/sonic/`.

## Icons

AsteroidOS's `Icon` draws `/usr/share/icons/asteroid/<name>.svg` in a single
colour, so an icon is a monochrome SVG in that directory. The icons that the
stock theme (package asteroid-icons-ion) lacks are in `sonic/icons/`.
`deploy.sh` installs them into `/usr/share/icons/asteroid/sonic/`, and QML
names them `sonic/<name>`. `--stock` leaves them there; nothing stock uses them.

| Icon | Shows | Drawn from |
|---|---|---|
| `ios-globe-off` | The Internet entry in the menu while Wi-Fi is off | `ios-globe-outline`, crossed by the slash of the `ios-*-off` icons. The globe's strokes are cut 25 px either side of the slash, as in `ios-notifications-off`. |

The launcher fork, usr-ein/asteroid-launcher, installs its icons in the same
place. An icon both forks use is in both, and the two copies must stay
identical.
