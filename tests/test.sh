#!/usr/bin/env bash

set -euo pipefail

bash tests/setup-opencode.sh
bash tests/run-opencode.sh
bash tests/github-run-opencode.sh
bash tests/review-action.sh
