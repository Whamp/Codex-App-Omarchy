#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install-codex-omarchy.sh"

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

make_fake() {
  local dir="$1"
  local name="$2"
  local body="$3"
  cat > "$dir/$name" <<EOF_FAKE
#!/usr/bin/env bash
set -euo pipefail
$body
EOF_FAKE
  chmod +x "$dir/$name"
}

run_installer() {
  local home="$1"
  shift
  PATH="$fakebin:/usr/bin:/bin" HOME="$home" FAKE_LOG="$log" /bin/bash "$installer" "$@" >>"$log" 2>&1
}

bash -n "$installer"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fakebin="$tmp/bin"
home="$tmp/home"
log="$tmp/commands.log"
mkdir -p "$fakebin" "$home"
: > "$log"

make_fake "$fakebin" sudo 'echo "sudo $*" >>"$FAKE_LOG"; "$@"'
make_fake "$fakebin" pacman 'echo "pacman $*" >>"$FAKE_LOG"'
make_fake "$fakebin" curl '
echo "curl $*" >>"$FAKE_LOG"
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    out="$1"
  fi
  shift || true
done
[ -n "$out" ] || { echo "curl fake missing -o" >&2; exit 1; }
if [ "${FAKE_CURL_FAIL:-0}" = "1" ]; then
  printf "partial-download\n" > "$out"
  echo "simulated curl failure" >&2
  exit 22
fi
printf "%s\n" "${FAKE_DMG_CONTENT:-downloaded-dmg}" > "$out"
'
make_fake "$fakebin" 7z '
echo "7z $*" >>"$FAKE_LOG"
outdir=""
archive=""
for arg in "$@"; do
  case "$arg" in
    -o*) outdir="${arg#-o}" ;;
    *.dmg) archive="$arg" ;;
  esac
done
[ -n "$outdir" ] || { echo "7z fake missing output dir" >&2; exit 1; }
[ -n "$archive" ] || { echo "7z fake missing archive" >&2; exit 1; }
mkdir -p "$outdir/Codex.app/Contents/Resources"
printf "asar from %s" "$(cat "$archive")" > "$outdir/Codex.app/Contents/Resources/app.asar"
'
make_fake "$fakebin" node '
if [ "${1:-}" = "-v" ]; then
  echo "v22.0.0"
elif [ "${1:-}" = "-p" ]; then
  echo "12.5.0"
else
  echo "node $*" >>"$FAKE_LOG"
fi
'
make_fake "$fakebin" electron '
if [ "${1:-}" = "--version" ]; then
  echo "v37.0.0"
else
  echo "electron $*" >>"$FAKE_LOG"
fi
'
make_fake "$fakebin" pnpm '
echo "pnpm $*" >>"$FAKE_LOG"
if [ "${1:-}" = "-v" ]; then
  echo "10.0.0"
elif [ "${1:-}" = "dlx" ] && [ "${2:-}" = "asar" ] && [ "${3:-}" = "--version" ]; then
  echo "1.0.0"
elif [ "${1:-}" = "dlx" ] && [ "${2:-}" = "asar" ] && [ "${3:-}" = "extract" ]; then
  src="$4"
  dest="$5"
  mkdir -p "$dest/node_modules/better-sqlite3"
  cp "$src" "$dest/extracted-from-app.asar"
  printf "{\"version\":\"12.5.0\"}\n" > "$dest/node_modules/better-sqlite3/package.json"
elif [ "${1:-}" = "add" ]; then
  mkdir -p node_modules/better-sqlite3
  printf "rebuilt\n" > node_modules/better-sqlite3/native.node
elif [ "${1:-}" = "dlx" ] && [ "${2:-}" = "electron-rebuild" ]; then
  :
elif [ "${1:-}" = "setup" ]; then
  :
elif [ "${1:-}" = "i" ]; then
  :
fi
'
make_fake "$fakebin" npm 'echo "10.0.0"'
make_fake "$fakebin" which 'command -v "$1" || true'
make_fake "$fakebin" codex 'echo "codex 0.0.0"'

FAKE_DMG_CONTENT="first-download" run_installer "$home" --no-desktop-entry || fail "first install failed"
dmg="$home/Downloads/codex-macos/Codex.dmg"
root_app="$home/apps/codex-port"
[ -f "$dmg" ] || fail "installer should download DMG when no cached copy exists"
assert_file_contains "$dmg" "first-download"
assert_file_contains "$root_app/app_asar/extracted-from-app.asar" "asar from first-download"
assert_file_contains "$log" "curl --fail --location --show-error -o"

curl_count_before="$(grep -c '^curl ' "$log")"
printf "stale app\n" > "$root_app/app_asar/stale-file"
mkdir -p "$root_app/dmg_extracted/stale-dir" "$root_app/_better-sqlite3-build"
printf "stale dmg extraction\n" > "$root_app/dmg_extracted/stale-dir/stale-file"
printf "stale build\n" > "$root_app/_better-sqlite3-build/stale-file"

FAKE_DMG_CONTENT="second-download-should-not-be-used" run_installer "$home" --no-desktop-entry || fail "cached rerun failed"
curl_count_after="$(grep -c '^curl ' "$log")"
[ "$curl_count_after" = "$curl_count_before" ] || fail "normal rerun should reuse cached DMG without curl"
assert_file_contains "$dmg" "first-download"
[ ! -e "$root_app/app_asar/stale-file" ] || fail "normal rerun should clean app_asar before extraction"
[ ! -e "$root_app/dmg_extracted/stale-dir/stale-file" ] || fail "normal rerun should clean dmg_extracted before extraction"
[ ! -e "$root_app/_better-sqlite3-build/stale-file" ] || fail "normal rerun should clean native build directory"
assert_file_contains "$root_app/app_asar/extracted-from-app.asar" "asar from first-download"

FAKE_DMG_CONTENT="forced-download" run_installer "$home" --force-download --no-desktop-entry || fail "force-download rerun failed"
[ "$(grep -c '^curl ' "$log")" -eq $((curl_count_after + 1)) ] || fail "--force-download should invoke curl again"
assert_file_contains "$dmg" "forced-download"
assert_file_contains "$root_app/app_asar/extracted-from-app.asar" "asar from forced-download"
assert_file_not_contains "$dmg" "first-download"

if FAKE_CURL_FAIL=1 run_installer "$home" --force-download --no-desktop-entry; then
  fail "force-download should fail when curl fails"
fi
assert_file_contains "$dmg" "forced-download"
assert_file_not_contains "$dmg" "partial-download"
if find "$home/Downloads/codex-macos" -maxdepth 1 -name 'Codex.dmg.tmp.*' | grep -q .; then
  fail "failed force-download should remove temporary DMG file"
fi

echo "Idempotent download/extraction verification passed."
