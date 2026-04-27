# Codex App for Omarchy

Install the Codex macOS desktop app on Omarchy x86_64 Linux.

This repo contains only the installer. The installer downloads the Codex DMG, prepares it for Linux, creates a terminal launcher, and adds Codex to the Omarchy menu by default.

Canonical installer: `install-codex-omarchy.sh`.

## Quick start

```bash
git clone https://github.com/Whamp/Codex-App-Omarchy.git
cd Codex-App-Omarchy
bash ./install-codex-omarchy.sh --preflight-only
bash ./install-codex-omarchy.sh
```

After install, open Codex from the Omarchy menu or launcher. You do not need to start it from the script every time.

For terminal launches, use:

```bash
~/apps/codex-port/run-codex.sh
```

## Requirements

- Omarchy on x86_64 Linux
- Internet access for the Codex DMG and Node packages
- `sudo` access if system packages must be installed
- `node` and `pnpm` on `PATH`, usually from Omarchy/mise

Run preflight first to see what the installer would do without changing your system:

```bash
bash ./install-codex-omarchy.sh --preflight-only
```

Preflight checks the platform, commands, dependency plan, and planned actions. It does not install packages, download, extract, rebuild, generate launchers, change Codex appearance defaults, or change desktop integration.

## What the installer does

- Downloads `Codex.dmg` to `~/Downloads/codex-macos` and reuses the cached file on reruns.
- Extracts `app.asar` to `~/apps/codex-port/app_asar`.
- Copies Codex's bundled plugin resources to `~/apps/codex-port/resources` so bundled plugins such as Browser Use can auto-install under system Electron.
- Rebuilds `better-sqlite3` and `node-pty` for the installed Electron version.
- Patches Codex's Linux open-target registry so the project toolbar can list installed editors, terminal editors, and a file manager fallback.
- Fails before launcher generation if any loadable `.node` addon is still a Mach-O binary after rebuilds.
- Generates `~/apps/codex-port/run-codex.sh` with discovered Electron, Codex CLI, and browser-use runtime defaults when available.
- Seeds Codex's sidebar appearance state so missing translucent sidebar preferences default to opaque rendering without overriding your explicit setting.

## Optional Omarchy niceties

When Omarchy is detected, the installer also tries to:

- Use `omarchy-pkg-add` for system packages when available.
- Create `~/.local/share/applications/codex.desktop` so Codex appears in the Omarchy menu/launcher.
- Download a best-effort OpenAI icon for the desktop entry.
- Refresh the desktop application database when `update-desktop-database` is available.
- Print safe guidance to reopen or restart Walker if Codex does not appear immediately.

The installer does not edit Hyprland, Waybar, Walker, terminal, Omarchy source configuration, or global Electron settings. It also avoids broad Omarchy application-refresh commands by default.

## Omarchy/mise, Node, and pnpm

The installer respects Omarchy's mise-based development setup:

- Existing `node` and `pnpm` commands satisfy the requirement.
- `npm` is diagnostic-only and is not required.
- On Omarchy, missing `node` or `pnpm` is reported with Omarchy/mise guidance instead of automatic JavaScript tooling installation.
- Outside Omarchy, a host with `pacman` may plan `nodejs` and `pnpm` as system packages.

## Installer options

See all options:

```bash
bash ./install-codex-omarchy.sh --help
```

Common flags:

- `--preflight-only`: print diagnostics and exit before making changes.
- `--no-install-deps`: report missing dependencies and exit before privileged package installation.
- `--skip-cli-install`: do not install `@openai/codex` when no working Codex CLI is found.
- `--no-desktop-entry`: skip desktop entry creation, icon download, and desktop database refresh.
- `--allow-rebuild-failure`: continue after native module rebuild failure for experiments. By default, rebuild failure is fatal.
- `--force-download`: replace the cached `~/Downloads/codex-macos/Codex.dmg` before extraction.

## Launch-time overrides

The generated launcher uses the Electron and Codex CLI paths found during install. Override them when needed:

```bash
ELECTRON_BIN=/path/to/electron CODEX_CLI_PATH=/path/to/codex ~/apps/codex-port/run-codex.sh
```

For Codex browser-use JavaScript execution:

```bash
CODEX_BROWSER_USE_NODE_PATH=/path/to/linux/node \
CODEX_NODE_REPL_PATH=/path/to/linux/node_repl \
~/apps/codex-port/run-codex.sh
```

For Codex bundled plugin discovery under system Electron:

```bash
CODEX_ELECTRON_RESOURCES_PATH=/path/to/codex/resources ~/apps/codex-port/run-codex.sh
```

If no Linux `node_repl` is found, Codex chat and the integrated terminal still work. Browser-use JavaScript REPL support stays disabled until `CODEX_NODE_REPL_PATH` is provided.

## Desktop entry and icon attribution

By default, the installer creates `~/.local/share/applications/codex.desktop`. That desktop entry points to `~/apps/codex-port/run-codex.sh`, so menu launches and terminal launches use the same runtime.

The desktop icon is downloaded from Homarr Labs dashboard-icons through jsDelivr using the OpenAI PNG. Homarr Labs dashboard-icons is licensed under Apache-2.0. Icon download failure is non-fatal; the desktop entry falls back to a generic `codex` icon name.

## Wayland/Electron troubleshooting

Wayland/Electron troubleshooting is opt-in only. The installer does not change global Electron flags or desktop environment settings.

Codex's Electron UI includes a translucent sidebar. On some Hyprland/Wayland systems, it can render as a broken transparent pane. To keep Codex usable by default, the installer seeds Codex's own `~/.codex/.codex-global-state.json` appearance state so missing light and dark sidebar translucency preferences default to opaque rendering. It also updates the matching `.bak` file. If you already chose a translucent or opaque sidebar in Codex settings, the installer keeps your choice.

You can change this later in Codex under Settings -> General -> Appearance.

If the Codex window still renders incorrectly, try your own Electron flags, for example:

```bash
ELECTRON_OZONE_PLATFORM_HINT=auto ~/apps/codex-port/run-codex.sh
```

Keep only flags that help your system.

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

## License

MIT. See [LICENSE](LICENSE).
