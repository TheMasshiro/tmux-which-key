#!/usr/bin/env bash
# tmux-which-key - which-key popup for tmux
# Plugin entry point (sourced by TPM)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

main() {
    local trigger
    trigger=$(tmux show-option -gqv "@which-key-trigger")

    # The script reads the other @which-key-* options and sizes the popup to the menu
    tmux bind-key "${trigger:-Space}" run-shell "'$CURRENT_DIR/scripts/which-key.sh' --open --client '#{client_name}' '#{pane_id}'"
}

main
