#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: curl -fsSL https://raw.githubusercontent.com/Whamp/Codex-App-Omarchy/main/bootstrap.sh | sudo bash -s -- [installer options]

Download this repository to a temporary directory and run the Omarchy Codex installer.

Environment overrides:
  CODEX_OMARCHY_REF          Git ref to download. Default: main
  CODEX_OMARCHY_ARCHIVE_URL  Full tar.gz archive URL to download.
  CODEX_OMARCHY_KEEP_BOOTSTRAP_DIR=1
                             Keep the temporary checkout for debugging.

All command-line arguments after -- are passed to install-codex-omarchy.sh.
EOF
}

case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download the Codex Omarchy installer." >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "tar is required to unpack the Codex Omarchy installer." >&2
  exit 1
fi

repo_ref="${CODEX_OMARCHY_REF:-main}"
archive_url="${CODEX_OMARCHY_ARCHIVE_URL:-https://github.com/Whamp/Codex-App-Omarchy/archive/refs/heads/${repo_ref}.tar.gz}"
bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-omarchy.XXXXXX")"

cleanup() {
  if [ "${CODEX_OMARCHY_KEEP_BOOTSTRAP_DIR:-0}" = "1" ]; then
    echo "Keeping bootstrap directory: $bootstrap_dir"
  else
    rm -rf "$bootstrap_dir"
  fi
}
trap cleanup EXIT

echo "Downloading Codex Omarchy installer from: $archive_url"
curl --fail --location --show-error "$archive_url" | tar -xz -C "$bootstrap_dir" --strip-components=1

installer="$bootstrap_dir/install-codex-omarchy.sh"
if [ ! -f "$installer" ]; then
  echo "Downloaded archive did not contain install-codex-omarchy.sh." >&2
  exit 1
fi

bash "$installer" "$@"
