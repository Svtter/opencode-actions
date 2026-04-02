#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

extract_prompt_default() {
  local action_file="$1"
  awk '
    /^  prompt:$/ {in_prompt=1; next}
    in_prompt && /^    default: \|$/ {in_default=1; next}
    in_default {
      if ($0 ~ /^  [a-zA-Z0-9_-]+:$/) {
        exit
      }
      sub(/^      /, "")
      print
    }
  ' "$action_file"
}

github_run_prompt_file="$(mktemp)"
review_prompt_file="$(mktemp)"
trap 'rm -f "$github_run_prompt_file" "$review_prompt_file"' EXIT

extract_prompt_default "$repo_root/github-run-opencode/action.yml" >"$github_run_prompt_file"
extract_prompt_default "$repo_root/review/action.yml" >"$review_prompt_file"

if ! diff -u "$github_run_prompt_file" "$review_prompt_file" >/dev/null; then
  printf 'review/action.yml prompt default must match github-run-opencode/action.yml\n' >&2
  exit 1
fi

if ! grep -Eq '^    default: zhipuai-coding-plan/glm-5$' "$repo_root/review/action.yml"; then
  printf 'review/action.yml model default is not zhipuai-coding-plan/glm-5\n' >&2
  exit 1
fi

printf 'review action metadata test passed\n'
