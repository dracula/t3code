#!/usr/bin/env bash
set -euo pipefail

THEME_URL='https://raw.githubusercontent.com/dracula/t3code/main/Dracula.json'
temporary_dir=''
cli=()
cli_help=''

usage() {
  cat <<'EOF'
Usage: bash install.sh [--base-dir PATH] [--help]

Import and select Dracula for the local T3 Code desktop/server environment.
The base directory defaults to T3CODE_HOME, then ~/.t3.
Uses an existing T3 CLI, or npx --yes t3@latest when one is unavailable.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit "${2:-1}"
}

cleanup() {
  if [[ -n "$temporary_dir" ]]; then
    rm -rf -- "$temporary_dir"
  fi
}

# Older commands can print top-level help without supporting theme installation.
supports_theme_install() {
  if ! cli_help=$("$@" theme set --help 2>&1); then
    return 1
  fi
  [[ "$cli_help" == *'--id'* && "$cli_help" == *'--base-dir'* ]]
}

find_cli() {
  local base_dir="$1" candidate
  local candidates=()
  if [[ -n "${T3CODE_CLI_PATH:-}" ]]; then
    candidates+=("$T3CODE_CLI_PATH")
  fi
  candidates+=("$base_dir/bin/t3")
  candidate=$(command -v t3 || true)
  if [[ -n "$candidate" ]]; then
    candidates+=("$candidate")
  fi
  candidates+=("$HOME/.local/bin/t3")

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]] && supports_theme_install "$candidate"; then
      cli=("$candidate")
      printf 'Using T3 CLI: %s\n' "$candidate"
      return
    fi
  done

  case "$(uname -s):$(uname -m)" in
    Darwin:arm64|Linux:x86_64|Linux:aarch64|Linux:arm64) ;;
    Darwin:x86_64)
      fail 'The npx T3 CLI has no Intel Mac build. Install a compatible T3 CLI and set T3CODE_CLI_PATH to its executable.'
      ;;
    *) fail 'The npx T3 CLI supports Apple Silicon macOS and x64/ARM64 Linux.' ;;
  esac
  command -v node >/dev/null 2>&1 || fail 'Node.js is required for the npx fallback. Install Node.js with npm, then run this installer again.'
  command -v npx >/dev/null 2>&1 || fail 'npx is required for the fallback. Install npm, then run this installer again.'
  cli=(npx --yes t3@latest)
  printf 'Using the official T3 CLI through npx.\n'
  if ! supports_theme_install "${cli[@]}"; then
    printf '%s\n' "$cli_help" >&2
    fail 'The npx T3 CLI could not provide theme installation. Check the npm output and network connection, then retry.'
  fi
}

find_theme() {
  local source_path="${BASH_SOURCE[0]:-}" script_dir=''
  if [[ -n "$source_path" && -f "$source_path" ]]; then
    script_dir=$(cd -- "$(dirname -- "$source_path")" && pwd -P)
    if [[ -f "$script_dir/Dracula.json" ]]; then
      theme_file="$script_dir/Dracula.json"
      return
    fi
  fi

  command -v curl >/dev/null 2>&1 || fail 'curl is required to download Dracula.json.'
  temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/dracula-t3code.XXXXXX")
  theme_file="$temporary_dir/Dracula.json"
  printf 'Downloading Dracula.json...\n'
  local download_status
  if curl --fail --silent --show-error --location --proto '=https' \
    --connect-timeout 10 --max-time 60 --output "$theme_file" "$THEME_URL"; then
    [[ -s "$theme_file" ]] || fail 'The downloaded theme is empty.'
  else
    download_status=$?
    fail 'Could not download Dracula.json. No theme was installed.' "$download_status"
  fi
}

main() {
  local base_dir="${T3CODE_HOME:-}" theme_file='' install_status
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; return ;;
      --base-dir)
        [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || fail '--base-dir requires a path.'
        base_dir="$2"
        shift 2
        ;;
      *) fail "Unknown argument: $1. Run with --help for usage." ;;
    esac
  done

  [[ -n "${HOME:-}" ]] || fail 'HOME must be set to locate the T3 environment.'
  if [[ -z "$base_dir" ]]; then
    base_dir="$HOME/.t3"
  fi

  case "$(uname -s)" in
    Darwin|Linux) ;;
    *) fail 'This installer supports macOS and Linux. For Windows desktop, use the manual theme import.' ;;
  esac

  # Keep CLI discovery and publication on the same directory, including ~/ paths.
  case "$base_dir" in
    \~) base_dir="$HOME" ;;
    \~/*) base_dir="$HOME/${base_dir:2}" ;;
  esac
  if [[ "$base_dir" != /* ]]; then
    base_dir="$PWD/$base_dir"
  fi
  printf 'T3 environment: %s\n' "$base_dir"
  if [[ -d "$base_dir/userdata" || -x "$base_dir/bin/t3" ]] || command -v t3 >/dev/null 2>&1; then
    printf 'Found an existing T3 installation or environment.\n'
  else
    printf 'No existing T3 environment found; preparing Dracula for the first launch.\n'
  fi

  find_cli "$base_dir"
  find_theme
  if "${cli[@]}" theme set "$theme_file" --id dracula-t3code --base-dir "$base_dir"; then
    printf 'Dracula is configured for this T3 environment. Connected clients will apply it; offline clients will apply it when they reconnect.\n'
  else
    install_status=$?
    fail 'T3 could not install Dracula. See the CLI output above.' "$install_status"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
main "$@"
