#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/install-codex-omarchy.sh"
readme="$repo_root/README.md"

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

if grep -Fq 'node-pty' "$installer" "$readme"; then
  fail "installer output/docs must not claim node-pty rebuild support"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fakebin="$tmp/bin"
mkdir -p "$fakebin"

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
printf "fake-dmg\n" > "$out"
'
make_fake "$fakebin" 7z '
echo "7z $*" >>"$FAKE_LOG"
outdir=""
for arg in "$@"; do
  case "$arg" in
    -o*) outdir="${arg#-o}" ;;
  esac
done
[ -n "$outdir" ] || { echo "7z fake missing output dir" >&2; exit 1; }
mkdir -p "$outdir/Codex.app/Contents/Resources"
printf "fake-asar\n" > "$outdir/Codex.app/Contents/Resources/app.asar"
'
make_fake "$fakebin" node '
if [ "${1:-}" = "-v" ]; then
  echo "v22.0.0"
elif [ "${1:-}" = "-p" ]; then
  echo "12.5.1"
else
  echo "node $*" >>"$FAKE_LOG"
fi
'
make_fake "$fakebin" electron '
if [ "${1:-}" = "--version" ]; then
  echo "v37.2.3"
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
  dest="$5"
  mkdir -p "$dest/node_modules/better-sqlite3"
  printf "{\"version\":\"12.5.1\"}\n" > "$dest/node_modules/better-sqlite3/package.json"
elif [ "${1:-}" = "add" ]; then
  echo "pnpm-add-env PYTHON=${PYTHON:-} npm_config_python=${npm_config_python:-}" >>"$FAKE_LOG"
  mkdir -p node_modules/.pnpm/better-sqlite3@12.5.1/node_modules/better-sqlite3
  printf "rebuilt\n" > node_modules/.pnpm/better-sqlite3@12.5.1/node_modules/better-sqlite3/native.node
  ln -s .pnpm/better-sqlite3@12.5.1/node_modules/better-sqlite3 node_modules/better-sqlite3
elif [ "${1:-}" = "dlx" ] && [ "${2:-}" = "electron-rebuild" ]; then
  echo "electron-rebuild-env PYTHON=${PYTHON:-} npm_config_python=${npm_config_python:-}" >>"$FAKE_LOG"
  if [ "${FAKE_REBUILD_FAIL:-0}" = "1" ]; then
    echo "simulated rebuild failure" >&2
    exit 42
  fi
elif [ "${1:-}" = "setup" ]; then
  :
elif [ "${1:-}" = "i" ]; then
  :
fi
'
make_fake "$fakebin" npm 'echo "10.0.0"'
make_fake "$fakebin" which 'command -v "$1" || true'
make_fake "$fakebin" codex 'echo "codex 0.0.0"'

success_home="$tmp/success-home"
log="$tmp/success.log"
mkdir -p "$success_home"
: > "$log"
run_installer "$success_home" || fail "installer should succeed when better-sqlite3 rebuild succeeds"
assert_file_contains "$log" 'Reading Electron version'
assert_file_contains "$log" 'Electron version: 37.2.3'
assert_file_contains "$log" 'pnpm add better-sqlite3@12.5.1'
assert_file_contains "$log" 'pnpm dlx electron-rebuild -v 37.2.3 -f -w better-sqlite3'
if [ -x /usr/bin/python ]; then
  assert_file_contains "$log" 'pnpm-add-env PYTHON=/usr/bin/python npm_config_python=/usr/bin/python'
  assert_file_contains "$log" 'electron-rebuild-env PYTHON=/usr/bin/python npm_config_python=/usr/bin/python'
fi
assert_file_not_contains "$log" 'node-pty'
if [ -L "$success_home/apps/codex-port/app_asar/node_modules/better-sqlite3" ]; then
  fail "rebuilt better-sqlite3 must be copied as a real directory, not a pnpm symlink"
fi
[ -f "$success_home/apps/codex-port/app_asar/node_modules/better-sqlite3/native.node" ] || fail "rebuilt better-sqlite3 native file was not copied into app_asar"

fatal_home="$tmp/fatal-home"
log="$tmp/fatal.log"
mkdir -p "$fatal_home"
: > "$log"
if FAKE_REBUILD_FAIL=1 run_installer "$fatal_home"; then
  fail "rebuild failure must be fatal by default"
fi
assert_file_contains "$log" 'electron-rebuild failed for better-sqlite3'
assert_file_contains "$log" 'Use --allow-rebuild-failure to continue anyway for experiments.'
if [ -e "$fatal_home/apps/codex-port/run-codex.sh" ]; then
  fail "default rebuild failure should stop before launcher generation"
fi

override_home="$tmp/override-home"
log="$tmp/override.log"
mkdir -p "$override_home"
: > "$log"
FAKE_REBUILD_FAIL=1 run_installer "$override_home" --allow-rebuild-failure || fail "--allow-rebuild-failure should continue after rebuild failure"
assert_file_contains "$log" 'WARNING: electron-rebuild failed for better-sqlite3'
assert_file_contains "$log" '--allow-rebuild-failure was set; continuing despite the native rebuild failure.'
[ -x "$override_home/apps/codex-port/run-codex.sh" ] || fail "override should continue to launcher generation"

echo "Native rebuild verification passed."
