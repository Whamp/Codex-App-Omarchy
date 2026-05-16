# Project Brief

Codex App for Omarchy exists to make the Codex macOS desktop app practical on an
Arch Linux Omarchy workstation through a one-line installer.

The intended default install command is:

```bash
curl -fsSL https://raw.githubusercontent.com/Whamp/Codex-App-Omarchy/main/bootstrap.sh | sudo bash
```

Run preflight without changing the system:

```bash
curl -fsSL https://raw.githubusercontent.com/Whamp/Codex-App-Omarchy/main/bootstrap.sh | bash -s -- --preflight-only
```

## Product Goal

The installer should give Omarchy users the same effective Codex desktop
experience that macOS users get from the official Codex DMG:

- Codex launches from the desktop app menu and from a terminal command.
- The installed app can find a working Codex CLI.
- Native Node addons are rebuilt for Linux instead of trying to load macOS
  binaries.
- Bundled plugin resources are available under system Electron.
- Browser-use and Node REPL integration work when Linux-compatible runtimes are
  available.
- Codex project open-target menus work with Linux editors, terminal editors, and
  a file manager fallback.
- Mobile remote-control UI is visible when the relay/app-server path is
  available.
- Hyprland/Wayland rendering starts from usable defaults without changing
  global Electron or Omarchy configuration.

## Current Shape

- `bootstrap.sh` is the piped one-line entry point. It downloads this repository
  to a temporary directory so the installer can use its Python patch scripts.
- `install-codex-omarchy.sh` is the canonical installer and remains runnable
  from a local checkout.
- `scripts/patch_codex_linux_open_targets.py` patches Linux editor/file-manager
  discovery inside the extracted app.
- `scripts/patch_codex_linux_remote_control_visibility.py` patches Linux
  visibility gating for remote-control controls.
- `tests/*.sh` are shell-level regression tests for installer planning,
  generated launchers, desktop integration, native rebuild checks, and patchers.

## Non-Goals

- This project does not reimplement the Codex app.
- This project does not patch Omarchy source files under
  `~/.local/share/omarchy`.
- This project does not edit Hyprland, Waybar, Walker, terminal, or global
  Electron configuration.
- This project does not replace Omarchy's mise-managed JavaScript toolchain with
  Arch packages unless the user opts into that manually.

## Compatibility Assumptions

- Primary target: Omarchy on x86_64 Arch Linux.
- Runtime shell: Bash.
- System packages: installed with `omarchy-pkg-add` when available, otherwise
  `pacman`.
- JavaScript tooling: `node` and `pnpm` are expected on `PATH`, usually through
  Omarchy/mise.

## Definition of Done

A change is ready when:

- `./tests/smoke.sh` passes.
- The focused regression test for the touched behavior passes.
- `bash ./install-codex-omarchy.sh --preflight-only` still exits before making
  filesystem or package changes beyond diagnostics.
- README and this project brief still describe the supported install path.
