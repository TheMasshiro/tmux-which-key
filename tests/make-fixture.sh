#!/usr/bin/env bash
# Rebuilds tests/fixture.dump from tests/fixture.conf with a clean tmux server
# (the same dump which-key.sh reads), then the expected outputs. Needs tmux.
set -euo pipefail
cd "$(dirname "$0")"

sock="wk-fixture-$$"
tmux -L "$sock" -f fixture.conf new-session -d -x 100 -y 30
trap 'tmux -L "$sock" kill-server 2>/dev/null' EXIT
{
    printf 'D\t100\t30\n'   # a fixed client size: no client is attached
    tmux -L "$sock" list-keys -F $'K\t#{key_table}\t#{key_string}\t#{key_repeat}\t#{key_note}\t#{key_command}' \; show-options -g |
        grep -E '^(K'$'\t''|@which-key-)'   # only what menu.awk reads
} > fixture.dump

UPDATE=1 ./run.sh
