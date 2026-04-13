#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export OPENCODE_ARGS="github run"
export OPENCODE_WORKING_DIRECTORY="${GITHUB_RUN_OPENCODE_WORKING_DIRECTORY:-}"
export OPENCODE_ATTEMPTS="${GITHUB_RUN_OPENCODE_ATTEMPTS:-3}"
export OPENCODE_RETRY_PROFILE="${GITHUB_RUN_OPENCODE_RETRY_PROFILE:-github-network}"
export OPENCODE_RETRY_ON_REGEX="${GITHUB_RUN_OPENCODE_RETRY_ON_REGEX:-}"
export OPENCODE_RETRY_DELAY_SECONDS="${GITHUB_RUN_OPENCODE_RETRY_DELAY_SECONDS:-15}"

if [[ -n "${GITHUB_RUN_OPENCODE_MODEL:-}" ]]; then
  export MODEL="$GITHUB_RUN_OPENCODE_MODEL"
fi

if [[ -n "${GITHUB_RUN_OPENCODE_PROMPT:-}" ]]; then
  export PROMPT="$GITHUB_RUN_OPENCODE_PROMPT"
fi

if [[ -n "${GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN:-}" ]]; then
  export USE_GITHUB_TOKEN="$GITHUB_RUN_OPENCODE_USE_GITHUB_TOKEN"
fi

if [[ -n "${GITHUB_RUN_OPENCODE_GITHUB_TOKEN:-}" ]]; then
  export GITHUB_TOKEN="$GITHUB_RUN_OPENCODE_GITHUB_TOKEN"
fi

if [[ -n "${GITHUB_RUN_OPENCODE_ZHIPU_API_KEY:-}" ]]; then
  export ZHIPU_API_KEY="$GITHUB_RUN_OPENCODE_ZHIPU_API_KEY"
fi

if [[ -n "${GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY:-}" ]]; then
  export OPENCODE_GO_API_KEY="$GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY"

  xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  auth_dir="$xdg_data_home/opencode"
  auth_file="$auth_dir/auth.json"

  mkdir -p "$auth_dir"

  if [[ -f "$auth_file" ]]; then
    tmp="$(cat "$auth_file")"
  else
    tmp="{}"
  fi

  opencode_go_key="$GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY"
  tmp="$(printf '%s' "$tmp" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['opencode-go'] = {'type': 'api', 'key': sys.argv[1]}
json.dump(data, sys.stdout, indent=2)
" "$opencode_go_key")"

  printf '%s\n' "$tmp" > "$auth_file"
fi

exec "$script_dir/../run-opencode/run-opencode.sh"
