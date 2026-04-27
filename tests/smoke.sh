#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install-codex-omarchy.sh"
readme="$repo_root/README.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[ -f "$installer" ] || fail "canonical installer install-codex-omarchy.sh is missing"

bash -n "$installer"

help_output="$(bash "$installer" --help)"
[[ "$help_output" == *"install-codex-omarchy.sh"* ]] || fail "help output must mention canonical installer name"
[[ "$help_output" == *"Omarchy"* ]] || fail "help output must describe Omarchy target"

grep -q 'install-codex-omarchy\.sh' "$readme" || fail "README must reference canonical installer name"

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
grep -q 'Homarr Labs dashboard-icons' "$readme" || fail "README must attribute Homarr Labs dashboard-icons"
grep -q 'Apache-2.0' "$readme" || fail "README must note dashboard-icons Apache-2.0 license"
grep -q 'Optional Omarchy niceties' "$readme" || fail "README must distinguish optional Omarchy niceties"

if grep -P '[^\x00-\x7F]' "$readme" >/dev/null; then
  fail "README must be ASCII English-only text"
fi

echo "Smoke verification passed."
