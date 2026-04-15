#!/usr/bin/env bash

set -euo pipefail

OPENCODE_INSTALL_DIR="${OPENCODE_INSTALL_DIR:-${RUNNER_TOOL_CACHE:-$HOME/.cache}/opencode/bin}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${RUNNER_TOOL_CACHE:-$HOME/.cache}/opencode/cache}"
OPENCODE_INSTALL_URL="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
OPENCODE_INSTALL_ATTEMPTS="${OPENCODE_INSTALL_ATTEMPTS:-3}"
OPENCODE_ALLOW_PREINSTALLED="${OPENCODE_ALLOW_PREINSTALLED:-false}"
OPENCODE_MIN_VERSION="${OPENCODE_MIN_VERSION:-}"
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

parse_semver() {
  local raw="$1"
  local normalized
  if [[ "$raw" =~ [vV]?([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?) ]]; then
    normalized="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  if [[ "$normalized" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    printf '%s\n' "$normalized"
    return 0
  fi
  return 1
}

semver_compare_prerelease() {
  local a="$1" b="$2"
  local -a a_parts b_parts
  local i limit

  IFS=. read -r -a a_parts <<<"$a"
  IFS=. read -r -a b_parts <<<"$b"
  limit="${#a_parts[@]}"
  if [[ "${#b_parts[@]}" -gt "$limit" ]]; then
    limit="${#b_parts[@]}"
  fi

  for ((i = 0; i < limit; i++)); do
    local ai="${a_parts[i]:-}"
    local bi="${b_parts[i]:-}"

    if [[ -z "$ai" ]] && [[ -n "$bi" ]]; then return 1; fi
    if [[ -n "$ai" ]] && [[ -z "$bi" ]]; then return 0; fi
    if [[ "$ai" == "$bi" ]]; then continue; fi

    if [[ "$ai" =~ ^[0-9]+$ ]] && [[ "$bi" =~ ^[0-9]+$ ]]; then
      if ((10#$ai > 10#$bi)); then return 0; fi
      if ((10#$ai < 10#$bi)); then return 1; fi
      continue
    fi

    if [[ "$ai" =~ ^[0-9]+$ ]]; then return 1; fi
    if [[ "$bi" =~ ^[0-9]+$ ]]; then return 0; fi
    if [[ "$ai" > "$bi" ]]; then return 0; fi
    return 1
  done

  return 0
}

semver_gte() {
  local a="$1" b="$2"
  local a_pre b_pre
  if [[ "$a" == *-* ]]; then
    a_pre="${a#*-}"
    a="${a%%-*}"
  else
    a_pre=""
  fi
  if [[ "$b" == *-* ]]; then
    b_pre="${b#*-}"
    b="${b%%-*}"
  else
    b_pre=""
  fi

  # Shell success means "a is greater than or equal to b".
  local i
  for i in 0 1 2; do
    local ai bi
    ai="$(echo "$a" | cut -d. -f$((i + 1)))"
    bi="$(echo "$b" | cut -d. -f$((i + 1)))"
    ai="${ai:-0}"
    bi="${bi:-0}"
    if [[ "$ai" -gt "$bi" ]]; then return 0; fi
    if [[ "$ai" -lt "$bi" ]]; then return 1; fi
  done
  if [[ -n "$a_pre" ]] && [[ -z "$b_pre" ]]; then return 1; fi
  if [[ -z "$a_pre" ]] && [[ -n "$b_pre" ]]; then return 0; fi
  if [[ -n "$a_pre" ]] && [[ -n "$b_pre" ]]; then
    semver_compare_prerelease "$a_pre" "$b_pre"
    return $?
  fi
  return 0
}

version_meets_minimum() {
  if [[ -z "$OPENCODE_MIN_VERSION" ]]; then return 0; fi
  local current="$1"
  local current_semver min_semver
  if ! current_semver="$(parse_semver "$current")"; then
    printf 'warning: could not parse version for comparison (current=%s, min=%s)\n' "$current" "$OPENCODE_MIN_VERSION" >&2
    return 1
  fi
  if ! min_semver="$(parse_semver "$OPENCODE_MIN_VERSION")"; then
    printf 'warning: could not parse version for comparison (current=%s, min=%s)\n' "$current" "$OPENCODE_MIN_VERSION" >&2
    return 1
  fi
  if semver_gte "$current_semver" "$min_semver"; then return 0; fi
  return 1
}

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
    if version_meets_minimum "$(opencode --version)"; then
      exit 0
    fi
    printf 'installed version below minimum %s, reinstalling\n' "$OPENCODE_MIN_VERSION" >&2
    rm -f "$OPENCODE_INSTALL_DIR/opencode"
    hash -r
  fi
fi

if [[ "$OPENCODE_ALLOW_PREINSTALLED" == "true" ]] && command -v opencode >/dev/null 2>&1; then
  materialize_binary "$(command -v opencode)"
  if activate_install_dir; then
    if version_meets_minimum "$(opencode --version)"; then
      exit 0
    fi
    printf 'preinstalled version below minimum %s, falling through to installer\n' "$OPENCODE_MIN_VERSION" >&2
    rm -f "$OPENCODE_INSTALL_DIR/opencode"
    hash -r
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
  if version_meets_minimum "$(opencode --version)"; then
  exit 0
  fi

  printf 'installed version does not satisfy minimum %s\n' "$OPENCODE_MIN_VERSION" >&2
  exit 1
fi

printf "OpenCode install script finished, but 'opencode' is still unavailable\n" >&2
exit 1
