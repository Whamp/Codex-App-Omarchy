# Codex App for Omarchy

This repository contains a Bash installer that prepares the Codex macOS desktop app for Omarchy on x86_64 Linux.

This repository contains the installer only. It downloads the Codex DMG during setup and prepares it locally on your machine.

The canonical installer is `install-codex-omarchy.sh`.

## Quick start

```bash
git clone https://github.com/Whamp/Codex-App-Omarchy.git
cd Codex-App-Omarchy
bash ./install-codex-omarchy.sh --preflight-only
bash ./install-codex-omarchy.sh
```

After a successful install, launch Codex with:

```bash
~/apps/codex-port/run-codex.sh
```

## Prerequisites

- Omarchy on x86_64 Linux
- internet access to download the Codex DMG and Node packages
- `sudo` access when system packages must be installed
- Node and pnpm available on `PATH`, preferably through Omarchy's mise-based development environment

The preflight command checks the local platform, required commands, and planned dependency actions without downloading, extracting, rebuilding, installing packages, or changing desktop integration:

```bash
bash ./install-codex-omarchy.sh --preflight-only
```

## What the installer does

The installer performs the required setup work:

- detects the local platform, CPU architecture, Omarchy presence, Omarchy version when available, and relevant command paths
- plans dependencies command-first, so existing `curl`, `7z`, `node`, `pnpm`, `electron`, and Codex CLI commands are reused when they work
- downloads `Codex.dmg` into `~/Downloads/codex-macos`
- reuses the cached DMG on reruns by default
- cleans stale extraction and native-build working directories on reruns
- extracts `app.asar` into `~/apps/codex-port/app_asar`
- rebuilds `better-sqlite3` and `node-pty` for the installed Electron version, preferring `/usr/bin/python` for native build commands when available
- patches Codex's Linux open-target registry so the project toolbar menu can list installed editors such as VS Code, Cursor, Zed, Antigravity, JetBrains IDEs, Sublime Text, terminal editors such as Neovim/Vim when a terminal emulator is available, and a file manager fallback instead of rendering an empty dropdown
- generates `~/apps/codex-port/run-codex.sh` with absolute Electron and Codex CLI defaults
- seeds Codex's own Linux appearance state so missing sidebar translucency preferences default to opaque rendering, without overriding an explicit user preference

The native rebuild covers `better-sqlite3` for Codex state storage and `node-pty` for the integrated terminal.

## Optional Omarchy niceties

When Omarchy is detected, the installer uses Omarchy-friendly behavior where possible.

Optional Omarchy niceties include:

- using `omarchy-pkg-add` for system package installation when Omarchy and that helper are available
- creating a user-level desktop entry by default so Codex appears in the launcher
- downloading a best-effort OpenAI icon for that desktop entry
- refreshing the standard desktop application database when `update-desktop-database` is available
- printing safe guidance to reopen or restart Walker if Codex does not appear immediately

The installer does not edit Hyprland, Waybar, Walker, terminal, Omarchy source configuration, or global Electron settings. It also avoids broad Omarchy application-refresh commands by default.

## Omarchy, mise, Node, and pnpm expectations

Omarchy users commonly manage Node through Omarchy's mise-based development environment. The installer respects that setup:

- an existing `node` command satisfies the Node requirement
- an existing `pnpm` command satisfies the pnpm requirement, even when the system `pnpm` package is not installed
- `npm` is diagnostic-only and is not required by the installer
- on Omarchy, missing `node` or `pnpm` is reported with Omarchy/mise Node development environment guidance instead of automatically installing JavaScript tooling
- users who intentionally want the system `pnpm` package can install it manually outside this installer

If Omarchy is not detected but the host still provides `pacman`, missing Node and pnpm can be planned as system packages (`nodejs` and `pnpm`).

## Usage

From the repository root on an Omarchy x86_64 system:

```bash
bash ./install-codex-omarchy.sh
```

After a successful install, launch Codex with:

```bash
~/apps/codex-port/run-codex.sh
```

`run-codex.sh` supports launch-time overrides:

```bash
ELECTRON_BIN=/path/to/electron CODEX_CLI_PATH=/path/to/codex ~/apps/codex-port/run-codex.sh
```

Without overrides, the generated launcher uses the absolute Electron and Codex CLI paths discovered or installed by the installer.

## Installer options

Use `bash ./install-codex-omarchy.sh --help` to see the current help text.

Important flags:

- `--preflight-only`: print platform, command, dependency-plan, and planned-action diagnostics, then exit before installing packages, downloading, extracting, rebuilding, generating launchers, changing Codex appearance defaults, or changing desktop integration.
- `--no-install-deps`: report missing dependencies and exit before privileged package installation. This is useful when you want to install packages yourself.
- `--skip-cli-install`: do not install `@openai/codex` when no working Codex CLI is found. If a working CLI is already discovered, it is still used. If no CLI is available, the generated launcher requires `CODEX_CLI_PATH` at launch time.
- `--no-desktop-entry`: skip user-level desktop entry creation, icon download, and desktop database refresh integration.
- `--allow-rebuild-failure`: continue after a native module rebuild failure for experiments. By default, rebuild failure is fatal.
- `--force-download`: replace the cached `~/Downloads/codex-macos/Codex.dmg` before extraction. Use this to recover from a bad or stale cached download.

## Desktop entry and icon attribution

By default, the installer creates `~/.local/share/applications/codex.desktop` and points it at the generated `~/apps/codex-port/run-codex.sh` launcher. This keeps desktop launch behavior consistent with terminal launch behavior.

The desktop icon is downloaded at install time from Homarr Labs dashboard-icons via jsDelivr using the OpenAI PNG. Homarr Labs dashboard-icons is licensed under Apache-2.0. Icon download failure is non-fatal; the desktop entry falls back to a generic `codex` icon name.

## Wayland/Electron troubleshooting

Wayland/Electron troubleshooting is opt-in only. The installer does not change global Electron flags or desktop environment settings.

Codex's Electron UI includes a translucent sidebar. On some Hyprland/Wayland systems, that translucent material can render as a broken transparent pane. To make the app usable by default, the installer seeds Codex's own `~/.codex/.codex-global-state.json` appearance state so missing light and dark sidebar translucency preferences default to opaque rendering. It also updates the matching `.bak` file. If you already chose a translucent or opaque sidebar in Codex settings, the installer preserves that explicit preference. You can change it later in Codex under Settings -> General -> Appearance by toggling the variant's translucent sidebar setting.

If the Codex window still does not render correctly on your system, try launching manually with your own Electron flags or environment variables, for example:

```bash
ELECTRON_OZONE_PLATFORM_HINT=auto ~/apps/codex-port/run-codex.sh
```

Use only the flags you need for your local display issue. Remove them again if they do not help.

## Verification

Run the lightweight shell baseline before submitting changes:

```bash
./tests/smoke.sh
./tests/dependency_planning.sh
./tests/preflight_only.sh
./tests/idempotent_download_extract.sh
./tests/native_rebuild.sh
./tests/cli_launcher.sh
./tests/desktop_entry.sh
./tests/linux_open_targets_patch.sh
```

The smoke test checks that the canonical installer exists, the installer parses with `bash -n`, help output is available, README usage references the canonical script name, required README flags are documented, attribution is present, and README text stays ASCII English-only.
