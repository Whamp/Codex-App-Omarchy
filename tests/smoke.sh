#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install-codex-omarchy.sh"
bootstrap="$repo_root/bootstrap.sh"
readme="$repo_root/README.md"
linux_open_targets_patcher="$repo_root/scripts/patch_codex_linux_open_targets.py"
linux_remote_control_visibility_patcher="$repo_root/scripts/patch_codex_linux_remote_control_visibility.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -f "$installer" ] || fail "canonical installer install-codex-omarchy.sh is missing"
[ -f "$bootstrap" ] || fail "one-line bootstrap bootstrap.sh is missing"
[ -f "$linux_open_targets_patcher" ] || fail "Linux open-target patcher is missing"
[ -f "$linux_remote_control_visibility_patcher" ] || fail "Linux remote-control visibility patcher is missing"

bash -n "$installer"
bash -n "$bootstrap"
python3 -m py_compile "$linux_open_targets_patcher"
python3 -m py_compile "$linux_remote_control_visibility_patcher"

help_output="$(bash "$installer" --help)"
[[ "$help_output" == *"install-codex-omarchy.sh"* ]] || fail "help output must mention canonical installer name"
[[ "$help_output" == *"Omarchy"* ]] || fail "help output must describe Omarchy target"

bootstrap_help_output="$(bash "$bootstrap" --help)"
[[ "$bootstrap_help_output" == *"bootstrap.sh"* ]] || fail "bootstrap help output must mention bootstrap.sh"
[[ "$bootstrap_help_output" == *"install-codex-omarchy.sh"* ]] || fail "bootstrap help output must mention delegated installer"

grep -q 'install-codex-omarchy\.sh' "$readme" || fail "README must reference canonical installer name"
grep -q 'bootstrap\.sh' "$readme" || fail "README must reference one-line bootstrap"
grep -q 'raw.githubusercontent.com/Whamp/Codex-App-Omarchy/main/bootstrap\.sh' "$readme" || fail "README must document one-line bootstrap URL"

for flag in \
  '--preflight-only' \
  '--no-install-deps' \
  '--skip-cli-install' \
  '--no-desktop-entry' \
  '--allow-rebuild-failure' \
  '--force-download'; do
  grep -q -- "$flag" "$readme" || fail "README must document $flag"
done

grep -q 'Omarchy/mise' "$readme" || fail "README must document Omarchy/mise expectations"
grep -q 'Wayland/Electron troubleshooting' "$readme" || fail "README must document Wayland/Electron troubleshooting"
grep -q 'opt-in' "$readme" || fail "README must say Wayland/Electron troubleshooting is opt-in"
grep -q 'translucent sidebar' "$readme" || fail "README must document the Codex translucent sidebar workaround"
grep -q 'opaque rendering' "$readme" || fail "README must document the opaque rendering default"
grep -q 'open-target registry' "$readme" || fail "README must document the Linux open-target patch"
grep -q 'mobile remote-control' "$readme" || fail "README must document the Linux mobile remote-control patch"
grep -q 'Homarr Labs dashboard-icons' "$readme" || fail "README must attribute Homarr Labs dashboard-icons"
grep -q 'Apache-2.0' "$readme" || fail "README must note dashboard-icons Apache-2.0 license"
grep -q 'Optional Omarchy niceties' "$readme" || fail "README must distinguish optional Omarchy niceties"

if grep -P '[^\x00-\x7F]' "$readme" >/dev/null; then
  fail "README must be ASCII English-only text"
fi

echo "Smoke verification passed."
