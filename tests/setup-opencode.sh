#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
server_root="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$server_root"
}
trap cleanup EXIT

pick_port() {
  python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

port="$(pick_port)"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$repo_root/tests/fixtures" >/dev/null 2>&1 &
server_pid=$!
sleep 1

run_install_case() {
  local case_dir="$1"
  shift

  export HOME="$case_dir/home"
  export OPENCODE_INSTALL_URL="http://127.0.0.1:${port}/fake-installer.sh"
  export OPENCODE_INSTALL_DIR="$case_dir/bin"
  export XDG_CACHE_HOME="$case_dir/cache"
  export OPENCODE_INSTALL_ATTEMPTS="${OPENCODE_INSTALL_ATTEMPTS:-1}"
  export OPENCODE_ALLOW_PREINSTALLED="${OPENCODE_ALLOW_PREINSTALLED:-false}"
  export PATH="$case_dir/path:/usr/bin:/bin"

  mkdir -p "$HOME" "$case_dir/path"
  "$repo_root/setup-opencode/install-opencode.sh" "$@"
}

case_one="$server_root/case-one"
export FAKE_OPENCODE_VERSION="1.2.3-test"
export FAKE_INSTALL_TARGET="install-dir"
run_install_case "$case_one"

if [[ ! -x "$case_one/bin/opencode" ]]; then
  printf 'expected installed binary at %s\n' "$case_one/bin/opencode" >&2
  exit 1
fi

actual_version="$("$case_one/bin/opencode" --version)"
if [[ "$actual_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected version %s, got %s\n' "$FAKE_OPENCODE_VERSION" "$actual_version" >&2
  exit 1
fi

case_two="$server_root/case-two"
mkdir -p "$case_two/path"
cat >"$case_two/path/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'preinstalled-version\n'
EOF
chmod +x "$case_two/path/opencode"

export FAKE_OPENCODE_VERSION="2.3.4-installed"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
run_install_case "$case_two"

if [[ ! -x "$case_two/bin/opencode" ]]; then
  printf 'expected installer-managed binary at %s\n' "$case_two/bin/opencode" >&2
  exit 1
fi

preinstalled_version="$("$case_two/bin/opencode" --version)"
if [[ "$preinstalled_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected installer-managed version %s, got %s\n' "$FAKE_OPENCODE_VERSION" "$preinstalled_version" >&2
  exit 1
fi

case_two_opt_in="$server_root/case-two-opt-in"
mkdir -p "$case_two_opt_in/path"
cat >"$case_two_opt_in/path/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'preinstalled-version\n'
EOF
chmod +x "$case_two_opt_in/path/opencode"

export FAKE_OPENCODE_VERSION="should-not-install"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="true"
run_install_case "$case_two_opt_in"

opt_in_version="$("$case_two_opt_in/bin/opencode" --version)"
if [[ "$opt_in_version" != "preinstalled-version" ]]; then
  printf 'expected opt-in preinstalled version, got %s\n' "$opt_in_version" >&2
  exit 1
fi

case_three="$server_root/case-three"
export FAKE_OPENCODE_VERSION="4.5.6-home"
export FAKE_INSTALL_TARGET="home-bin"
export OPENCODE_ALLOW_PREINSTALLED="false"
run_install_case "$case_three"

if [[ ! -x "$case_three/bin/opencode" ]]; then
  printf 'expected fallback-installed binary copied to %s\n' "$case_three/bin/opencode" >&2
  exit 1
fi

home_version="$("$case_three/bin/opencode" --version)"
if [[ "$home_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected fallback-installed version %s, got %s\n' "$FAKE_OPENCODE_VERSION" "$home_version" >&2
  exit 1
fi

case_four="$server_root/case-four"
mkdir -p "$case_four/bin"
cat >"$case_four/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'broken cached binary\n' >&2
exit 99
EOF
chmod +x "$case_four/bin/opencode"

export FAKE_OPENCODE_VERSION="7.8.9-recovered"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
run_install_case "$case_four"

recovered_version="$("$case_four/bin/opencode" --version)"
if [[ "$recovered_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected recovered version %s, got %s\n' "$FAKE_OPENCODE_VERSION" "$recovered_version" >&2
  exit 1
fi

case_five="$server_root/case-five"
mkdir -p "$case_five/path"
cat >"$case_five/path/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected-preinstalled\n'
EOF
chmod +x "$case_five/path/opencode"

export FAKE_OPENCODE_VERSION="should-fail"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_INSTALL_ATTEMPTS="0"
if run_install_case "$case_five" >/dev/null 2>&1; then
  printf 'expected install-attempts=0 to fail validation\n' >&2
  exit 1
fi

case_six="$server_root/case-six"
mkdir -p "$case_six/bin"
cat >"$case_six/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '1.0.0\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_six/bin/opencode"

export FAKE_OPENCODE_VERSION="2.0.0-upgraded"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_INSTALL_ATTEMPTS="3"
export OPENCODE_MIN_VERSION="1.4.5"
run_install_case "$case_six"

upgraded_version="$("$case_six/bin/opencode" --version)"
if [[ "$upgraded_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected upgraded version %s (cached 1.0.0 below min 1.4.5), got %s\n' "$FAKE_OPENCODE_VERSION" "$upgraded_version" >&2
  exit 1
fi

case_seven="$server_root/case-seven"
mkdir -p "$case_seven/bin"
cat >"$case_seven/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '2.0.0\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_seven/bin/opencode"

export FAKE_OPENCODE_VERSION="should-not-install"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_MIN_VERSION="1.4.5"
run_install_case "$case_seven"

cached_version="$("$case_seven/bin/opencode" --version)"
if [[ "$cached_version" != "2.0.0" ]]; then
  printf 'expected cached version 2.0.0 (meets min 1.4.5), got %s\n' "$cached_version" >&2
  exit 1
fi

case_eight="$server_root/case-eight"
mkdir -p "$case_eight/bin"
cat >"$case_eight/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '0.1.0\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_eight/bin/opencode"

export FAKE_OPENCODE_VERSION="should-not-install"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_MIN_VERSION=""
run_install_case "$case_eight"

no_check_version="$("$case_eight/bin/opencode" --version)"
if [[ "$no_check_version" != "0.1.0" ]]; then
  printf 'expected cached version 0.1.0 (version check disabled), got %s\n' "$no_check_version" >&2
  exit 1
fi

case_nine="$server_root/case-nine"
mkdir -p "$case_nine/bin"
cat >"$case_nine/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '1.5.0-beta.1\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_nine/bin/opencode"

export FAKE_OPENCODE_VERSION="1.5.0"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_MIN_VERSION="1.5.0"
run_install_case "$case_nine"

prerelease_upgraded_version="$("$case_nine/bin/opencode" --version)"
if [[ "$prerelease_upgraded_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected prerelease cached version to upgrade to %s, got %s\n' "$FAKE_OPENCODE_VERSION" "$prerelease_upgraded_version" >&2
  exit 1
fi

case_ten="$server_root/case-ten"
mkdir -p "$case_ten/bin"
cat >"$case_ten/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '1.5.0\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_ten/bin/opencode"

export FAKE_OPENCODE_VERSION="1.5.0"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_MIN_VERSION="not-a-semver"
if run_install_case "$case_ten" >/dev/null 2>&1; then
  printf 'expected invalid minimum version to fail validation\n' >&2
  exit 1
fi

case_eleven="$server_root/case-eleven"
mkdir -p "$case_eleven/path"
cat >"$case_eleven/path/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '1.0.0\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_eleven/path/opencode"

export FAKE_OPENCODE_VERSION="1.6.0"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="true"
export OPENCODE_MIN_VERSION="1.5.0"
run_install_case "$case_eleven"

preinstalled_upgraded_version="$("$case_eleven/bin/opencode" --version)"
if [[ "$preinstalled_upgraded_version" != "$FAKE_OPENCODE_VERSION" ]]; then
  printf 'expected outdated preinstalled version to upgrade to %s, got %s\n' "$FAKE_OPENCODE_VERSION" "$preinstalled_upgraded_version" >&2
  exit 1
fi

case_twelve="$server_root/case-twelve"
mkdir -p "$case_twelve/bin"
cat >"$case_twelve/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf '1.0.0\n'
  exit 0
fi
printf 'fake opencode %s\n' "$*"
EOF
chmod +x "$case_twelve/bin/opencode"

export FAKE_OPENCODE_VERSION="1.4.9"
export FAKE_INSTALL_TARGET="install-dir"
export OPENCODE_ALLOW_PREINSTALLED="false"
export OPENCODE_MIN_VERSION="1.5.0"
if run_install_case "$case_twelve" >/dev/null 2>&1; then
  printf 'expected install result below minimum version to fail validation\n' >&2
  exit 1
fi

printf 'setup-opencode test passed\n'
