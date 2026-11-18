#!/usr/bin/env bash
# tmux-which-key - which-key popup for tmux
# Plugin entry point (sourced by TPM)

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IFS=$'\037' read -r trigger extras < <(tmux display-message -p $'#{@which-key-trigger}\037#{@which-key-extras}')
case "$extras" in
    none|off) extras=() ;;
    "") extras=(\; source-file "$CURRENT_DIR/configs/git.conf") ;;
    *) extras=(\; source-file "${extras/#\~/$HOME}") ;;
esac

# The script reads the other @which-key-* options and sizes the popup to the menu
tmux bind-key "${trigger:-Space}" run-shell "'$CURRENT_DIR/scripts/which-key.sh' --open --client '#{client_name}' '#{pane_id}'" "${extras[@]}"
