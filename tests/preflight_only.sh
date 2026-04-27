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

run_preflight() {
  local fakebin="$1"
  local home="$2"
  PATH="$fakebin" HOME="$home" /bin/bash "$installer" --preflight-only
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

bash -n "$installer"

present_tmp="$(mktemp -d)"
version_only_tmp="$(mktemp -d)"
absent_tmp="$(mktemp -d)"
trap 'rm -rf "$present_tmp" "$version_only_tmp" "$absent_tmp"' EXIT

present_bin="$present_tmp/bin"
present_home="$present_tmp/home"
mkdir -p "$present_bin" "$present_home"
for cmd in pacman curl 7z node pnpm electron; do
  make_fake_cmd "$present_bin" "$cmd"
done
make_fake_cmd "$present_bin" npm "echo 'npm should be diagnostic only'"
make_fake_cmd "$present_bin" omarchy "echo 'Omarchy 2.0.1'"

present_output="$(run_preflight "$present_bin" "$present_home")"
assert_contains "$present_output" "Preflight-only mode"
assert_contains "$present_output" "OS        :"
assert_contains "$present_output" "Arch      :"
assert_contains "$present_output" "Omarchy   : present"
assert_contains "$present_output" "Omarchy version: Omarchy 2.0.1"
assert_contains "$present_output" "pacman: OK ($present_bin/pacman)"
assert_contains "$present_output" "curl: OK ($present_bin/curl)"
assert_contains "$present_output" "7z: OK ($present_bin/7z)"
assert_contains "$present_output" "npm: diagnostic only ($present_bin/npm)"
assert_contains "$present_output" "npm is diagnostic-only and is not required by preflight planning."
assert_contains "$present_output" "Required system/build packages: python base-devel git"
assert_contains "$present_output" "Planned package install command: sudo pacman -S --needed python base-devel git"
assert_contains "$present_output" "Skipping download, package installation, extraction, rebuild, launcher generation, Codex appearance defaults, and desktop integration."
assert_not_contains "$present_output" "Installing base packages"
assert_not_contains "$present_output" "Downloading Codex.dmg"
[[ ! -e "$present_home/Downloads/codex-macos" ]] || fail "preflight-only must not create download directory"
[[ ! -e "$present_home/apps/codex-port" ]] || fail "preflight-only must not create app directory"

version_only_bin="$version_only_tmp/bin"
version_only_home="$version_only_tmp/home"
mkdir -p "$version_only_bin" "$version_only_home"
for cmd in pacman curl 7z node pnpm electron; do
  make_fake_cmd "$version_only_bin" "$cmd"
done
make_fake_cmd "$version_only_bin" omarchy-version "echo 'Omarchy 2.1.0'"

version_only_output="$(run_preflight "$version_only_bin" "$version_only_home")"
assert_contains "$version_only_output" "Omarchy   : present"
assert_contains "$version_only_output" "Omarchy version: Omarchy 2.1.0"
assert_contains "$version_only_output" "pacman: OK ($version_only_bin/pacman)"
assert_contains "$version_only_output" "Skipping download, package installation, extraction, rebuild, launcher generation, Codex appearance defaults, and desktop integration."
assert_not_contains "$version_only_output" "Installing base packages"
assert_not_contains "$version_only_output" "Downloading Codex.dmg"
[[ ! -e "$version_only_home/Downloads/codex-macos" ]] || fail "preflight-only must not create download directory with omarchy-version detection"
[[ ! -e "$version_only_home/apps/codex-port" ]] || fail "preflight-only must not create app directory with omarchy-version detection"

absent_bin="$absent_tmp/bin"
absent_home="$absent_tmp/home"
mkdir -p "$absent_bin" "$absent_home"
for cmd in pacman curl node electron; do
  make_fake_cmd "$absent_bin" "$cmd"
done
# Leave 7z, pnpm, npm, and omarchy absent to exercise missing-status reporting.

absent_output="$(run_preflight "$absent_bin" "$absent_home")"
assert_contains "$absent_output" "Omarchy   : absent"
assert_contains "$absent_output" "Omarchy version: unavailable"
assert_contains "$absent_output" "7z: missing"
assert_contains "$absent_output" "pnpm: missing"
assert_contains "$absent_output" "npm: diagnostic only (missing)"
assert_contains "$absent_output" "Missing runtime dependencies: 7zip pnpm"
assert_contains "$absent_output" "Required system/build packages: python base-devel git"
assert_contains "$absent_output" "Planned package install command: sudo pacman -S --needed 7zip pnpm python base-devel git"
assert_not_contains "$absent_output" "Installing base packages"
[[ ! -e "$absent_home/Downloads/codex-macos" ]] || fail "preflight-only must not create download directory when Omarchy is absent"
[[ ! -e "$absent_home/apps/codex-port" ]] || fail "preflight-only must not create app directory when Omarchy is absent"

echo "Preflight-only verification passed."
