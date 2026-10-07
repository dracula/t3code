#!/usr/bin/env bats
# Bats runs each test with a fresh setup; exported mocks are intentionally local.
# shellcheck disable=SC2030,SC2031

setup() {
  test_home="$BATS_TEST_TMPDIR/home"
  mock_bin="$BATS_TEST_TMPDIR/bin"
  local_repo="$BATS_TEST_TMPDIR/local repo"
  remote_script="$BATS_TEST_TMPDIR/remote/install.sh"
  export MOCK_LOG="$BATS_TEST_TMPDIR/calls"
  export MOCK_THEME="$BATS_TEST_DIRNAME/../Dracula.json"
  export MOCK_INSTALLED="$BATS_TEST_TMPDIR/installed.json"
  export TMPDIR="$BATS_TEST_TMPDIR/downloads"
  export MOCK_OS=Linux MOCK_ARCH=x86_64
  unset T3CODE_HOME T3CODE_CLI_PATH
  mkdir -p "$test_home" "$mock_bin" "$local_repo" "${remote_script%/*}" "$TMPDIR"
  cp "$BATS_TEST_DIRNAME/../install.sh" "$local_repo/install.sh"
  cp "$MOCK_THEME" "$local_repo/Dracula.json"
  cp "$BATS_TEST_DIRNAME/../install.sh" "$remote_script"
  for utility in cat cp dirname mktemp rm; do
    ln -s "$(command -v "$utility")" "$mock_bin/$utility"
  done
  cat > "$mock_bin/uname" <<'EOF'
#!/bin/bash
if [[ "$1" == -s ]]; then printf '%s\n' "$MOCK_OS"; else printf '%s\n' "$MOCK_ARCH"; fi
EOF
  cat > "$BATS_TEST_TMPDIR/mock-cli" <<'EOF'
#!/bin/bash
printf 'CLI [%s]\n' "$0" >> "$MOCK_LOG"
printf 'ARG [%s]\n' "$@" >> "$MOCK_LOG"
if [[ "${1:-}" == --yes ]]; then
  [[ "$2" == t3@latest ]] || exit 90
  shift 2
fi
if [[ "${3:-}" == --help ]]; then
  if [[ "${MOCK_HELP_MODE:-supported}" == error ]]; then
    printf 'CLI download failed\n' >&2
    exit 1
  fi
  if [[ "${MOCK_HELP_MODE:-supported}" == old || "$0" == "${MOCK_OLD_CLI:-}" ]]; then
    printf 'Usage: t3 [--help]\n'
    exit 0
  fi
  printf 'Usage: t3 theme set FILE --id ID --base-dir PATH\n'
  exit 0
fi
[[ "$1" == theme && "$2" == set ]] || exit 91
[[ "$4" == --id && "$5" == dracula-t3code && "$6" == --base-dir ]] || exit 92
[[ -f "$3" ]] || exit 93
if [[ -n "${MOCK_INSTALL_STATUS:-}" ]]; then
  printf 'Theme rejected\n' >&2
  exit "$MOCK_INSTALL_STATUS"
fi
cp "$3" "$MOCK_INSTALLED"
printf 'Installed theme\n'
EOF
  cat > "$mock_bin/curl" <<'EOF'
#!/bin/bash
printf 'DOWNLOAD\n' >> "$MOCK_LOG"
printf 'CURL [%s]\n' "$@" >> "$MOCK_LOG"
destination=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output ]]; then destination="$2"; shift 2; else shift; fi
done
[[ -n "$destination" ]] || exit 94
if [[ -n "${MOCK_CURL_STATUS:-}" ]]; then
  printf 'partial' > "$destination"
  exit "$MOCK_CURL_STATUS"
fi
if [[ "${MOCK_EMPTY_DOWNLOAD:-}" == yes ]]; then
  : > "$destination"
else
  cp "$MOCK_THEME" "$destination"
fi
EOF
  chmod +x "$mock_bin/uname" "$mock_bin/curl" "$BATS_TEST_TMPDIR/mock-cli"
}

make_cli() {
  mkdir -p "${1%/*}"
  cp "$BATS_TEST_TMPDIR/mock-cli" "$1"
  chmod +x "$1"
}

enable_npx() {
  make_cli "$mock_bin/npx"
  ln -s /bin/true "$mock_bin/node"
}

run_installer() {
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash "$local_repo/install.sh" "$@"
}

assert_clean_downloads() {
  local remaining
  remaining=$(find "$TMPDIR" -mindepth 1 -print)
  [[ -z "$remaining" ]]
}

@test "help does not require dependencies or modify an environment" {
  run env -u HOME PATH="$mock_bin" /bin/bash "$local_repo/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'Usage:'* ]]
  [ ! -e "$MOCK_LOG" ]
}

@test "rejects unknown options and a missing or empty base directory" {
  run_installer --unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *'Unknown argument'* ]]
  run_installer --base-dir
  [ "$status" -ne 0 ]
  [[ "$output" == *'requires a path'* ]]
  run_installer --base-dir ''
  [ "$status" -ne 0 ]
  [ ! -e "$MOCK_LOG" ]
}

@test "explicit CLI takes precedence and uses the sibling theme" {
  export T3CODE_CLI_PATH="$BATS_TEST_TMPDIR/explicit cli"
  make_cli "$T3CODE_CLI_PATH"
  make_cli "$test_home/.t3/bin/t3"
  make_cli "$mock_bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *'Dracula is configured'* ]]
  [[ "$(cat "$MOCK_LOG")" == *"CLI [$T3CODE_CLI_PATH]"* ]]
  [[ "$(cat "$MOCK_LOG")" != *"CLI [$mock_bin/t3]"* ]]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$local_repo/Dracula.json]"* ]]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$test_home/.t3]"* ]]
  [[ "$(cat "$MOCK_LOG")" != *DOWNLOAD* ]]
  cmp "$MOCK_THEME" "$MOCK_INSTALLED"
}

@test "bundled desktop CLI takes precedence over PATH" {
  make_cli "$test_home/.t3/bin/t3"
  make_cli "$mock_bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"CLI [$test_home/.t3/bin/t3]"* ]]
  [[ "$(cat "$MOCK_LOG")" != *"CLI [$mock_bin/t3]"* ]]
}

@test "PATH takes precedence over the local bin fallback" {
  make_cli "$mock_bin/t3"
  make_cli "$test_home/.local/bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"CLI [$mock_bin/t3]"* ]]
  [[ "$(cat "$MOCK_LOG")" != *"CLI [$test_home/.local/bin/t3]"* ]]
}

@test "finds the local bin CLI outside PATH" {
  make_cli "$test_home/.local/bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"CLI [$test_home/.local/bin/t3]"* ]]
}

@test "skips missing explicit paths and old CLIs that only print root help" {
  export T3CODE_CLI_PATH="$BATS_TEST_TMPDIR/missing"
  export MOCK_OLD_CLI="$test_home/.t3/bin/t3"
  make_cli "$MOCK_OLD_CLI"
  make_cli "$mock_bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"CLI [$mock_bin/t3]"* ]]
  [[ "$output" == *"Using T3 CLI: $mock_bin/t3"* ]]
}

@test "base-dir overrides T3CODE_HOME and preserves spaces" {
  export T3CODE_HOME="$BATS_TEST_TMPDIR/other home"
  local target="$BATS_TEST_TMPDIR/custom home"
  make_cli "$target/bin/t3"
  run_installer --base-dir "$target"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"CLI [$target/bin/t3]"* ]]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$target]"* ]]
}

@test "T3CODE_HOME is used when no flag is given" {
  export T3CODE_HOME="$BATS_TEST_TMPDIR/environment home"
  make_cli "$T3CODE_HOME/bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$T3CODE_HOME]"* ]]
}

@test "expands tilde paths and makes relative base directories absolute" {
  make_cli "$mock_bin/t3"
  # Pass the literal tilde to exercise the installer's own expansion.
  # shellcheck disable=SC2088
  run_installer --base-dir '~/custom home'
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$test_home/custom home]"* ]]
  run_installer --base-dir 'relative home'
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$PWD/relative home]"* ]]
}

@test "npx prepares a theme without an existing installation" {
  enable_npx
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *'preparing Dracula for the first launch'* ]]
  [[ "$(cat "$MOCK_LOG")" == *'ARG [--yes]'*'ARG [t3@latest]'* ]]
  [ ! -d "$test_home/.t3" ]
  cmp "$MOCK_THEME" "$MOCK_INSTALLED"
}

@test "falls back to npx for an installed CLI without theme support" {
  export MOCK_OLD_CLI="$mock_bin/t3"
  make_cli "$MOCK_OLD_CLI"
  enable_npx
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *'Using the official T3 CLI through npx'* ]]
}

@test "standalone script downloads and removes the temporary theme" {
  make_cli "$mock_bin/t3"
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash "$remote_script"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *'DOWNLOAD'* ]]
  [[ "$(cat "$MOCK_LOG")" == *'https://raw.githubusercontent.com/dracula/t3code/main/Dracula.json'* ]]
  cmp "$MOCK_THEME" "$MOCK_INSTALLED"
  assert_clean_downloads
}

@test "piped installer downloads instead of using a theme in the current directory" {
  make_cli "$mock_bin/t3"
  cd "$local_repo"
  # The child shell expands its positional argument.
  # shellcheck disable=SC2016
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash -c 'cat install.sh | /bin/bash -s -- --base-dir "$1"' installer "$test_home/pipe home"
  [ "$status" -eq 0 ]
  [[ "$(cat "$MOCK_LOG")" == *'DOWNLOAD'* ]]
  [[ "$(cat "$MOCK_LOG")" == *"ARG [$test_home/pipe home]"* ]]
  assert_clean_downloads
}

@test "download failures preserve the exit code and clean partial files" {
  make_cli "$mock_bin/t3"
  export MOCK_CURL_STATUS=22
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash "$remote_script"
  [ "$status" -eq 22 ]
  [[ "$output" == *'Could not download'* ]]
  [[ "$output" != *'Dracula is configured'* ]]
  [ ! -e "$MOCK_INSTALLED" ]
  assert_clean_downloads
}

@test "rejects empty downloads before theme installation" {
  make_cli "$mock_bin/t3"
  export MOCK_EMPTY_DOWNLOAD=yes
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash "$remote_script"
  [ "$status" -ne 0 ]
  [[ "$output" == *'downloaded theme is empty'* ]]
  [ ! -e "$MOCK_INSTALLED" ]
  assert_clean_downloads
}

@test "CLI installation failures preserve status and do not retry with npx" {
  make_cli "$mock_bin/t3"
  enable_npx
  export MOCK_INSTALL_STATUS=17
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash "$remote_script"
  [ "$status" -eq 17 ]
  [[ "$output" == *'Theme rejected'* ]]
  [[ "$output" != *'Dracula is configured'* ]]
  [[ "$(cat "$MOCK_LOG")" != *"CLI [$mock_bin/npx]"* ]]
  assert_clean_downloads
}

@test "rerunning publishes the same stable ID with the current theme" {
  make_cli "$mock_bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  printf '{"name":"Updated Dracula"}\n' > "$local_repo/Dracula.json"
  run_installer
  [ "$status" -eq 0 ]
  cmp "$local_repo/Dracula.json" "$MOCK_INSTALLED"
  [ "$(grep -c 'ARG \[dracula-t3code\]' "$MOCK_LOG")" -eq 2 ]
}

@test "missing Node or npx produces actionable errors" {
  run_installer
  [ "$status" -ne 0 ]
  [[ "$output" == *'Node.js is required'* ]]
  ln -s /bin/true "$mock_bin/node"
  run_installer
  [ "$status" -ne 0 ]
  [[ "$output" == *'npx is required'* ]]
}

@test "missing curl affects downloads but not local theme installation" {
  make_cli "$mock_bin/t3"
  rm "$mock_bin/curl"
  run_installer
  [ "$status" -eq 0 ]
  run env HOME="$test_home" PATH="$mock_bin" /bin/bash "$remote_script"
  [ "$status" -ne 0 ]
  [[ "$output" == *'curl is required'* ]]
  assert_clean_downloads
}

@test "npx capability failures expose the underlying diagnostic" {
  enable_npx
  export MOCK_HELP_MODE=error
  run_installer
  [ "$status" -ne 0 ]
  [[ "$output" == *'CLI download failed'* ]]
  [[ "$output" != *'Dracula is configured'* ]]
}

@test "Apple Silicon and ARM64 Linux can use npx" {
  enable_npx
  export MOCK_OS=Darwin MOCK_ARCH=arm64
  run_installer
  [ "$status" -eq 0 ]
  export MOCK_OS=Linux MOCK_ARCH=aarch64
  run_installer
  [ "$status" -eq 0 ]
}

@test "Intel Macs require an existing CLI while Windows is rejected" {
  enable_npx
  export MOCK_OS=Darwin MOCK_ARCH=x86_64
  run_installer
  [ "$status" -ne 0 ]
  [[ "$output" == *'no Intel Mac build'* ]]
  make_cli "$mock_bin/t3"
  run_installer
  [ "$status" -eq 0 ]
  export MOCK_OS=MINGW64_NT
  run_installer
  [ "$status" -ne 0 ]
  [[ "$output" == *'For Windows desktop'* ]]
}
