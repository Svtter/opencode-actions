#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow_file="$repo_root/.github/workflows/review.yml"

if [[ ! -f "$workflow_file" ]]; then
  printf 'expected dogfood review workflow at %s\n' "$workflow_file" >&2
  exit 1
fi

if ! grep -Fq 'uses: Svtter/opencode-actions/review@v1' "$workflow_file"; then
  printf 'expected workflow to use published review@v1 action\n' >&2
  exit 1
fi

if ! grep -Fq 'model: opencode-go/minimax-m2.7' "$workflow_file"; then
  printf 'expected workflow to pin model to opencode-go/minimax-m2.7\n' >&2
  exit 1
fi

if ! grep -Fq 'github.event.pull_request.head.repo.full_name == github.repository' "$workflow_file"; then
  printf 'expected workflow to skip fork pull requests\n' >&2
  exit 1
fi

if ! grep -Fq 'zhipu-api-key: ${{ secrets.ZHIPU_API_KEY }}' "$workflow_file"; then
  printf 'expected workflow to wire ZHIPU_API_KEY secret\n' >&2
  exit 1
fi

printf 'dogfood review workflow test passed\n'
