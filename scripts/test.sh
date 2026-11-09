#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
mkdir -p .tests
export NVIM_LOG_FILE="$PWD/.tests/nvim.log"
export BUFFERLINE_TEST_PATH="${1:-tests/}"
timeout --kill-after=5s 120s "${NVIM_BIN:-nvim}" --headless --noplugin -i NONE \
  -u tests/minimal_init.lua -c 'runtime plugin/plenary.vim' \
  -c "lua require('plenary.test_harness').test_directory(vim.env.BUFFERLINE_TEST_PATH, {minimal_init = 'tests/minimal_init.lua', sequential = true, timeout = 10000})"
