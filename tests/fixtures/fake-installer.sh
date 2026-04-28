#!/usr/bin/env bash

set -euo pipefail

install_dir="${OPENCODE_INSTALL_DIR:?}"
target_dir="$install_dir"

if [[ "${FAKE_INSTALL_TARGET:-install-dir}" == "home-bin" ]]; then
  target_dir="$HOME/.opencode/bin"
fi

mkdir -p "$target_dir"

cat >"$target_dir/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

contains_model() {
  local list="$1"
  local target="$2"
  local item

  IFS=',' read -r -a items <<<"$list"
  for item in "${items[@]}"; do
    if [[ "$item" == "$target" ]]; then
      return 0
    fi
  done

  return 1
}

if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' "${FAKE_OPENCODE_VERSION:-0.0.0-test}"
  exit 0
fi

if [[ -n "${FAKE_OPENCODE_TIMEOUT_MODELS:-}" ]] && contains_model "$FAKE_OPENCODE_TIMEOUT_MODELS" "${MODEL:-}"; then
  sleep "${FAKE_OPENCODE_TIMEOUT_SLEEP_SECONDS:-5}"
fi

if [[ -n "${FAKE_OPENCODE_ERROR_MODELS:-}" ]] && contains_model "$FAKE_OPENCODE_ERROR_MODELS" "${MODEL:-}"; then
  printf 'deadline exceeded: simulated model error for %s\n' "${MODEL:-}" >&2
  exit 23
fi

printf 'fake opencode %s\n' "$*"
printf 'MODEL=%s\n' "${MODEL:-}"
printf 'PROMPT=%s\n' "${PROMPT:-}"
printf 'USE_GITHUB_TOKEN=%s\n' "${USE_GITHUB_TOKEN:-}"
printf 'GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN:-}"
printf 'ZHIPU_API_KEY=%s\n' "${ZHIPU_API_KEY:-}"
printf 'OPENCODE_API_KEY=%s\n' "${OPENCODE_API_KEY:-}"
EOF

chmod +x "$target_dir/opencode"
