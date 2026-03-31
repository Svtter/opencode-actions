#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
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

export HOME="$work_dir/home"
export OPENCODE_INSTALL_URL="http://127.0.0.1:${port}/fake-installer.sh"
export OPENCODE_INSTALL_DIR="$work_dir/bin"
export XDG_CACHE_HOME="$work_dir/cache"
export OPENCODE_INSTALL_ATTEMPTS="1"
export OPENCODE_ALLOW_PREINSTALLED="false"
export PATH="/usr/bin:/bin"
export FAKE_OPENCODE_VERSION="9.9.9-wrapper"

"$repo_root/setup-opencode/install-opencode.sh"
export PATH="$OPENCODE_INSTALL_DIR:/usr/bin:/bin"

export GITHUB_RUN_OPENCODE_MODEL="wrapper-model"
export GITHUB_RUN_OPENCODE_PROMPT="review prompt"
export GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN="true"
export GITHUB_RUN_OPENCODE_GITHUB_TOKEN="gh-token"
export GITHUB_RUN_OPENCODE_ZHIPU_API_KEY="zhipu-token"
export GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY="go-token"
export GITHUB_RUN_OPENCODE_ATTEMPTS="1"
export GITHUB_RUN_OPENCODE_RETRY_PROFILE="github-network"

output="$("$repo_root/github-run-opencode/run-github-opencode.sh" 2>&1)"

if [[ "$output" != *"fake opencode github run"* ]]; then
  printf 'expected github run invocation, got:\n%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"MODEL=wrapper-model"* ]]; then
  printf 'expected model env in output, got:\n%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"PROMPT=review prompt"* ]]; then
  printf 'expected prompt env in output, got:\n%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"USE_GITHUB_TOKEN=true"* ]]; then
  printf 'expected USE_GITHUB_TOKEN env in output, got:\n%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"GITHUB_TOKEN=gh-token"* ]]; then
  printf 'expected GITHUB_TOKEN env in output, got:\n%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"ZHIPU_API_KEY=zhipu-token"* ]]; then
  printf 'expected ZHIPU_API_KEY env in output, got:\n%s\n' "$output" >&2
  exit 1
fi

if [[ "$output" != *"OPENCODE_GO_API_KEY=go-token"* ]]; then
  printf 'expected OPENCODE_GO_API_KEY env in output, got:\n%s\n' "$output" >&2
  exit 1
fi

printf 'github-run-opencode test passed\n'
