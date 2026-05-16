#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
patcher="$repo_root/scripts/patch_codex_linux_remote_control_visibility.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  ! grep -Fq -- "$needle" "$file" || fail "expected $file not to contain: $needle"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

app_dir="$tmp/app_asar"
assets_dir="$app_dir/webview/assets"
visibility_bundle="$assets_dir/remote-control-connections-visibility-test.js"
mkdir -p "$assets_dir"
cat > "$visibility_bundle" <<'EOF_BUNDLE'
import{p as e,pt as t}from"./vscode-api.js";import{r as n}from"./remote-connection-visibility.js";var r=t();function i(){let t=(0,r.c)(3),[i]=e(`remote_control_connections_state`),o=n(),s;return t[0]!==i||t[1]!==o?(s=a({remoteControlConnectionsState:i,slingshotEnabled:o}),t[0]=i,t[1]=o,t[2]=s):s=t[2],s}function a({remoteControlConnectionsState:e,slingshotEnabled:t}){return t&&(e?.available??!0)&&e?.accessRequired!==!0}export{i as t};
EOF_BUNDLE

python3 "$patcher" "$app_dir" || fail "patcher failed"
assert_file_contains "$visibility_bundle" "Codex-App-Omarchy linux-remote-control-visibility patch"
assert_file_contains "$visibility_bundle" 'return!0'
assert_file_not_contains "$visibility_bundle" 'return t&&(e?.available??!0)&&e?.accessRequired!==!0'
assert_file_not_contains "$visibility_bundle" "__codexOmarchyIsLinuxRenderer"

first_sha="$(sha256sum "$visibility_bundle" | awk '{print $1}')"
python3 "$patcher" "$app_dir" || fail "second patcher run failed"
second_sha="$(sha256sum "$visibility_bundle" | awk '{print $1}')"
[ "$first_sha" = "$second_sha" ] || fail "patcher must be idempotent"

legacy_app_dir="$tmp/legacy_app_asar"
legacy_assets_dir="$legacy_app_dir/webview/assets"
legacy_bundle="$legacy_assets_dir/remote-control-connections-visibility-test.js"
mkdir -p "$legacy_assets_dir"
cat > "$legacy_bundle" <<'EOF_LEGACY'
import{p as e,pt as t}from"./vscode-api.js";import{r as n}from"./remote-connection-visibility.js";var r=t();function i(){let t=(0,r.c)(3),[i]=e(`remote_control_connections_state`),o=n(),s;return t[0]!==i||t[1]!==o?(s=a({remoteControlConnectionsState:i,slingshotEnabled:o}),t[0]=i,t[1]=o,t[2]=s):s=t[2],s}/* Codex-App-Omarchy linux-remote-control-visibility patch */function __codexOmarchyIsLinuxRenderer(){try{return typeof navigator<`u`&&/Linux/i.test(navigator.platform??``)}catch{return!1}}function a({remoteControlConnectionsState:e,slingshotEnabled:t}){return(__codexOmarchyIsLinuxRenderer()||t)&&(e?.available??!0)&&e?.accessRequired!==!0}export{i as t};
EOF_LEGACY
python3 "$patcher" "$legacy_app_dir" || fail "legacy patch update failed"
assert_file_contains "$legacy_bundle" 'return!0'
assert_file_not_contains "$legacy_bundle" "__codexOmarchyIsLinuxRenderer"

missing_app="$tmp/missing_app_asar"
mkdir -p "$missing_app"
python3 "$patcher" "$missing_app" >"$tmp/missing.out" 2>"$tmp/missing.err" || fail "missing visibility bundle should be a non-fatal no-op"
assert_file_contains "$tmp/missing.out" "No Codex remote-control visibility bundle found"

echo "Linux remote-control visibility patch verification passed."
