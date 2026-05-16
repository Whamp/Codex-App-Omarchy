#!/usr/bin/env python3
"""Patch Codex's bundled webview to expose mobile remote-control on Linux.

The upstream desktop app gates the Settings > Connections mobile remote-control
section behind a remote-connections visibility flag. In the macOS build running
under Electron on Linux, the relay and app-server remote-control path work, but
this renderer gate can hide the local-device/mobile setup UI. For this Linux
port, expose the section outright; the user still has to click the app's
consent/authorization controls before remote control is enabled.
"""
from __future__ import annotations

import pathlib
import sys

MARKER = "Codex-App-Omarchy linux-remote-control-visibility patch"
ANCHOR = (
    "function a({remoteControlConnectionsState:e,slingshotEnabled:t}){"
    "return t&&(e?.available??!0)&&e?.accessRequired!==!0}"
)
REPLACEMENT = (
    "/* Codex-App-Omarchy linux-remote-control-visibility patch */"
    "function a({remoteControlConnectionsState:e,slingshotEnabled:t}){"
    "return!0}"
)
LEGACY_REPLACEMENTS = (
    (
        "/* Codex-App-Omarchy linux-remote-control-visibility patch */"
        "function a({remoteControlConnectionsState:e,slingshotEnabled:t}){"
        "return(e?.available??!0)&&e?.accessRequired!==!0}"
    ),
    (
        "/* Codex-App-Omarchy linux-remote-control-visibility patch */"
        "function __codexOmarchyIsLinuxRenderer(){"
        "try{return typeof navigator<`u`&&/Linux/i.test(navigator.platform??``)}catch{return!1}"
        "}"
        "function a({remoteControlConnectionsState:e,slingshotEnabled:t}){"
        "return(__codexOmarchyIsLinuxRenderer()||t)&&(e?.available??!0)&&e?.accessRequired!==!0}"
    ),
)


def find_visibility_bundles(app_asar: pathlib.Path) -> list[pathlib.Path]:
    assets_dir = app_asar / "webview" / "assets"
    if not assets_dir.is_dir():
        return []
    return sorted(assets_dir.glob("remote-control-connections-visibility-*.js"))


def patch_bundle(bundle: pathlib.Path) -> str:
    text = bundle.read_text(encoding="utf-8")
    if REPLACEMENT in text:
        return "already patched"
    for legacy in LEGACY_REPLACEMENTS:
        if legacy in text:
            bundle.write_text(text.replace(legacy, REPLACEMENT, 1), encoding="utf-8")
            return "updated"
    if MARKER in text:
        raise ValueError(f"unknown remote-control visibility patch shape in {bundle}")
    if ANCHOR not in text:
        raise ValueError(f"remote-control visibility anchor was not found in {bundle}")
    bundle.write_text(text.replace(ANCHOR, REPLACEMENT, 1), encoding="utf-8")
    return "patched"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: patch_codex_linux_remote_control_visibility.py /path/to/app_asar", file=sys.stderr)
        return 2

    app_asar = pathlib.Path(argv[1])
    bundles = find_visibility_bundles(app_asar)
    if not bundles:
        print(f"No Codex remote-control visibility bundle found under: {app_asar}")
        return 0

    patched = 0
    already = 0
    for bundle in bundles:
        result = patch_bundle(bundle)
        if result in {"patched", "updated"}:
            patched += 1
        elif result == "already patched":
            already += 1
        print(f"{bundle}: {result}")

    if patched == 0 and already == 0:
        print("No Codex remote-control visibility bundle was patched.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
