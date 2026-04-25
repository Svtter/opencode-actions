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
fake_bin_dir="$work_dir/fake-bin"
mkdir -p "$fake_bin_dir"

cat >"$fake_bin_dir/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'fake timeout %s\n' "$*"

duration="$1"
shift

printf 'TIMEOUT_DURATION=%s\n' "$duration"
"$@"
EOF

chmod +x "$fake_bin_dir/timeout"
export PATH="$fake_bin_dir:$OPENCODE_INSTALL_DIR:/usr/bin:/bin"

reset_wrapper_env() {
  unset GITHUB_RUN_OPENCODE_FALLBACK_MODELS
  unset GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS
  unset GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX
  unset FAKE_OPENCODE_TIMEOUT_MODELS
  unset FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS
  unset FAKE_OPENCODE_ERROR_MODELS

  export GITHUB_RUN_OPENCODE_MODEL="wrapper-model"
  export GITHUB_RUN_OPENCODE_PROMPT="review prompt"
  export GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN="true"
  export GITHUB_RUN_OPENCODE_GITHUB_TOKEN="gh-token"
  export GITHUB_RUN_OPENCODE_ZHIPU_API_KEY="zhipu-token"
  export GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY="go-token"
  export GITHUB_RUN_OPENCODE_ATTEMPTS="1"
  export GITHUB_RUN_OPENCODE_RETRY_PROFILE="github-network"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf '%s\n%s\n' "$message" "$haystack" >&2
    exit 1
  fi
}

reset_wrapper_env
output="$("$repo_root/github-run-opencode/run-github-opencode.sh" 2>&1)"

assert_contains "$output" "fake opencode github run" "expected github run invocation, got:"
assert_contains "$output" "MODEL=wrapper-model" "expected model env in output, got:"
assert_contains "$output" "PROMPT=review prompt" "expected prompt env in output, got:"
assert_contains "$output" "USE_GITHUB_TOKEN=true" "expected USE_GITHUB_TOKEN env in output, got:"
assert_contains "$output" "GITHUB_TOKEN=gh-token" "expected GITHUB_TOKEN env in output, got:"
assert_contains "$output" "ZHIPU_API_KEY=zhipu-token" "expected ZHIPU_API_KEY env in output, got:"
assert_contains "$output" "OPENCODE_API_KEY=go-token" "expected OPENCODE_API_KEY env in output, got:"

reset_wrapper_env
export GITHUB_RUN_OPENCODE_MODEL="zhipuai-coding-plan/glm-5"
export GITHUB_RUN_OPENCODE_FALLBACK_MODELS="opencode-go/gemini-2.5-pro"
export GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS="1"
export FAKE_OPENCODE_TIMEOUT_MODELS="zhipuai-coding-plan/glm-5"
export FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS="2"

fallback_output="$("$repo_root/github-run-opencode/run-github-opencode.sh" 2>&1)"

assert_contains "$fallback_output" "MODEL=opencode-go/gemini-2.5-pro" "expected fallback model to be used after timeout, got:"
assert_contains "$fallback_output" "OpenCode model zhipuai-coding-plan/glm-5 timed out" "expected timeout log before fallback, got:"

if [[ "$output" != *"TIMEOUT_DURATION=600s"* ]]; then
  printf 'expected default timeout duration of 600s, got:\n%s\n' "$output" >&2
  exit 1
fi

export GITHUB_RUN_OPENCODE_TIMEOUT_SECONDS="7"
override_output="$("$repo_root/github-run-opencode/run-github-opencode.sh" 2>&1)"

if [[ "$override_output" != *"TIMEOUT_DURATION=7s"* ]]; then
  printf 'expected override timeout duration of 7s, got:\n%s\n' "$override_output" >&2
  exit 1
fi

unset GITHUB_RUN_OPENCODE_MODEL
export MODEL_NAME="env-model-name"

output="$($repo_root/github-run-opencode/run-github-opencode.sh 2>&1)"

if [[ "$output" != *"MODEL=env-model-name"* ]]; then
  printf 'expected MODEL_NAME fallback in output, got:\n%s\n' "$output" >&2
  exit 1
fi

unset MODEL_NAME

output="$($repo_root/github-run-opencode/run-github-opencode.sh 2>&1)"

if [[ "$output" != *"MODEL=zhipuai-coding-plan/glm-5.1"* ]]; then
  printf 'expected built-in model fallback in output, got:\n%s\n' "$output" >&2
  exit 1
fi

printf 'github-run-opencode test passed\n'
