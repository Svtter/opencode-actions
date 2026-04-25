#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fallback_models_input="${GITHUB_RUN_OPENCODE_FALLBACK_MODELS:-}"
model_timeout_seconds="${GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS:-0}"
fallback_on_regex="${GITHUB_RUN_OPENCODE_FALLBACK_ON_REGEX:-timed out|timeout|deadline exceeded|context deadline exceeded|operation timed out|connection timed out}"

export OPENCODE_ARGS="github run"
export OPENCODE_WORKING_DIRECTORY="${GITHUB_RUN_OPENCODE_WORKING_DIRECTORY:-}"
export OPENCODE_ATTEMPTS="${GITHUB_RUN_OPENCODE_ATTEMPTS:-3}"
export OPENCODE_RETRY_PROFILE="${GITHUB_RUN_OPENCODE_RETRY_PROFILE:-github-network}"
export OPENCODE_RETRY_ON_REGEX="${GITHUB_RUN_OPENCODE_RETRY_ON_REGEX:-}"
export OPENCODE_RETRY_DELAY_SECONDS="${GITHUB_RUN_OPENCODE_RETRY_DELAY_SECONDS:-15}"

if [[ -n "${GITHUB_RUN_OPENCODE_MODEL:-}" ]]; then
  export MODEL="$GITHUB_RUN_OPENCODE_MODEL"
elif [[ -n "${MODEL_NAME:-}" ]]; then
  export MODEL="$MODEL_NAME"
else
  export MODEL="zhipuai-coding-plan/glm-5.1"
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
  export OPENCODE_API_KEY="$GITHUB_RUN_OPENCODE_OPENCODE_GO_API_KEY"
fi

if [[ -n "${GITHUB_RUN_OPENCODE_DEEPSEEK_API_KEY:-}" ]]; then
  export DEEPSEEK_API_KEY="$GITHUB_RUN_OPENCODE_DEEPSEEK_API_KEY"
fi

require_non_negative_integer() {
  local value="$1"
  local name="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf '%s must be a non-negative integer, got %s\n' "$name" "$value" >&2
    exit 1
  fi
}

supports_model_with_available_key() {
  local model="$1"

  case "$model" in
    zhipuai*/*)
      [[ -n "${ZHIPU_API_KEY:-}" ]]
      ;;
    opencode-go/*)
      [[ -n "${OPENCODE_API_KEY:-}" ]]
      ;;
    *)
      return 0
      ;;
  esac
}

append_candidate_model() {
  local model="$1"
  local existing

  if [[ -z "$model" ]]; then
    return 0
  fi

  for existing in "${candidate_models[@]}"; do
    if [[ "$existing" == "$model" ]]; then
      return 0
    fi
  done

  candidate_models+=("$model")
}

parse_candidate_models() {
  local raw_list="$1"
  local line
  local normalized_line

  while IFS= read -r line; do
    normalized_line="${line#,}"
    normalized_line="${normalized_line%,}"
    normalized_line="${normalized_line#${normalized_line%%[![:space:]]*}}"
    normalized_line="${normalized_line%${normalized_line##*[![:space:]]}}"
    append_candidate_model "$normalized_line"
  done < <(printf '%s\n' "$raw_list" | tr ',' '\n')
}

run_model() {
  local model="$1"
  local log_file="$2"
  local status

  export MODEL="$model"

  if [[ "$model_timeout_seconds" -gt 0 ]]; then
    timeout --foreground "${model_timeout_seconds}s" "$script_dir/../run-opencode/run-opencode.sh" 2>&1 | tee "$log_file"
    status=${PIPESTATUS[0]}
  else
    "$script_dir/../run-opencode/run-opencode.sh" 2>&1 | tee "$log_file"
    status=${PIPESTATUS[0]}
  fi

  return "$status"
}

require_non_negative_integer "$model_timeout_seconds" "GITHUB_RUN_OPENCODE_MODEL_TIMEOUT_SECONDS"

candidate_models=()
eligible_models=()

append_candidate_model "${GITHUB_RUN_OPENCODE_MODEL:-}"
parse_candidate_models "$fallback_models_input"

if [[ "${#candidate_models[@]}" -eq 0 ]]; then
  exec "$script_dir/../run-opencode/run-opencode.sh"
fi

for model in "${candidate_models[@]}"; do
  if supports_model_with_available_key "$model"; then
    eligible_models+=("$model")
  else
    printf 'Skipping fallback model %s because its provider key is unavailable\n' "$model" >&2
  fi
done

if [[ "${#eligible_models[@]}" -eq 0 ]]; then
  printf 'No eligible models available after API key filtering\n' >&2
  exit 1
fi

if [[ "${#eligible_models[@]}" -eq 1 ]]; then
  export MODEL="${eligible_models[0]}"
  exec "$script_dir/../run-opencode/run-opencode.sh"
fi

for index in "${!eligible_models[@]}"; do
  model="${eligible_models[$index]}"
  log_file="$(mktemp)"

  set +e
  run_model "$model" "$log_file"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    rm -f "$log_file"
    exit 0
  fi

  is_last_model=0
  if [[ "$index" -eq "$(( ${#eligible_models[@]} - 1 ))" ]]; then
    is_last_model=1
  fi

  if [[ "$status" -eq 124 ]]; then
    printf 'OpenCode model %s timed out after %ss\n' "$model" "$model_timeout_seconds" >&2
    if [[ "$is_last_model" -eq 0 ]]; then
      rm -f "$log_file"
      continue
    fi
  fi

  if [[ "$is_last_model" -eq 0 ]] && [[ -n "$fallback_on_regex" ]] && grep -Eiq "$fallback_on_regex" "$log_file"; then
    printf 'OpenCode model %s matched fallback regex, trying next candidate\n' "$model" >&2
    rm -f "$log_file"
    continue
  fi

  rm -f "$log_file"
  exit "$status"
done
