#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
attempt_file="$work_dir/attempts"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

cat >"$work_dir/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
attempt_file="${FAKE_OPENCODE_ATTEMPT_FILE:?}"
attempt="0"
if [[ -f "$attempt_file" ]]; then
  attempt="$(<"$attempt_file")"
fi
attempt="$((attempt + 1))"
printf '%s' "$attempt" >"$attempt_file"
if (( attempt < 3 )); then
  printf 'Failed to connect to github.com port 443\n' >&2
  exit 42
fi
printf 'success on attempt %s\n' "$attempt"
EOF

chmod +x "$work_dir/opencode"

export PATH="$work_dir:$PATH"
export FAKE_OPENCODE_ATTEMPT_FILE="$attempt_file"
export OPENCODE_ARGS="github run"
export OPENCODE_ATTEMPTS="3"
export OPENCODE_RETRY_ON_REGEX="Failed to connect to github\\.com port 443"
export OPENCODE_RETRY_DELAY_SECONDS="0"

output="$($repo_root/run-opencode/run-opencode.sh 2>&1)"

if [[ "$output" != *"success on attempt 3"* ]]; then
  printf 'expected successful retry output, got:\n%s\n' "$output" >&2
  exit 1
fi

attempts="$(<"$attempt_file")"
if [[ "$attempts" != "3" ]]; then
  printf 'expected 3 attempts, got %s\n' "$attempts" >&2
  exit 1
fi

export OPENCODE_ATTEMPTS="0"
if "$repo_root/run-opencode/run-opencode.sh" >/dev/null 2>&1; then
  printf 'expected attempts=0 to fail validation\n' >&2
  exit 1
fi

printf 'run-opencode test passed\n'
