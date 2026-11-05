# Wgplex

Wgplex.app is a macOS menu bar client for the [`wgplex`](https://github.com/mrFokin/wgplex) engine. The app changes nothing in the system itself: it talks to the engine's public API (JSON-RPC 2.0 over the unix socket `<prefix>/var/run/wgplex.sock`) and shows the tunnel status. The app has no privileged code and does not read the engine's config.

Bundle identifier: `io.github.mrfokin.wgplex`. The app UI is in Russian.

## Requirements

- macOS 13 or later.
- The `wgplex` engine, installed and running:

  ```sh
  brew install mrfokin/tap/wgplex
  sudo brew services start --sudo-service-user=root wgplex
  ```

## Install

```sh
brew trust mrfokin/tap
brew install --cask mrfokin/tap/wgplex-app
```

`brew trust` is needed because Homebrew 7 does not load the `wgplex` formula (a dependency of the cask) from an untrusted tap.

The same universal (arm64 + x86_64) `.dmg` is attached to each GitHub release and can be installed manually.

## First launch and "Open Anyway"

The app has no Developer ID signature yet (ad-hoc signed, not notarized), so macOS blocks the first launch:

1. Open Wgplex. macOS shows the dialog "Wgplex" Not Opened — Apple could not verify… Click **Done** (not "Move to Trash").
2. Open System Settings, then Privacy & Security. It shows "Wgplex" was blocked to protect your Mac.
3. Click **Open Anyway** and enter an administrator password.

## Launch at login

Off by default. On first launch the app asks "Запускать Wgplex при входе?"; it can also be switched in Settings (⌘,). Each user enables it for their own account. The entry appears under System Settings, Login Items, Open at Login.

To start the app at login for all users, an administrator can add a LaunchAgent plist to `/Library/LaunchAgents` (the app itself has no privileged code), for example `/Library/LaunchAgents/io.github.mrfokin.wgplex.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.github.mrfokin.wgplex</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>-a</string>
        <string>/Applications/Wgplex.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

The file must be owned by `root:wheel` with mode `644`; it takes effect at the next login.

## Update

```sh
brew upgrade --cask wgplex-app
```

Replacing the app manually from a `.dmg` requires "Open Anyway" again.

The app checks GitHub for the latest release once a day (can be disabled with "Проверять обновления" in Settings) and shows the `brew upgrade` command when a new version is out.

## Uninstall

```sh
brew uninstall --cask wgplex-app
```

The cask's `zap` also removes the app's defaults (`brew uninstall --zap --cask wgplex-app`). The engine is separate: stop it with `sudo brew services stop --sudo-service-user=root wgplex` and remove it with `brew uninstall wgplex`. Quitting the app only closes the app; tunnels belong to the machine.

## Build from source

Swift Package, macOS 13+, no third-party dependencies.

```sh
make check   # swift build and swift test
make dmg     # dist/Wgplex-<VERSION>.dmg (+ .sha256), universal, ad-hoc signed
```

## FileVault

With FileVault, after a reboot the disk stays locked until the password is entered in preboot; macOS and the engine do not start, so tunnels come up only after unlock. For headless machines, either do not use FileVault, or use `fdesetup authrestart` for planned reboots (it does not help after a power loss).
