#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
patcher="$repo_root/scripts/patch_codex_linux_open_targets.py"

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
build_dir="$app_dir/.vite/build"
main_bundle="$build_dir/main-test.js"
mkdir -p "$build_dir"
cat > "$main_bundle" <<'EOF_BUNDLE'
function Td(e){return[]}
function Id(e){return e}
var Ed=Td(process.platform),Dd=Id(Ed),Od=new Set(Ed.filter(e=>e.kind===`editor`).map(e=>e.id)),kd=null,Ad=null;
EOF_BUNDLE

python3 "$patcher" "$app_dir" || fail "patcher failed"
assert_file_contains "$main_bundle" "Codex-App-Omarchy linux-open-targets patch"
assert_file_contains "$main_bundle" 'function __codexOmarchyLinuxOpenTargets(x)'
assert_file_not_contains "$main_bundle" 'function __codexOmarchyLinuxOpenTargets(e)'
assert_file_contains "$main_bundle" '`vscode`'
assert_file_contains "$main_bundle" '`cursor`'
assert_file_contains "$main_bundle" '`antigravity`'
assert_file_contains "$main_bundle" '`zed`'
assert_file_contains "$main_bundle" '`fileManager`'
assert_file_contains "$main_bundle" '`idea`'
assert_file_contains "$main_bundle" '`neovim`'
assert_file_contains "$main_bundle" '`helix`'
assert_file_contains "$main_bundle" 'No terminal emulator is available for terminal editor target'
assert_file_contains "$main_bundle" 'process.platform===`linux`?__codexOmarchyLinuxOpenTargets(Td(process.platform)):Td(process.platform)'
assert_file_not_contains "$main_bundle" 'var Ed=Td(process.platform),Dd=Id(Ed)'

first_sha="$(sha256sum "$main_bundle" | awk '{print $1}')"
python3 "$patcher" "$app_dir" || fail "second patcher run failed"
second_sha="$(sha256sum "$main_bundle" | awk '{print $1}')"
[ "$first_sha" = "$second_sha" ] || fail "patcher must be idempotent"

missing_app="$tmp/missing_app_asar"
mkdir -p "$missing_app"
python3 "$patcher" "$missing_app" >/"$tmp/missing.out" 2>/"$tmp/missing.err" || fail "missing main bundle should be a non-fatal no-op"
assert_file_contains "$tmp/missing.out" "No Codex main bundle found"

echo "Linux open-target patch verification passed."
