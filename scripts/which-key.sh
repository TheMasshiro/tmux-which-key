#!/usr/bin/env bash
# tmux-which-key - LazyVim-style which-key popup for tmux
# Usage: which-key.sh [--config <path>] <pane_id>

set -uo pipefail
printf '\033[?25l'
trap 'printf "\033[?25h"' EXIT

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE=""
PANE_ID=""
CLIENT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --client)
            CLIENT="$2"
            shift 2
            ;;
        *)
            PANE_ID="$1"
            shift
            ;;
    esac
done

# Resolve config file: explicit > XDG > user home > live tmux bindings (CONFIG_FILE stays empty)
if [[ -z "$CONFIG_FILE" ]]; then
    local_xdg="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-which-key/config.json"
    local_home="$HOME/.tmux-which-key.json"
    if [[ -f "$local_xdg" ]]; then
        CONFIG_FILE="$local_xdg"
    elif [[ -f "$local_home" ]]; then
        CONFIG_FILE="$local_home"
    fi
fi

# Build the menu from the prefix key table of the running tmux server.
# Bindings are grouped by the tmux command family they run (pane, window, ...);
# a `switch-client -T <table>` binding becomes a group listing that table (one level).
# Description is the `bind -N` note, else the command truncated.
build_from_tmux() {
    tmux list-keys -F $'#{key_table}\t#{key_string}\t#{key_note}\t#{key_command}' | jq -Rn '
        [inputs | split("\t") | {t: .[0], k: .[1], n: .[2], c: (.[3:] | join(" "))}] as $b
        | def desc: if .n != "" then .n else .c[:22] end;
          def leaf: {key: .k, type: "key", description: desc, command: (.t + " " + .k)};
          def is_table: .c | test("^switch-client -T ");
          # shortcut: first word decides the group, wrappers use the whole command, add a family here if one lands in misc
          def cat:
              (.c | split(" ")[0]) as $w
              | (if $w | IN("confirm-before", "command-prompt", "if-shell") then .c else $w end) as $x
              | if   $x | test("pane|split-window|clear-history") then "pane"
                elif $x | test("window|rotate") then "window"
                elif $x | test("session|client|choose-tree") then "session"
                elif $x | test("buffer|copy-mode") then "buffer"
                elif $x | test("layout") then "layout"
                else "misc" end;
          [$b[] | select(.t == "prefix")] as $p
          | {items: (
              [[["pane","p"],["window","w"],["session","s"],["buffer","b"],["layout","l"],["misc","m"]][] as [$n, $k]
               | [$p[] | select((is_table | not) and cat == $n) | leaf] as $i
               | select($i | length > 0)
               | {key: $k, type: "group", description: $n, items: $i}]
              + [$p[] | select(is_table)
                 | (.c | sub("^switch-client -T "; "")) as $t
                 | {key: .k, type: "group", description: (if .n != "" then .n else $t end),
                    items: [$b[] | select(.t == $t) | leaf]}])}'
}

# Catppuccin Mocha theme colors
C_KEY=$'\033[38;2;249;226;175m'       # #F9E2AF - yellow
C_GRP=$'\033[38;2;137;220;235m'       # #89DCEB - sky
C_DESC=$'\033[38;2;205;214;244m'      # #CDD6F4 - text
C_SEP=$'\033[38;2;108;112;134m'       # #6C7086 - overlay0
C_HDR=$'\033[38;2;137;180;250m'       # #89B4FA - blue
C_R=$'\033[0m'

if [[ -z "$PANE_ID" ]]; then
    echo "Usage: which-key.sh [--config <path>] <pane_id>"
    exit 1
fi

if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG=$(build_from_tmux)
elif [[ -f "$CONFIG_FILE" ]]; then
    CONFIG=$(cat "$CONFIG_FILE")
else
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

COLS=$(tput cols 2>/dev/null || echo 100)
SEP_LINE=$(printf '%*s' $((COLS - 2)) '')
SEP_LINE=${SEP_LINE// /─}

# Navigation stack (jq path indices)
NAV_STACK=()

# Get current items as tab-separated lines: key\ttype\tdescription\tcommand\timmediate
# Single jq call per menu level instead of per-item
get_current_items() {
    local path=".items"
    for idx in "${NAV_STACK[@]}"; do
        path="${path}[${idx}].items"
    done
    echo "$CONFIG" | jq -r "${path}[] | [.key, .type, .description, (.command // \"\"), (if .immediate then \"true\" else \"false\" end)] | @tsv" 2>/dev/null
}

get_breadcrumb() {
    local path=".items"
    local parts=("root")
    for idx in "${NAV_STACK[@]}"; do
        parts+=("$(echo "$CONFIG" | jq -r "${path}[${idx}].description")")
        path="${path}[${idx}].items"
    done
    local IFS=" > "
    echo "${parts[*]}"
}

render_menu() {
    clear

    local breadcrumb
    breadcrumb=$(get_breadcrumb)

    # Header
    printf "%s  Which Key%s  %s│%s  %s%s%s\n" "$C_HDR" "$C_R" "$C_SEP" "$C_R" "$C_DESC" "$breadcrumb" "$C_R"
    printf "%s%s%s\n" "$C_SEP" "$SEP_LINE" "$C_R"

    # Parse all items in one jq call
    local keys=() types=() descs=()
    while IFS=$'\t' read -r key type desc _cmd; do
        keys+=("$key")
        types+=("$type")
        descs+=("$desc")
    done < <(get_current_items)

    local total=${#keys[@]}
    if [[ $total -eq 0 ]]; then
        printf "  %s(empty)%s\n" "$C_DESC" "$C_R"
        return
    fi

    # Column layout
    local col_width=32
    local num_cols=$(( (COLS - 2) / col_width ))
    [[ $num_cols -lt 1 ]] && num_cols=1
    local num_rows=$(( (total + num_cols - 1) / num_cols ))

    for ((row = 0; row < num_rows; row++)); do
        printf "  "
        for ((col = 0; col < num_cols; col++)); do
            local i=$((col * num_rows + row))
            if [[ $i -lt $total ]]; then
                local k="${keys[$i]}" t="${types[$i]}" d="${descs[$i]}"
                local prefix="" dc="$C_DESC"
                if [[ "$t" == "group" ]]; then
                    prefix="+"
                    dc="$C_GRP"
                fi
                d="${d:0:$((col_width - ${#k} - 4 - ${#prefix} - 1))}"
                local visible_len=$(( ${#k} + 4 + ${#prefix} + ${#d} ))
                local pad=$((col_width - visible_len))
                [[ $pad -lt 1 ]] && pad=1
                printf "%s%s%s  %s→%s %s%s%s%s" "$C_KEY" "$k" "$C_R" "$C_SEP" "$C_R" "$dc" "$prefix" "$d" "$C_R"
                printf '%*s' "$pad" ""
            fi
        done
        printf "\n"
    done

    # Footer
    printf "\n%s%s%s\n" "$C_SEP" "$SEP_LINE" "$C_R"
    if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
        printf "  %sesc  close    ⌫  back%s\n" "$C_SEP" "$C_R"
    else
        printf "  %sesc  close%s\n" "$C_SEP" "$C_R"
    fi
}

handle_key() {
    local keypress="$1"
    local i=0

    while IFS=$'\t' read -r key type desc command immediate; do
        if [[ "$key" == "$keypress" ]]; then
            case "$type" in
                group)
                    NAV_STACK+=("$i")
                    return 0
                    ;;
                action)
                    tmux send-keys -t "$PANE_ID" -l "$command"
                    if [[ "$immediate" == "true" ]]; then
                        tmux send-keys -t "$PANE_ID" Enter
                    fi
                    exit 0
                    ;;
                popup)
                    local pane_path
                    pane_path=$(tmux display-message -t "$PANE_ID" -p '#{pane_current_path}')
                    tmux run-shell -b "sleep 0.1 && tmux display-popup -E -h 80% -w 80% -d '$pane_path' '$command'"
                    exit 0
                    ;;
                key)
                    local tbl ks
                    read -r tbl ks <<< "$command"
                    [[ "$ks" == ";" ]] && ks='\;'
                    tmux run-shell -b "sleep 0.1; tmux switch-client -c $(printf '%q' "$CLIENT") -T $(printf '%q' "$tbl") && tmux send-keys -K -c $(printf '%q' "$CLIENT") $(printf '%q' "$ks")"
                    exit 0
                    ;;
                tmux)
                    case "$command" in
                        choose-*|command-prompt*|customize-mode*|copy-mode*)
                            tmux run-shell -b "sleep 0.1 && tmux $command"
                            ;;
                        *)
                            tmux $command
                            ;;
                    esac
                    exit 0
                    ;;
                script)
                    tmux run-shell "$command"
                    exit 0
                    ;;
            esac
        fi
        ((i++))
    done < <(get_current_items)
}

# Main loop
while true; do
    render_menu

    IFS= read -rsn1 keypress

    # Escape
    if [[ "$keypress" == $'\x1b' ]]; then
        read -rsn1 -t 0.1 seq1 || true
        if [[ -z "$seq1" ]]; then
            if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
                unset 'NAV_STACK[${#NAV_STACK[@]}-1]'
            else
                exit 0
            fi
        fi
        continue
    fi

    # Backspace
    if [[ "$keypress" == $'\x7f' || "$keypress" == $'\x08' ]]; then
        if [[ ${#NAV_STACK[@]} -gt 0 ]]; then
            unset 'NAV_STACK[${#NAV_STACK[@]}-1]'
        else
            exit 0
        fi
        continue
    fi

    # Regular key
    if [[ -n "$keypress" ]]; then
        case "$keypress" in
            ' ')    keypress=Space ;;
            $'\t')  keypress=Tab ;;
            [$'\x01'-$'\x1a'])
                printf -v n '%d' "'$keypress"
                printf -v keypress "C-\\x$(printf '%x' $((n + 96)))"
                ;;
        esac
        handle_key "$keypress"
    fi
done
