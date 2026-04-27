#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: bash ./install-codex-omarchy.sh [--help] [--preflight-only] [--no-install-deps] [--force-download] [--allow-rebuild-failure] [--skip-cli-install] [--no-desktop-entry]

Prepare the Codex macOS desktop app for Omarchy systems.

Options:
  -h, --help        Show this help text and exit.
  --preflight-only   Print platform, command, and dependency-plan diagnostics,
                     then exit before installing packages, downloading,
                     extracting, rebuilding, generating launchers, changing
                     Codex appearance defaults, or changing desktop integration.
  --no-install-deps  Report missing dependencies and exit before privileged
                     package installation.
  --force-download   Replace the cached Codex.dmg before extraction.
  --allow-rebuild-failure
                     Continue after a native module rebuild failure
                     for experiments. By default, rebuild failure is fatal.
  --skip-cli-install
                     Do not install @openai/codex when no working CLI is found.
                     Useful for tests and custom setups that provide
                     CODEX_CLI_PATH at launch time.
  --no-desktop-entry
                     Skip user-level desktop entry, icon download, and desktop
                     database refresh integration.
EOF
}

INSTALLER_PATH="${BASH_SOURCE[0]}"
case "$INSTALLER_PATH" in
  */*) INSTALLER_DIR="$(cd "${INSTALLER_PATH%/*}" && pwd)" ;;
  *) INSTALLER_DIR="$(pwd)" ;;
esac

PREFLIGHT_ONLY=0
NO_INSTALL_DEPS=0
FORCE_DOWNLOAD=0
ALLOW_REBUILD_FAILURE=0
SKIP_CLI_INSTALL=0
NO_DESKTOP_ENTRY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=1
      ;;
    --no-install-deps)
      NO_INSTALL_DEPS=1
      ;;
    --force-download)
      FORCE_DOWNLOAD=1
      ;;
    --allow-rebuild-failure)
      ALLOW_REBUILD_FAILURE=1
      ;;
    --skip-cli-install)
      SKIP_CLI_INSTALL=1
      ;;
    --no-desktop-entry)
      NO_DESKTOP_ENTRY=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help >&2
      exit 2
      ;;
  esac
  shift
done

##
## Codex macOS -> Omarchy installer
## Usage:
##   bash ./install-codex-omarchy.sh
##

RUNTIME_INSTALL_PACKAGES=()
BUILD_INSTALL_PACKAGES=()
INSTALL_PACKAGES=()
FATAL_DEPENDENCY_MESSAGES=()

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

add_unique_package() {
  local array_name="$1"
  local pkg="$2"
  local existing
  local -n packages_ref="$array_name"
  for existing in "${packages_ref[@]}"; do
    [ "$existing" = "$pkg" ] && return 0
  done
  packages_ref+=("$pkg")
}

add_runtime_install_package() {
  add_unique_package RUNTIME_INSTALL_PACKAGES "$1"
}

add_build_install_package() {
  add_unique_package BUILD_INSTALL_PACKAGES "$1"
}

refresh_install_packages() {
  INSTALL_PACKAGES=("${RUNTIME_INSTALL_PACKAGES[@]}" "${BUILD_INSTALL_PACKAGES[@]}")
}

add_fatal_dependency_message() {
  FATAL_DEPENDENCY_MESSAGES+=("$1")
}

join_words() {
  local IFS=' '
  echo "$*"
}

CODEX_CLI_DEFAULT=""
CODEX_CLI_SOURCE=""

is_executable_file() {
  [ -n "${1:-}" ] && [ -f "$1" ] && [ -x "$1" ]
}

is_working_codex_cli() {
  is_executable_file "$1" || return 1
  "$1" --version >/dev/null 2>&1 || return 1
}

absolute_executable_path() {
  local executable_path="$1"
  local executable_dir
  local executable_base

  is_executable_file "$executable_path" || return 1

  if command -v realpath >/dev/null 2>&1; then
    realpath "$executable_path" && return 0
  fi

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$executable_path" && return 0
  fi

  executable_dir="$(dirname -- "$executable_path")"
  executable_base="$(basename -- "$executable_path")"
  (
    cd -P -- "$executable_dir"
    printf '%s/%s\n' "$(pwd -P)" "$executable_base"
  )
}

discover_codex_cli() {
  CODEX_CLI_DEFAULT=""
  CODEX_CLI_SOURCE=""

  if is_working_codex_cli "${CODEX_CLI_PATH:-}"; then
    CODEX_CLI_DEFAULT="$(absolute_executable_path "$CODEX_CLI_PATH")"
    CODEX_CLI_SOURCE="CODEX_CLI_PATH"
    return 0
  fi

  local codex_on_path
  codex_on_path="$(command -v codex 2>/dev/null || true)"
  if is_working_codex_cli "$codex_on_path"; then
    CODEX_CLI_DEFAULT="$(absolute_executable_path "$codex_on_path")"
    CODEX_CLI_SOURCE="PATH"
    return 0
  fi

  return 1
}

ensure_codex_cli() {
  echo
  echo "=== [5] Codex CLI discovery/install ==="

  if discover_codex_cli; then
    if [ "$CODEX_CLI_SOURCE" = "CODEX_CLI_PATH" ]; then
      echo "Using Codex CLI from CODEX_CLI_PATH: $CODEX_CLI_DEFAULT"
    else
      echo "Using Codex CLI from PATH: $CODEX_CLI_DEFAULT"
    fi
    echo "Skipping Codex CLI installation because a working CLI was found."
    return 0
  fi

  if [ "$SKIP_CLI_INSTALL" -eq 1 ]; then
    echo "--skip-cli-install was set; not installing Codex CLI."
    echo "No working Codex CLI was found. The generated launcher will require CODEX_CLI_PATH to point to an executable codex CLI."
    return 0
  fi

  echo "No working Codex CLI found; installing @openai/codex with pnpm."
  echo "Configuring the pnpm global environment (pnpm setup)..."
  "$PNPM_BIN" setup || true
  mkdir -p "$PNPM_HOME/global/5"

  case ":$PATH:" in
    *":$PNPM_HOME:"*) : ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
  esac

  if ! "$PNPM_BIN" i -g @openai/codex; then
    echo "Codex CLI installation failed. Install @openai/codex manually or rerun with --skip-cli-install and provide CODEX_CLI_PATH." >&2
    exit 1
  fi

  hash -r
  if PATH="$PNPM_HOME:$PATH" discover_codex_cli; then
    echo "Using Codex CLI after pnpm install: $CODEX_CLI_DEFAULT"
    return 0
  fi

  echo "Codex CLI installation completed, but no executable codex command was found in PNPM_HOME or PATH." >&2
  echo "Expected a codex executable under: $PNPM_HOME" >&2
  exit 1
}

shell_quote() {
  printf '%q' "$1"
}

desktop_exec_quote() {
  local value="$1"
  value="${value//%/%%}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\`/\\\`}"
  value="${value//\$/\\\$}"
  printf '"%s"' "$value"
}

write_launcher() {
  local electron_default="$1"
  local codex_default="${2:-}"
  local electron_default_quoted
  local codex_default_quoted
  electron_default_quoted="$(shell_quote "$electron_default")"

  if [ -n "$codex_default" ]; then
    codex_default_quoted="$(shell_quote "$codex_default")"
    cat > "$ROOT_APP_DIR/run-codex.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
APP_DIR="\$ROOT_DIR/app_asar"

export ELECTRON_FORCE_IS_PACKAGED=1
export NODE_ENV=production

ELECTRON_BIN="\${ELECTRON_BIN:-}"
if [ -z "\$ELECTRON_BIN" ]; then
  ELECTRON_BIN=$electron_default_quoted
fi
CODEX_CLI_PATH="\${CODEX_CLI_PATH:-}"
if [ -z "\$CODEX_CLI_PATH" ]; then
  CODEX_CLI_PATH=$codex_default_quoted
fi
export CODEX_CLI_PATH

"\$ELECTRON_BIN" "\$APP_DIR"
EOF
  else
    cat > "$ROOT_APP_DIR/run-codex.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
APP_DIR="\$ROOT_DIR/app_asar"

export ELECTRON_FORCE_IS_PACKAGED=1
export NODE_ENV=production

ELECTRON_BIN="\${ELECTRON_BIN:-}"
if [ -z "\$ELECTRON_BIN" ]; then
  ELECTRON_BIN=$electron_default_quoted
fi
if [ -n "\${CODEX_CLI_PATH:-}" ]; then
  export CODEX_CLI_PATH
else
  echo "No Codex CLI default was discovered; set CODEX_CLI_PATH to an executable codex CLI." >&2
  exit 1
fi

"\$ELECTRON_BIN" "\$APP_DIR"
EOF
  fi

  chmod +x "$ROOT_APP_DIR/run-codex.sh"
}

OPENAI_ICON_URL="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/openai.png"
DESKTOP_ICON_NAME="codex-openai"
DESKTOP_ICON_FALLBACK="codex"

find_python_bin() {
  if [ -x /usr/bin/python ]; then
    printf '%s\n' /usr/bin/python
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  elif command -v python >/dev/null 2>&1; then
    command -v python
  else
    return 1
  fi
}

patch_codex_linux_open_targets() {
  echo
  echo "=== [3b] Linux open-target menu patch ==="

  local patcher="$INSTALLER_DIR/scripts/patch_codex_linux_open_targets.py"
  if [ ! -f "$patcher" ]; then
    echo "WARNING: Linux open-target patcher was not found at $patcher; continuing without the editor-picker fix." >&2
    return 0
  fi

  local python_bin=""
  if ! python_bin="$(find_python_bin)"; then
    echo "WARNING: could not patch Codex Linux open targets because Python was not found; continuing without the editor-picker fix." >&2
    return 0
  fi

  if ! "$python_bin" "$patcher" "$ROOT_APP_DIR/app_asar"; then
    echo "WARNING: could not patch Codex Linux open targets; continuing without the editor-picker fix." >&2
    return 0
  fi
}

seed_opaque_chrome_defaults() {
  echo
  echo "=== [8] Codex Linux rendering defaults ==="

  local python_bin=""
  python_bin="$(find_python_bin || true)"

  if [ -z "$python_bin" ]; then
    echo "WARNING: could not seed Codex opaque sidebar defaults because Python was not found." >&2
    return 0
  fi

  local state_file="$HOME/.codex/.codex-global-state.json"
  if ! "$python_bin" - "$state_file" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)

if path.exists():
    raw = path.read_text(encoding="utf-8")
    if raw.strip():
        try:
            data = json.loads(raw)
        except Exception as exc:
            print(f"WARNING: could not parse {path}; leaving Codex appearance defaults unchanged: {exc}", file=sys.stderr)
            raise SystemExit(0)
        if not isinstance(data, dict):
            print(f"WARNING: {path} is not a JSON object; leaving Codex appearance defaults unchanged.", file=sys.stderr)
            raise SystemExit(0)
    else:
        data = {}
else:
    data = {}

changed = False
preserved_explicit = False
for key in ("appearanceLightChromeTheme", "appearanceDarkChromeTheme"):
    value = data.get(key)
    if isinstance(value, dict):
        theme = dict(value)
        if isinstance(theme.get("opaqueWindows"), bool):
            preserved_explicit = True
            continue
    else:
        theme = {}
    theme["opaqueWindows"] = True
    data[key] = theme
    changed = True

if preserved_explicit:
    print("Preserved explicit Codex sidebar translucency settings.")

if not changed:
    print("Codex opaque sidebar defaults already set; no changes needed.")
    raise SystemExit(0)

content = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
for target in (path, pathlib.Path(str(path) + ".bak")):
    tmp = target.with_name(f".{target.name}.tmp-{os.getpid()}")
    tmp.write_text(content, encoding="utf-8")
    os.replace(tmp, target)

print(f"Seeded Codex opaque sidebar defaults at: {path}")
PY
  then
    echo "WARNING: could not seed Codex opaque sidebar defaults; continuing." >&2
  fi
}

install_desktop_entry() {
  if [ "$NO_DESKTOP_ENTRY" -eq 1 ]; then
    echo
    echo "--no-desktop-entry was set; skipping desktop entry and icon setup."
    return 0
  fi

  echo
  echo "=== [7] User desktop entry and icon ==="

  local applications_dir="$HOME/.local/share/applications"
  local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
  local desktop_file="$applications_dir/codex.desktop"
  local icon_file="$icon_dir/$DESKTOP_ICON_NAME.png"
  local desktop_icon="$DESKTOP_ICON_NAME"
  local desktop_exec
  local tmp_icon

  mkdir -p "$applications_dir" "$icon_dir"

  tmp_icon="$(mktemp "$icon_file.tmp.XXXXXX")"
  if curl --fail --location --show-error -o "$tmp_icon" "$OPENAI_ICON_URL"; then
    mv -f "$tmp_icon" "$icon_file"
    echo "Downloaded OpenAI desktop icon to: $icon_file"
  else
    rm -f "$tmp_icon"
    desktop_icon="$DESKTOP_ICON_FALLBACK"
    echo "WARNING: could not download the OpenAI desktop icon from $OPENAI_ICON_URL; continuing without it." >&2
    echo "Desktop entry will use fallback icon name: $desktop_icon" >&2
  fi

  desktop_exec="$(desktop_exec_quote "$ROOT_APP_DIR/run-codex.sh")"

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Codex
Comment=Codex desktop app port
Exec=$desktop_exec
Icon=$desktop_icon
Terminal=false
Categories=Development;
EOF

  chmod 644 "$desktop_file"
  echo "Desktop entry was created at: $desktop_file"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir" || echo "WARNING: update-desktop-database failed; desktop entry was still created." >&2
  else
    echo "update-desktop-database was not found; skipping standard desktop database refresh."
  fi

  if [ "$OMARCHY_STATUS" = "present" ]; then
    echo "If Codex does not appear in Walker immediately, reopen Walker or restart it from your session; this installer did not run broad Omarchy application refresh commands."
  fi
}

plan_dependencies() {
  RUNTIME_INSTALL_PACKAGES=()
  BUILD_INSTALL_PACKAGES=()
  INSTALL_PACKAGES=()
  FATAL_DEPENDENCY_MESSAGES=()

  has_cmd curl || add_runtime_install_package curl
  has_cmd 7z || add_runtime_install_package 7zip
  has_cmd electron || add_runtime_install_package electron

  # Native module installation/rebuild still requires Arch system build packages.
  # Keep runtime capabilities command-first, but ensure these packages through the
  # selected package backend (`--needed` makes already-installed packages safe).
  add_build_install_package python
  add_build_install_package base-devel
  add_build_install_package git

  if ! has_cmd node; then
    if [ "$OMARCHY_STATUS" = "present" ]; then
      add_fatal_dependency_message "Missing node on Omarchy. Set up or repair the Omarchy/mise Node development environment, then rerun this installer. The installer will not force-install Arch nodejs over an Omarchy-managed JavaScript toolchain."
    else
      add_runtime_install_package nodejs
    fi
  fi

  if ! has_cmd pnpm; then
    if [ "$OMARCHY_STATUS" = "present" ]; then
      add_fatal_dependency_message "Missing pnpm on Omarchy. Set up or repair the Omarchy/mise Node development environment so pnpm is available on PATH. If you intentionally want the Arch pnpm package instead, opt in manually with: sudo pacman -S pnpm"
    else
      add_runtime_install_package pnpm
    fi
  fi

  refresh_install_packages
}

select_dependency_install_command() {
  if [ "${#INSTALL_PACKAGES[@]}" -eq 0 ]; then
    return 0
  fi

  if [ "$OMARCHY_STATUS" = "present" ] && has_cmd omarchy-pkg-add; then
    echo "omarchy-pkg-add $(join_words "${INSTALL_PACKAGES[@]}")"
  else
    echo "sudo pacman -S --needed $(join_words "${INSTALL_PACKAGES[@]}")"
  fi
}

print_dependency_plan() {
  echo
  echo "Dependency plan:"

  if [ "${#RUNTIME_INSTALL_PACKAGES[@]}" -eq 0 ] && [ "${#BUILD_INSTALL_PACKAGES[@]}" -eq 0 ] && [ "${#FATAL_DEPENDENCY_MESSAGES[@]}" -eq 0 ]; then
    echo "Dependency plan: all command-first dependencies are already satisfied."
    return 0
  fi

  if [ "${#RUNTIME_INSTALL_PACKAGES[@]}" -gt 0 ]; then
    echo "  Missing runtime dependencies: $(join_words "${RUNTIME_INSTALL_PACKAGES[@]}")"
  fi

  if [ "${#BUILD_INSTALL_PACKAGES[@]}" -gt 0 ]; then
    echo "  Required system/build packages: $(join_words "${BUILD_INSTALL_PACKAGES[@]}")"
  fi

  if [ "${#INSTALL_PACKAGES[@]}" -gt 0 ] && [ "${#FATAL_DEPENDENCY_MESSAGES[@]}" -eq 0 ]; then
    echo "  Planned package install command: $(select_dependency_install_command)"
  fi

  if [ "${#FATAL_DEPENDENCY_MESSAGES[@]}" -gt 0 ]; then
    echo "  Dependencies requiring manual setup:"
    local message
    for message in "${FATAL_DEPENDENCY_MESSAGES[@]}"; do
      echo "  - $message"
    done
  fi
}

handle_dependency_plan() {
  plan_dependencies
  print_dependency_plan

  if [ "${#FATAL_DEPENDENCY_MESSAGES[@]}" -gt 0 ]; then
    echo
    echo "Resolve the missing dependencies above, then rerun this installer." >&2
    exit 1
  fi

  if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
    return 0
  fi

  if [ "${#INSTALL_PACKAGES[@]}" -eq 0 ]; then
    return 0
  fi

  if [ "$NO_INSTALL_DEPS" -eq 1 ]; then
    echo
    [ "${#RUNTIME_INSTALL_PACKAGES[@]}" -eq 0 ] || echo "Missing runtime dependencies: $(join_words "${RUNTIME_INSTALL_PACKAGES[@]}")" >&2
    [ "${#BUILD_INSTALL_PACKAGES[@]}" -eq 0 ] || echo "Required system/build packages: $(join_words "${BUILD_INSTALL_PACKAGES[@]}")" >&2
    echo "Packages not installed: $(join_words "${INSTALL_PACKAGES[@]}")" >&2
    echo "--no-install-deps was set; exiting before privileged package installation." >&2
    exit 1
  fi

  if [ "$OMARCHY_STATUS" = "present" ] && has_cmd omarchy-pkg-add; then
    echo
    echo "Installing dependencies through Omarchy package helper: omarchy-pkg-add $(join_words "${INSTALL_PACKAGES[@]}")"
    omarchy-pkg-add "${INSTALL_PACKAGES[@]}"
    hash -r
  else
    if ! has_cmd pacman; then
      echo "pacman was not found. Install the missing packages manually: $(join_words "${INSTALL_PACKAGES[@]}")" >&2
      exit 1
    fi
    echo
    echo "Installing dependencies with pacman: sudo pacman -S --needed $(join_words "${INSTALL_PACKAGES[@]}")"
    sudo pacman -S --needed "${INSTALL_PACKAGES[@]}"
    hash -r
  fi
}

# Resolve a relative explicit CLI override before the installer changes
# directories for download/extraction/build steps.
if [ -n "${CODEX_CLI_PATH:-}" ]; then
  CODEX_CLI_PATH="$(absolute_executable_path "$CODEX_CLI_PATH" 2>/dev/null || printf '%s\n' "$CODEX_CLI_PATH")"
  export CODEX_CLI_PATH
fi

ELECTRON_BIN_INTERNAL=""

echo "=== [0] Quick system check (no machine-specific hardcoded paths) ==="

ARCH="$(uname -m 2>/dev/null || echo unknown)"
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
OS_NAME="unknown"
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_NAME="${NAME:-${ID:-unknown}}"
fi

OMARCHY_STATUS="absent"
OMARCHY_VERSION="unavailable"
if command -v omarchy >/dev/null 2>&1; then
  OMARCHY_STATUS="present"
  OMARCHY_VERSION="$(omarchy --version 2>/dev/null || omarchy version 2>/dev/null || echo unavailable)"
elif command -v omarchy-version >/dev/null 2>&1; then
  OMARCHY_STATUS="present"
  OMARCHY_VERSION="$(omarchy-version 2>/dev/null || echo unavailable)"
fi
OMARCHY_VERSION="${OMARCHY_VERSION%%$'\n'*}"
[ -n "$OMARCHY_VERSION" ] || OMARCHY_VERSION="unavailable"

echo "OS        : $OS_NAME"
echo "Kernel    : $KERNEL"
echo "Arch      : $ARCH"
echo "HOME      : $HOME"
echo "Omarchy   : $OMARCHY_STATUS"
echo "Omarchy version: $OMARCHY_VERSION"

echo
echo "Command check:"
for cmd in pacman curl 7z node pnpm electron; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd: OK ($(command -v "$cmd"))"
  else
    echo "  - $cmd: missing"
  fi
done
if command -v npm >/dev/null 2>&1; then
  echo "  - npm: diagnostic only ($(command -v npm))"
else
  echo "  - npm: diagnostic only (missing)"
fi
echo "npm is diagnostic-only and is not required by preflight planning."

if [ "$ARCH" != "x86_64" ]; then
  echo
  echo "WARNING: architecture is not x86_64 (detected: $ARCH)."
  echo "Native modules such as better-sqlite3 and node-pty may not build correctly."
fi

handle_dependency_plan

if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
  echo
  echo "Preflight-only mode: reporting complete."
  echo "Skipping download, package installation, extraction, rebuild, launcher generation, Codex appearance defaults, and desktop integration."
  exit 0
fi

echo

echo "=== [1] Download Codex.dmg to ~/Downloads/codex-macos ==="
mkdir -p "$HOME/Downloads/codex-macos"
cd "$HOME/Downloads/codex-macos"

download_codex_dmg() {
  local tmp_dmg
  tmp_dmg="$(mktemp Codex.dmg.tmp.XXXXXX)"

  if curl --fail --location --show-error -o "$tmp_dmg" "https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"; then
    mv -f "$tmp_dmg" Codex.dmg
  else
    local curl_status=$?
    rm -f "$tmp_dmg"
    echo "Failed to download Codex.dmg; cached copy was left unchanged." >&2
    return "$curl_status"
  fi
}

if [ "$FORCE_DOWNLOAD" -eq 1 ]; then
  echo "Force-download requested; downloading replacement before updating cached Codex.dmg."
  download_codex_dmg
elif [ ! -f Codex.dmg ]; then
  echo "Downloading Codex.dmg..."
  download_codex_dmg
else
  echo "Codex.dmg already exists, reusing cached download."
fi

echo
echo "=== [2] Dependency versions ==="

if ! command -v node >/dev/null 2>&1; then
  echo "node is still missing after dependency handling." >&2
  exit 1
fi
if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm is still missing after dependency handling." >&2
  exit 1
fi
if ! command -v electron >/dev/null 2>&1; then
  echo "electron is still missing after dependency handling." >&2
  exit 1
fi
if ! command -v 7z >/dev/null 2>&1; then
  echo "7z is still missing after dependency handling. On Arch, install package: 7zip" >&2
  exit 1
fi

node -v || true
if command -v npm >/dev/null 2>&1; then
  npm -v || true
else
  echo "npm: diagnostic only (missing)"
fi
ELECTRON_BIN_INTERNAL="$(absolute_executable_path "$(command -v electron)")"
"$ELECTRON_BIN_INTERNAL" --version || true
pnpm -v

# Absolute path to the pnpm binary
PNPM_BIN="$(command -v pnpm)"

# Set PNPM_HOME so global binaries have a predictable location
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
mkdir -p "$PNPM_HOME"

echo
echo "Checking asar through pnpm dlx (without global installation)..."
"$PNPM_BIN" dlx asar --version || true

echo
echo "=== [3] Extract DMG and app.asar into ~/apps/codex-port ==="

ROOT_APP_DIR="$HOME/apps/codex-port"
mkdir -p "$ROOT_APP_DIR"
cd "$ROOT_APP_DIR"

# Reruns should preserve the cached DMG but remove stale extraction output from
# previous partial or failed runs before discovering app.asar again.
echo "Cleaning extracted app and native-build working directories before re-extraction..."
rm -rf "$ROOT_APP_DIR/dmg_extracted" "$ROOT_APP_DIR/app_asar" "$ROOT_APP_DIR/_better-sqlite3-build" "$ROOT_APP_DIR/_native-build"

echo "Extracting Codex.dmg with 7z (auto overwrite - yes to all)..."
7z x -y -aoa "$HOME/Downloads/codex-macos/Codex.dmg" -o./dmg_extracted

echo
echo "Looking for app.asar inside dmg_extracted..."
APP_ASAR_PATH=$(find ./dmg_extracted -name "app.asar" -print | head -n 1 || true)

if [ -z "${APP_ASAR_PATH:-}" ]; then
  echo "Could not find app.asar inside ./dmg_extracted." >&2
  exit 1
fi

echo "Found app.asar: $APP_ASAR_PATH"

mkdir -p "$ROOT_APP_DIR/app_asar"
echo "Extracting app.asar into the app_asar directory (through pnpm dlx asar)..."
"$PNPM_BIN" dlx asar extract "$APP_ASAR_PATH" "$ROOT_APP_DIR/app_asar"

patch_codex_linux_open_targets

echo
echo "=== [4] Rebuild native modules (better-sqlite3, node-pty) through pnpm ==="

if [ -x /usr/bin/python ]; then
  export PYTHON=/usr/bin/python
  export npm_config_python=/usr/bin/python
  echo "Using system Python for native rebuilds: /usr/bin/python"
fi

cd "$ROOT_APP_DIR/app_asar"

echo
echo "Reading Electron version..."
ELECTRON_VERSION=$("$ELECTRON_BIN_INTERNAL" --version | tr -d 'v' || true)

if [ -z "${ELECTRON_VERSION:-}" ]; then
  echo "Could not read the Electron version. Check that electron is installed correctly." >&2
  exit 1
fi

echo "Electron version: $ELECTRON_VERSION"

echo
echo "Creating an isolated project to build native modules for Electron (to avoid workspace issues and partial packages from the DMG)..."
TMP_BUILD_DIR="$ROOT_APP_DIR/_native-build"
rm -rf "$TMP_BUILD_DIR"
mkdir -p "$TMP_BUILD_DIR"

echo "Reading the better-sqlite3 version from the Codex app..."
BSQL_VERSION=$(node -p "require('$ROOT_APP_DIR/app_asar/node_modules/better-sqlite3/package.json').version" 2>/dev/null || echo "12.5.0")
echo "better-sqlite3 version: $BSQL_VERSION"

echo "Reading the node-pty version from the Codex app..."
NODE_PTY_VERSION=$(node -p "require('$ROOT_APP_DIR/app_asar/node_modules/node-pty/package.json').version" 2>/dev/null || echo "1.1.0")
echo "node-pty version: $NODE_PTY_VERSION"

cd "$TMP_BUILD_DIR"
echo "Creating a minimal package.json for the temporary project..."
cat > package.json <<EOF
{
  "name": "codex-native-electron-build",
  "version": "1.0.0",
  "private": true
}
EOF

pnpm add "better-sqlite3@$BSQL_VERSION" "node-pty@$NODE_PTY_VERSION"

echo
echo "Rebuilding native modules in the isolated project for Electron $ELECTRON_VERSION..."
ELECTRON_REBUILD_CMD=("$PNPM_BIN" dlx electron-rebuild -v "$ELECTRON_VERSION" -f -w better-sqlite3 -w node-pty)
echo "Command: ${ELECTRON_REBUILD_CMD[*]}"
set +e
"${ELECTRON_REBUILD_CMD[@]}"
REB_RES=$?
set -e

if [ "$REB_RES" -ne 0 ]; then
  if [ "$ALLOW_REBUILD_FAILURE" -eq 1 ]; then
    echo "WARNING: electron-rebuild failed for native modules: better-sqlite3, node-pty (exit code $REB_RES)."
    echo "--allow-rebuild-failure was set; continuing despite the native rebuild failure."
  else
    echo "electron-rebuild failed for native modules: better-sqlite3, node-pty (exit code $REB_RES)." >&2
    echo "Use --allow-rebuild-failure to continue anyway for experiments." >&2
    exit "$REB_RES"
  fi
fi

copy_rebuilt_native_module() {
  local module_name="$1"

  echo
  echo "Copying the rebuilt $module_name module into Codex app_asar..."
  if [ -d "$TMP_BUILD_DIR/node_modules/$module_name" ]; then
    rm -rf "$ROOT_APP_DIR/app_asar/node_modules/$module_name"
    cp -aL "$TMP_BUILD_DIR/node_modules/$module_name" "$ROOT_APP_DIR/app_asar/node_modules/$module_name"
    echo "$module_name was copied into app_asar/node_modules."
  else
    echo "WARNING: node_modules/$module_name was not found in the isolated project; skipping copy."
  fi
}

copy_rebuilt_native_module better-sqlite3
copy_rebuilt_native_module node-pty

ensure_codex_cli

ELECTRON_DEFAULT="$ELECTRON_BIN_INTERNAL"
if [ -z "$ELECTRON_DEFAULT" ] || [ ! -x "$ELECTRON_DEFAULT" ]; then
  echo "Could not resolve an executable Electron binary after dependency handling." >&2
  exit 1
fi

echo
echo "=== [6] run-codex.sh launcher for Codex ==="
write_launcher "$ELECTRON_DEFAULT" "$CODEX_CLI_DEFAULT"

echo
if [ -n "$CODEX_CLI_DEFAULT" ]; then
  echo "run-codex.sh was created at: $ROOT_APP_DIR/run-codex.sh"
  echo "Default Electron binary: $ELECTRON_DEFAULT"
  echo "Default Codex CLI: $CODEX_CLI_DEFAULT"
else
  echo "run-codex.sh was created at: $ROOT_APP_DIR/run-codex.sh"
  echo "Default Electron binary: $ELECTRON_DEFAULT"
  echo "Default Codex CLI: none (--skip-cli-install was set and no working CLI was discovered)"
  echo "Set CODEX_CLI_PATH=/path/to/codex when launching if the desktop app needs a custom CLI."
fi

install_desktop_entry
seed_opaque_chrome_defaults

echo
echo "=== Done. The Codex port installer has finished. ==="
