#!/usr/bin/env bash

set -euo pipefail

OPENCODE_INSTALL_DIR="${OPENCODE_INSTALL_DIR:-${RUNNER_TOOL_CACHE:-$HOME/.cache}/opencode/bin}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${RUNNER_TOOL_CACHE:-$HOME/.cache}/opencode/cache}"
OPENCODE_INSTALL_URL="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
OPENCODE_INSTALL_ATTEMPTS="${OPENCODE_INSTALL_ATTEMPTS:-3}"
OPENCODE_ALLOW_PREINSTALLED="${OPENCODE_ALLOW_PREINSTALLED:-false}"
DEFAULT_OPENCODE_BIN_DIR="$HOME/.opencode/bin"
FALLBACK_OPENCODE_BIN_DIR="${RUNNER_TOOL_CACHE:-$HOME/.cache}/opencode/bin"

require_positive_integer() {
  local value="$1"
  local name="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    printf '%s must be a positive integer, got %s\n' "$name" "$value" >&2
    exit 1
  fi
}

require_positive_integer "$OPENCODE_INSTALL_ATTEMPTS" "OPENCODE_INSTALL_ATTEMPTS"

append_github_path() {
  local path_entry="$1"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    printf '%s\n' "$path_entry" >>"$GITHUB_PATH"
  fi
}

activate_install_dir() {
  export PATH="$OPENCODE_INSTALL_DIR:$PATH"
  append_github_path "$OPENCODE_INSTALL_DIR"
  if opencode --version; then
    return 0
  fi

  rm -f "$OPENCODE_INSTALL_DIR/opencode"
  hash -r
  return 1
}

materialize_binary() {
  local candidate="$1"
  if [[ "$candidate" != "$OPENCODE_INSTALL_DIR/opencode" ]]; then
    cp "$candidate" "$OPENCODE_INSTALL_DIR/opencode"
    chmod +x "$OPENCODE_INSTALL_DIR/opencode"
  fi
}

mkdir -p "$OPENCODE_INSTALL_DIR"
mkdir -p "$XDG_CACHE_HOME"

export OPENCODE_INSTALL_DIR
export XDG_CACHE_HOME
export PATH="$OPENCODE_INSTALL_DIR:$PATH"

if [[ -x "$OPENCODE_INSTALL_DIR/opencode" ]]; then
  if activate_install_dir; then
    exit 0
  fi
fi

if [[ "$OPENCODE_ALLOW_PREINSTALLED" == "true" ]] && command -v opencode >/dev/null 2>&1; then
  materialize_binary "$(command -v opencode)"
  if activate_install_dir; then
    exit 0
  fi
fi

attempt=1
while [[ "$attempt" -le "$OPENCODE_INSTALL_ATTEMPTS" ]]; do
  if curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 5 \
    --retry-delay 2 \
    "$OPENCODE_INSTALL_URL" | bash; then
    break
  fi

  if [[ "$attempt" -eq "$OPENCODE_INSTALL_ATTEMPTS" ]]; then
    printf 'OpenCode installation failed after %s attempts\n' "$OPENCODE_INSTALL_ATTEMPTS" >&2
    exit 1
  fi

  sleep "$((attempt * 5))"
  attempt="$((attempt + 1))"
done

resolved_candidate=""
for candidate in \
  "$OPENCODE_INSTALL_DIR/opencode" \
  "$DEFAULT_OPENCODE_BIN_DIR/opencode" \
  "$FALLBACK_OPENCODE_BIN_DIR/opencode"
do
  if [[ -x "$candidate" ]]; then
    resolved_candidate="$candidate"
    break
  fi
done

if [[ -z "$resolved_candidate" ]] && [[ "$OPENCODE_ALLOW_PREINSTALLED" == "true" ]] && command -v opencode >/dev/null 2>&1; then
  resolved_candidate="$(command -v opencode)"
fi

if [[ -z "$resolved_candidate" ]]; then
  printf "OpenCode install script finished, but 'opencode' is still unavailable\n" >&2
  exit 1
fi

materialize_binary "$resolved_candidate"
if activate_install_dir; then
  exit 0
fi

printf "OpenCode install script finished, but 'opencode' is still unavailable\n" >&2
exit 1
