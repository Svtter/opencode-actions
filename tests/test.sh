#!/usr/bin/env bash

set -euo pipefail

bash tests/setup-opencode.sh
bash tests/run-opencode.sh
