#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

install_dependency() {
  local repository="$1" revision="$2"
  local directory=".tests/site/pack/deps/start/${repository##*/}"
  if [[ ! -d "$directory" ]]; then
    mkdir -p "$directory"
    git -C "$directory" init -q
    git -C "$directory" remote add origin "https://github.com/$repository.git"
    timeout --kill-after=5s 60s git -C "$directory" fetch -q --depth=1 origin "$revision"
    git -C "$directory" checkout -q --detach FETCH_HEAD
  fi
  if [[ "$(git -C "$directory" rev-parse HEAD)" != "$revision" ]]; then
    echo "Unexpected test dependency revision: $directory (expected $revision)" >&2
    exit 1
  fi
}

install_dependency nvim-lua/plenary.nvim 74b06c6c75e4eeb3108ec01852001636d85a932b
install_dependency nvim-tree/nvim-web-devicons ec309a0eaff6ea967e58c275996155ab5c16938d
