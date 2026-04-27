#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install-codex-omarchy.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_fake_cmd() {
  local dir="$1"
  local name="$2"
  local body="${3:-printf '%s fake\\n' \"$0\"}"
  cat > "$dir/$name" <<EOF
#!/bin/bash
set -euo pipefail
$body
EOF
  chmod +x "$dir/$name"
}

run_installer() {
  local fakebin="$1"
  local home="$2"
  shift 2
  PATH="$fakebin" HOME="$home" /bin/bash "$installer" "$@" 2>&1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle\n--- output ---\n$haystack"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle\n--- output ---\n$haystack"
}

assert_fails() {
  local output_var="$1"
  shift
  local output
  set +e
  output="$($@)"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail "expected command to fail"
  printf -v "$output_var" '%s' "$output"
}

bash -n "$installer"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Existing commands satisfy capabilities and avoid package actions, even with npm only diagnostic.
all_bin="$tmp/all/bin"
all_home="$tmp/all/home"
mkdir -p "$all_bin" "$all_home"
for cmd in pacman curl 7z node pnpm electron omarchy omarchy-pkg-add; do
  make_fake_cmd "$all_bin" "$cmd"
done
make_fake_cmd "$all_bin" npm "echo npm-present"
all_output="$(run_installer "$all_bin" "$all_home" --preflight-only)"
assert_contains "$all_output" "Required system/build packages: python base-devel git"
assert_contains "$all_output" "Planned package install command: omarchy-pkg-add python base-devel git"
assert_contains "$all_output" "npm: diagnostic only ($all_bin/npm)"
assert_not_contains "$all_output" "sudo pacman -S"
assert_not_contains "$all_output" "nodejs"
assert_not_contains "$all_output" "pnpm (Arch package)"

# Omarchy missing Node fails with Omarchy/mise guidance instead of Arch Node package plan.
omarchy_missing_node_bin="$tmp/omarchy-missing-node/bin"
omarchy_missing_node_home="$tmp/omarchy-missing-node/home"
mkdir -p "$omarchy_missing_node_bin" "$omarchy_missing_node_home"
for cmd in pacman curl 7z pnpm electron omarchy omarchy-pkg-add; do
  make_fake_cmd "$omarchy_missing_node_bin" "$cmd"
done
assert_fails omarchy_node_output run_installer "$omarchy_missing_node_bin" "$omarchy_missing_node_home" --preflight-only
assert_contains "$omarchy_node_output" "Missing node on Omarchy"
assert_contains "$omarchy_node_output" "Omarchy/mise Node development environment"
assert_not_contains "$omarchy_node_output" "Planned package install command"

# Omarchy missing pnpm fails with Omarchy/mise guidance and manual Arch pnpm opt-in.
omarchy_missing_pnpm_bin="$tmp/omarchy-missing-pnpm/bin"
omarchy_missing_pnpm_home="$tmp/omarchy-missing-pnpm/home"
mkdir -p "$omarchy_missing_pnpm_bin" "$omarchy_missing_pnpm_home"
for cmd in pacman curl 7z node electron omarchy omarchy-pkg-add; do
  make_fake_cmd "$omarchy_missing_pnpm_bin" "$cmd"
done
assert_fails omarchy_pnpm_output run_installer "$omarchy_missing_pnpm_bin" "$omarchy_missing_pnpm_home" --preflight-only
assert_contains "$omarchy_pnpm_output" "Missing pnpm on Omarchy"
assert_contains "$omarchy_pnpm_output" "Omarchy/mise Node development environment"
assert_contains "$omarchy_pnpm_output" "sudo pacman -S pnpm"

# Non-Omarchy pacman hosts can plan system packages for missing Node and pnpm, and 7z maps to the current 7zip package.
plain_missing_js_bin="$tmp/plain-missing-js/bin"
plain_missing_js_home="$tmp/plain-missing-js/home"
mkdir -p "$plain_missing_js_bin" "$plain_missing_js_home"
for cmd in pacman curl electron; do
  make_fake_cmd "$plain_missing_js_bin" "$cmd"
done
plain_js_output="$(run_installer "$plain_missing_js_bin" "$plain_missing_js_home" --preflight-only)"
assert_contains "$plain_js_output" "Missing runtime dependencies: 7zip nodejs pnpm"
assert_contains "$plain_js_output" "Required system/build packages: python base-devel git"
assert_contains "$plain_js_output" "Planned package install command: sudo pacman -S --needed 7zip nodejs pnpm python base-devel git"
assert_not_contains "$plain_js_output" "npm -g"

# Omarchy package helper is selected when available for installable system packages.
omarchy_pkg_bin="$tmp/omarchy-pkg/bin"
omarchy_pkg_home="$tmp/omarchy-pkg/home"
mkdir -p "$omarchy_pkg_bin" "$omarchy_pkg_home"
for cmd in pacman curl node pnpm electron omarchy omarchy-pkg-add; do
  make_fake_cmd "$omarchy_pkg_bin" "$cmd"
done
omarchy_pkg_output="$(run_installer "$omarchy_pkg_bin" "$omarchy_pkg_home" --preflight-only)"
assert_contains "$omarchy_pkg_output" "Missing runtime dependencies: 7zip"
assert_contains "$omarchy_pkg_output" "Required system/build packages: python base-devel git"
assert_contains "$omarchy_pkg_output" "Planned package install command: omarchy-pkg-add 7zip python base-devel git"
assert_not_contains "$omarchy_pkg_output" "sudo pacman -S --needed 7zip python base-devel git"

# --no-install-deps reports missing dependencies and exits before privileged installation.
no_install_bin="$tmp/no-install/bin"
no_install_home="$tmp/no-install/home"
mkdir -p "$no_install_bin" "$no_install_home"
for cmd in pacman curl node pnpm electron; do
  make_fake_cmd "$no_install_bin" "$cmd"
done
assert_fails no_install_output run_installer "$no_install_bin" "$no_install_home" --no-install-deps
assert_contains "$no_install_output" "--no-install-deps was set"
assert_contains "$no_install_output" "Missing runtime dependencies: 7zip"
assert_contains "$no_install_output" "Required system/build packages: python base-devel git"
assert_contains "$no_install_output" "Packages not installed: 7zip python base-devel git"
assert_not_contains "$no_install_output" "Installing dependencies"
assert_not_contains "$no_install_output" "Downloading Codex.dmg"
[[ ! -e "$no_install_home/Downloads/codex-macos" ]] || fail "--no-install-deps must exit before download setup"

echo "Dependency planning verification passed."
