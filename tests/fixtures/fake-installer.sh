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
if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' "${FAKE_OPENCODE_VERSION:-0.0.0-test}"
  exit 0
fi
printf 'fake opencode %s\n' "$*"
printf 'MODEL=%s\n' "${MODEL:-}"
printf 'PROMPT=%s\n' "${PROMPT:-}"
printf 'USE_GITHUB_TOKEN=%s\n' "${USE_GITHUB_TOKEN:-}"
printf 'GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN:-}"
printf 'ZHIPU_API_KEY=%s\n' "${ZHIPU_API_KEY:-}"
printf 'OPENCODE_GO_API_KEY=%s\n' "${OPENCODE_GO_API_KEY:-}"
EOF

chmod +x "$target_dir/opencode"
