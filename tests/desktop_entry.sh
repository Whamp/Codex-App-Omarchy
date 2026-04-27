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

assert_file_exists() {
  [ -f "$1" ] || fail "expected file to exist: $1"
}

assert_file_missing() {
  [ ! -e "$1" ] || fail "expected file to be absent: $1"
}

assert_opaque_chrome_seeded() {
  /usr/bin/python - "$1" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
for key in ("appearanceLightChromeTheme", "appearanceDarkChromeTheme"):
    value = data.get(key)
    if not isinstance(value, dict) or value.get("opaqueWindows") is not True:
        raise SystemExit(f"{key}.opaqueWindows was not seeded true in {path}")
PY
}

assert_explicit_dark_translucency_preserved() {
  /usr/bin/python - "$1" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
dark = data.get("appearanceDarkChromeTheme")
light = data.get("appearanceLightChromeTheme")
if dark.get("opaqueWindows") is not False:
    raise SystemExit("explicit dark translucent preference was overwritten")
if dark.get("surface") != "#101010":
    raise SystemExit("existing dark chrome theme data was not preserved")
if light.get("opaqueWindows") is not True:
    raise SystemExit("missing light opaque preference was not seeded")
PY
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

setup_common_fakes() {
  local fakebin="$1"
  make_fake "$fakebin" sudo 'echo "sudo $*" >>"$FAKE_LOG"; "$@"'
  make_fake "$fakebin" pacman 'echo "pacman $*" >>"$FAKE_LOG"'
  make_fake "$fakebin" curl '
echo "curl $*" >>"$FAKE_LOG"
out=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; out="$1" ;;
    http*) url="$1" ;;
  esac
  shift || true
done
[ -n "$out" ] || exit 1
case "$url" in
  *dashboard-icons*/png/openai.png)
    if [ "${FAKE_ICON_FAIL:-0}" = "1" ]; then exit 22; fi
    printf "fake-openai-png\n" > "$out"
    ;;
  *)
    printf "fake-dmg\n" > "$out"
    ;;
esac
'
  make_fake "$fakebin" 7z '
echo "7z $*" >>"$FAKE_LOG"
outdir=""
for arg in "$@"; do case "$arg" in -o*) outdir="${arg#-o}" ;; esac; done
[ -n "$outdir" ] || exit 1
mkdir -p "$outdir/Codex.app/Contents/Resources"
printf "fake-asar\n" > "$outdir/Codex.app/Contents/Resources/app.asar"
'
  make_fake "$fakebin" node '
if [ "${1:-}" = "-v" ]; then echo "v22.0.0"; elif [ "${1:-}" = "-p" ]; then echo "12.5.0"; else echo "node $*" >>"$FAKE_LOG"; fi
'
  make_fake "$fakebin" electron '
if [ "${1:-}" = "--version" ]; then echo "v37.0.0"; else echo "electron $*" >>"$FAKE_LOG"; fi
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
  printf "{\"version\":\"12.5.0\"}\n" > "$dest/node_modules/better-sqlite3/package.json"
elif [ "${1:-}" = "add" ]; then
  mkdir -p node_modules/better-sqlite3
  printf "rebuilt\n" > node_modules/better-sqlite3/native.node
elif [ "${1:-}" = "dlx" ] && [ "${2:-}" = "electron-rebuild" ]; then
  :
fi
'
  make_fake "$fakebin" npm 'echo "10.0.0"'
  make_fake "$fakebin" codex 'echo fake-codex'
  make_fake "$fakebin" omarchy-pkg-add 'echo "omarchy-pkg-add $*" >>"$FAKE_LOG"'
  make_fake "$fakebin" omarchy-refresh-applications 'echo "BROAD_REFRESH $*" >>"$FAKE_LOG"; exit 99'
  make_fake "$fakebin" omarchy-refresh-config 'echo "BROAD_CONFIG_REFRESH $*" >>"$FAKE_LOG"; exit 99'
}

assert_hermetic_omarchy_helpers() {
  local fakebin="$1"
  local helper
  for helper in omarchy-pkg-add omarchy-refresh-applications omarchy-refresh-config; do
    [ "$(PATH="$fakebin:/usr/bin:/bin" command -v "$helper")" = "$fakebin/$helper" ] || fail "$helper is not masked by the test fakebin"
  done
}

run_installer() {
  local fakebin="$1"
  local home="$2"
  local log="$3"
  shift 3
  assert_hermetic_omarchy_helpers "$fakebin"
  PATH="$fakebin:/usr/bin:/bin" HOME="$home" FAKE_LOG="$log" /bin/bash "$installer" "$@" >>"$log" 2>&1
}

bash -n "$installer"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Default desktop integration: desktop file launches generated run-codex.sh,
# OpenAI icon is downloaded into the user icon cache, standard desktop database
# refresh is used, broad Omarchy refresh commands are not invoked, and Walker
# guidance is printed on Omarchy.
default_bin="$tmp/default/bin"
default_home="$tmp/default/home"
default_log="$tmp/default.log"
mkdir -p "$default_bin" "$default_home"
setup_common_fakes "$default_bin"
make_fake "$default_bin" update-desktop-database 'echo "update-desktop-database $*" >>"$FAKE_LOG"'
make_fake "$default_bin" omarchy 'echo "omarchy $*" >>"$FAKE_LOG"; echo "Omarchy 2.0"'
run_installer "$default_bin" "$default_home" "$default_log" --skip-cli-install || fail "default desktop entry run failed"
desktop_file="$default_home/.local/share/applications/codex.desktop"
icon_file="$default_home/.local/share/icons/hicolor/256x256/apps/codex-openai.png"
assert_file_exists "$desktop_file"
assert_file_exists "$icon_file"
assert_file_contains "$icon_file" "fake-openai-png"
assert_file_contains "$desktop_file" "Name=Codex"
assert_file_contains "$desktop_file" "Exec=\"$default_home/apps/codex-port/run-codex.sh\""
assert_file_contains "$desktop_file" "Icon=codex-openai"
assert_file_contains "$desktop_file" "Type=Application"
assert_file_contains "$desktop_file" "Categories=Development;"
assert_file_not_contains "$desktop_file" "Categories=Development;Utility;"
assert_file_not_contains "$desktop_file" "electron"
assert_file_contains "$default_log" "curl --fail --location --show-error -o"
assert_file_contains "$default_log" "dashboard-icons"
assert_file_contains "$default_log" "update-desktop-database $default_home/.local/share/applications"
state_file="$default_home/.codex/.codex-global-state.json"
assert_file_exists "$state_file"
assert_file_exists "$state_file.bak"
assert_opaque_chrome_seeded "$state_file"
assert_file_contains "$default_log" "Seeded Codex opaque sidebar defaults"
assert_file_not_contains "$default_log" "BROAD_REFRESH"
assert_file_not_contains "$default_log" "omarchy-refresh-applications"
assert_file_contains "$default_log" "If Codex does not appear in Walker immediately"

# --no-desktop-entry skips all desktop-entry/icon/database integration.
skip_bin="$tmp/skip/bin"
skip_home="$tmp/skip/home"
skip_log="$tmp/skip.log"
mkdir -p "$skip_bin" "$skip_home"
setup_common_fakes "$skip_bin"
make_fake "$skip_bin" update-desktop-database 'echo "update-desktop-database $*" >>"$FAKE_LOG"'
run_installer "$skip_bin" "$skip_home" "$skip_log" --skip-cli-install --no-desktop-entry || fail "skip desktop entry run failed"
assert_file_missing "$skip_home/.local/share/applications/codex.desktop"
assert_file_missing "$skip_home/.local/share/icons/hicolor/256x256/apps/codex-openai.png"
assert_file_not_contains "$skip_log" "update-desktop-database"
assert_file_contains "$skip_log" "--no-desktop-entry was set; skipping desktop entry and icon setup."

# Existing explicit translucency choices are respected; missing variant choices are seeded.
preference_bin="$tmp/preference/bin"
preference_home="$tmp/preference/home"
preference_log="$tmp/preference.log"
mkdir -p "$preference_bin" "$preference_home/.codex"
setup_common_fakes "$preference_bin"
cat > "$preference_home/.codex/.codex-global-state.json" <<'EOF_STATE'
{"appearanceDarkChromeTheme":{"opaqueWindows":false,"surface":"#101010"},"appearanceLightChromeTheme":{"surface":"#ffffff"}}
EOF_STATE
run_installer "$preference_bin" "$preference_home" "$preference_log" --skip-cli-install --no-desktop-entry || fail "explicit appearance preference run failed"
assert_explicit_dark_translucency_preserved "$preference_home/.codex/.codex-global-state.json"
assert_file_contains "$preference_log" "Preserved explicit Codex sidebar translucency settings"

# Icon download failure is non-fatal and creates a desktop entry with fallback icon metadata.
fail_icon_bin="$tmp/fail-icon/bin"
fail_icon_home="$tmp/fail-icon/home"
fail_icon_log="$tmp/fail-icon.log"
mkdir -p "$fail_icon_bin" "$fail_icon_home"
setup_common_fakes "$fail_icon_bin"
FAKE_ICON_FAIL=1 run_installer "$fail_icon_bin" "$fail_icon_home" "$fail_icon_log" --skip-cli-install || fail "icon failure should not fail installer"
assert_file_exists "$fail_icon_home/.local/share/applications/codex.desktop"
assert_file_missing "$fail_icon_home/.local/share/icons/hicolor/256x256/apps/codex-openai.png"
assert_file_contains "$fail_icon_home/.local/share/applications/codex.desktop" "Icon=codex"
assert_file_contains "$fail_icon_log" "WARNING: could not download the OpenAI desktop icon"
assert_file_contains "$fail_icon_log" "Desktop entry will use fallback icon name: codex"

# Desktop Exec values quote paths and escape literal percent signs so paths with
# spaces or desktop-entry field-code characters are parsed as one launcher path.
special_bin="$tmp/special/bin"
special_home="$tmp/special/home with % sign"
special_log="$tmp/special.log"
mkdir -p "$special_bin" "$special_home"
setup_common_fakes "$special_bin"
run_installer "$special_bin" "$special_home" "$special_log" --skip-cli-install || fail "special HOME desktop entry run failed"
special_desktop_file="$special_home/.local/share/applications/codex.desktop"
assert_file_exists "$special_desktop_file"
assert_file_contains "$special_desktop_file" "Exec=\"$tmp/special/home with %% sign/apps/codex-port/run-codex.sh\""
assert_file_not_contains "$special_desktop_file" "Exec=$special_home/apps/codex-port/run-codex.sh"
assert_file_not_contains "$special_log" "BROAD_REFRESH"
assert_file_not_contains "$special_log" "BROAD_CONFIG_REFRESH"

assert_file_not_contains "$default_log" "BROAD_CONFIG_REFRESH"
assert_file_contains "$default_log" "omarchy-pkg-add python base-devel git"

echo "Desktop entry verification passed."
