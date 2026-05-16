# AGENTS.md

## Project Map

| Path | Purpose |
| --- | --- |
| `bootstrap.sh` | One-line installer entry point. Downloads the repo archive and delegates to the canonical installer. |
| `install-codex-omarchy.sh` | Canonical Omarchy installer for the Codex desktop app port. |
| `scripts/patch_codex_linux_open_targets.py` | Patches extracted Codex app code so Linux open-target menus can find editors and file managers. |
| `scripts/patch_codex_linux_remote_control_visibility.py` | Patches extracted Codex app code so Linux remote-control UI visibility matches available runtime support. |
| `tests/*.sh` | Shell regression tests. They create fake command environments and must avoid touching the real machine. |
| `docs/PROJECT.md` | Project goal, scope, parity definition, and done criteria. |

## Commands

Run the baseline before handing off changes:

```bash
./tests/smoke.sh
```

Run the full local suite when installer behavior changes:

```bash
./tests/smoke.sh
./tests/dependency_planning.sh
./tests/preflight_only.sh
./tests/idempotent_download_extract.sh
./tests/native_rebuild.sh
./tests/cli_launcher.sh
./tests/desktop_entry.sh
./tests/linux_open_targets_patch.sh
./tests/remote_control_visibility_patch.sh
```

Check syntax directly:

```bash
bash -n bootstrap.sh
bash -n install-codex-omarchy.sh
python3 -m py_compile scripts/patch_codex_linux_open_targets.py
python3 -m py_compile scripts/patch_codex_linux_remote_control_visibility.py
```

## Constraints

- Keep all committed text ASCII unless a file already requires another
  character set.
- Keep `install-codex-omarchy.sh` runnable from a local checkout and from
  `bootstrap.sh`.
- Do not make preflight install packages, download the DMG, extract files,
  rebuild native modules, generate launchers, seed Codex state, or update
  desktop integration.
- Do not edit `~/.local/share/omarchy` or user desktop configuration as part of
  tests or development.
- Prefer Omarchy helpers when present, but keep a plain Arch fallback for
  non-Omarchy preflight and tests.
- Treat `node` and `pnpm` on Omarchy as mise-managed tools. Do not silently
  replace them with Arch packages.
- Preserve user ownership when the installer is run through `sudo`.

## Installer Design Notes

- `bootstrap.sh` exists because the canonical installer depends on local
  `scripts/` files. Do not make the README pipe `install-codex-omarchy.sh`
  directly unless those dependencies are embedded or removed.
- Native module rebuilds must fail closed unless an explicit experimental flag
  is used.
- Desktop integration must be user-level only: desktop entry, icon, and
  `codex://` handler.
- Wayland/Electron troubleshooting should stay opt-in. The installer may seed
  Codex-owned app state, but should not write global Electron flags or Omarchy
  config.
