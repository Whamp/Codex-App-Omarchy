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

setup_common_fakes() {
  local fakebin="$1"
  make_fake "$fakebin" sudo 'echo "sudo $*" >>"$FAKE_LOG"; "$@"'
  make_fake "$fakebin" pacman 'echo "pacman $*" >>"$FAKE_LOG"'
  make_fake "$fakebin" curl '
echo "curl $*" >>"$FAKE_LOG"
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then shift; out="$1"; fi
  shift || true
done
[ -n "$out" ] || exit 1
printf "fake-dmg\n" > "$out"
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
if [ "${1:-}" = "--version" ]; then
  echo "v37.0.0"
else
  echo "electron $* CODEX_CLI_PATH=${CODEX_CLI_PATH:-} CODEX_BROWSER_USE_NODE_PATH=${CODEX_BROWSER_USE_NODE_PATH:-} CODEX_NODE_REPL_PATH=${CODEX_NODE_REPL_PATH:-}" >>"$FAKE_LOG"
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
  printf "{\"version\":\"12.5.0\"}\n" > "$dest/node_modules/better-sqlite3/package.json"
elif [ "${1:-}" = "add" ]; then
  mkdir -p node_modules/better-sqlite3
  printf "rebuilt\n" > node_modules/better-sqlite3/native.node
elif [ "${1:-}" = "dlx" ] && [ "${2:-}" = "electron-rebuild" ]; then
  :
elif [ "${1:-}" = "setup" ]; then
  :
elif [ "${1:-}" = "i" ] && [ "${2:-}" = "-g" ]; then
  if [ "${FAKE_PNPM_INSTALL_FAIL:-0}" = "1" ]; then echo "simulated codex install failure" >&2; exit 55; fi
  if [ "${FAKE_PNPM_REQUIRE_HOME_ON_PATH:-0}" = "1" ]; then
    case ":$PATH:" in
      *":${PNPM_HOME:?}:"*) : ;;
      *) echo "PNPM_HOME was not on PATH during global install" >&2; exit 56 ;;
    esac
  fi
  mkdir -p "${PNPM_HOME:?}"
  cat > "$PNPM_HOME/codex" <<EOF_CODEX
#!/usr/bin/env bash
echo installed-codex "\$@"
EOF_CODEX
  chmod +x "$PNPM_HOME/codex"
fi
'
  make_fake "$fakebin" npm 'echo "10.0.0"'
  make_fake "$fakebin" which 'command -v "$1" || true'
}

run_installer() {
  local fakebin="$1"
  local home="$2"
  local log="$3"
  shift 3
  PATH="$fakebin:/usr/bin:/bin" HOME="$home" FAKE_LOG="$log" /bin/bash "$installer" "$@" >>"$log" 2>&1
}

bash -n "$installer"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Executable CODEX_CLI_PATH wins over codex on PATH and prevents installation.
explicit_bin="$tmp/explicit/bin"
explicit_home="$tmp/explicit/home"
explicit_log="$tmp/explicit.log"
mkdir -p "$explicit_bin" "$explicit_home" "$tmp/custom"
setup_common_fakes "$explicit_bin"
make_fake "$explicit_bin" codex 'echo path-codex'
make_fake "$tmp/custom" codex-custom 'echo explicit-codex'
CODEX_CLI_PATH="$tmp/custom/codex-custom" run_installer "$explicit_bin" "$explicit_home" "$explicit_log" || fail "explicit CLI path install run failed"
assert_file_contains "$explicit_log" "Using Codex CLI from CODEX_CLI_PATH: $tmp/custom/codex-custom"
assert_file_not_contains "$explicit_log" "pnpm i -g @openai/codex"
assert_file_contains "$explicit_home/apps/codex-port/run-codex.sh" "ELECTRON_BIN=$explicit_bin/electron"
assert_file_contains "$explicit_home/apps/codex-port/run-codex.sh" "CODEX_CLI_PATH=$tmp/custom/codex-custom"
assert_file_contains "$explicit_home/apps/codex-port/run-codex.sh" '"$ELECTRON_BIN" "$APP_DIR"'

# Existing codex on PATH satisfies the CLI requirement and avoids reinstall/update.
path_bin="$tmp/path/bin"
path_home="$tmp/path/home"
path_log="$tmp/path.log"
mkdir -p "$path_bin" "$path_home"
setup_common_fakes "$path_bin"
make_fake "$path_bin" codex 'echo path-codex'
run_installer "$path_bin" "$path_home" "$path_log" || fail "PATH CLI run failed"
assert_file_contains "$path_log" "Using Codex CLI from PATH: $path_bin/codex"
assert_file_not_contains "$path_log" "pnpm i -g @openai/codex"
assert_file_contains "$path_home/apps/codex-port/run-codex.sh" "CODEX_CLI_PATH=$path_bin/codex"

# Relative CODEX_CLI_PATH is accepted but normalized to an absolute launcher default.
relative_cli_root="$tmp/relative-cli"
relative_cli_bin="$relative_cli_root/bin"
relative_cli_home="$tmp/relative-cli-home"
relative_cli_log="$tmp/relative-cli.log"
mkdir -p "$relative_cli_bin" "$relative_cli_home"
setup_common_fakes "$relative_cli_bin"
make_fake "$relative_cli_bin" codex-custom 'echo relative-explicit-codex'
(
  cd "$relative_cli_root"
  CODEX_CLI_PATH="bin/codex-custom" run_installer "$relative_cli_bin" "$relative_cli_home" "$relative_cli_log"
) || fail "relative CODEX_CLI_PATH install run failed"
assert_file_contains "$relative_cli_log" "Using Codex CLI from CODEX_CLI_PATH: $relative_cli_bin/codex-custom"
assert_file_contains "$relative_cli_home/apps/codex-port/run-codex.sh" "CODEX_CLI_PATH=$relative_cli_bin/codex-custom"
assert_file_not_contains "$relative_cli_home/apps/codex-port/run-codex.sh" "CODEX_CLI_PATH=bin/codex-custom"

# Missing CLI installs through pnpm by default and generated launcher uses installed absolute path.
install_bin="$tmp/install/bin"
install_home="$tmp/install/home"
install_log="$tmp/install.log"
mkdir -p "$install_bin" "$install_home"
setup_common_fakes "$install_bin"
make_fake "$install_bin" codex 'exit 42'
FAKE_PNPM_REQUIRE_HOME_ON_PATH=1 run_installer "$install_bin" "$install_home" "$install_log" || fail "install fallback run failed"
assert_file_contains "$install_log" "No working Codex CLI found; installing @openai/codex with pnpm."
assert_file_contains "$install_log" "pnpm i -g @openai/codex"
assert_file_contains "$install_log" "Using Codex CLI after pnpm install: $install_home/.local/share/pnpm/codex"
assert_file_contains "$install_home/apps/codex-port/run-codex.sh" "CODEX_CLI_PATH=$install_home/.local/share/pnpm/codex"

# A Linux Codex primary runtime enables the browser-use Node REPL MCP server from the launcher.
runtime_bin="$tmp/runtime/bin"
runtime_home="$tmp/runtime/home"
runtime_log="$tmp/runtime.log"
runtime_node_repl="$runtime_home/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/node_repl"
mkdir -p "$runtime_bin" "$runtime_home" "$(dirname "$runtime_node_repl")"
setup_common_fakes "$runtime_bin"
make_fake "$runtime_bin" codex 'echo path-codex'
make_fake "$(dirname "$runtime_node_repl")" node_repl 'echo linux-node-repl'
run_installer "$runtime_bin" "$runtime_home" "$runtime_log" || fail "runtime path launcher run failed"
assert_file_contains "$runtime_log" "Using browser-use Node from PATH: $runtime_bin/node"
assert_file_contains "$runtime_log" "Using browser-use node_repl from Codex primary runtime: $runtime_node_repl"
assert_file_contains "$runtime_home/apps/codex-port/run-codex.sh" "CODEX_BROWSER_USE_NODE_PATH=$runtime_bin/node"
assert_file_contains "$runtime_home/apps/codex-port/run-codex.sh" "CODEX_NODE_REPL_PATH=$runtime_node_repl"
runtime_run_log="$tmp/runtime-run.log"
FAKE_LOG="$runtime_run_log" PATH="$runtime_bin:/usr/bin:/bin" "$runtime_home/apps/codex-port/run-codex.sh" || fail "runtime launcher run failed"
assert_file_contains "$runtime_run_log" "CODEX_BROWSER_USE_NODE_PATH=$runtime_bin/node"
assert_file_contains "$runtime_run_log" "CODEX_NODE_REPL_PATH=$runtime_node_repl"

# CLI installation failure is fatal by default and stops before launcher generation.
fail_bin="$tmp/fail/bin"
fail_home="$tmp/fail/home"
fail_log="$tmp/fail.log"
mkdir -p "$fail_bin" "$fail_home"
setup_common_fakes "$fail_bin"
make_fake "$fail_bin" codex 'exit 42'
if FAKE_PNPM_INSTALL_FAIL=1 run_installer "$fail_bin" "$fail_home" "$fail_log"; then
  fail "CLI install failure should be fatal"
fi
assert_file_contains "$fail_log" "Codex CLI installation failed"
[ ! -e "$fail_home/apps/codex-port/run-codex.sh" ] || fail "fatal CLI install failure should stop before launcher generation"

# --skip-cli-install does not invoke pnpm global install and makes missing default explicit in launcher.
skip_bin="$tmp/skip/bin"
skip_home="$tmp/skip/home"
skip_log="$tmp/skip.log"
mkdir -p "$skip_bin" "$skip_home"
setup_common_fakes "$skip_bin"
make_fake "$skip_bin" codex 'exit 42'
run_installer "$skip_bin" "$skip_home" "$skip_log" --skip-cli-install || fail "skip CLI install run failed"
assert_file_contains "$skip_log" "--skip-cli-install was set; not installing Codex CLI."
assert_file_not_contains "$skip_log" "pnpm i -g @openai/codex"
assert_file_contains "$skip_home/apps/codex-port/run-codex.sh" 'No Codex CLI default was discovered; set CODEX_CLI_PATH to an executable codex CLI.'
assert_file_contains "$skip_home/apps/codex-port/run-codex.sh" 'if [ -n "${CODEX_CLI_PATH:-}" ]; then'
skip_run_log="$tmp/skip-run.log"
: > "$skip_run_log"
FAKE_LOG="$skip_run_log" PATH="$skip_bin:/usr/bin:/bin" "$skip_home/apps/codex-port/run-codex.sh" >"$tmp/skip-run.out" 2>"$tmp/skip-run.err" && fail "launcher without a CLI default should fail fast"
assert_file_contains "$tmp/skip-run.err" 'No Codex CLI default was discovered; set CODEX_CLI_PATH to an executable codex CLI.'
assert_file_not_contains "$skip_run_log" 'electron '

# Shell-significant characters in discovered defaults are quoted safely in the launcher.
tricky_bin="$tmp/tricky path/with dollars/bin"
tricky_home="$tmp/tricky/home"
tricky_log="$tmp/tricky.log"
tricky_cli_dir="$tmp/tricky cli/with $/bin"
tricky_cli="$tricky_cli_dir/codex custom"
mkdir -p "$tricky_bin" "$tricky_home" "$tricky_cli_dir"
setup_common_fakes "$tricky_bin"
make_fake "$tricky_cli_dir" "codex custom" 'echo tricky-codex'
CODEX_CLI_PATH="$tricky_cli" run_installer "$tricky_bin" "$tricky_home" "$tricky_log" || fail "tricky default path install run failed"
tricky_run_log="$tmp/tricky-run.log"
FAKE_LOG="$tricky_run_log" PATH="$tricky_bin:/usr/bin:/bin" "$tricky_home/apps/codex-port/run-codex.sh" || fail "tricky launcher run failed"
assert_file_contains "$tricky_run_log" "CODEX_CLI_PATH=$tricky_cli"

echo "CLI discovery and launcher verification passed."
