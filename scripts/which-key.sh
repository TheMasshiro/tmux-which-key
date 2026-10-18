#!/usr/bin/env bash
# tmux-which-key - LazyVim-style which-key popup for tmux
# Usage: which-key.sh [--config <path>] [--theme <name|path>] [--client <name>] <pane_id>

set -uo pipefail
printf '\033[?25l\033[2J'
trap 'printf "\033[?25h"' EXIT

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE=""
PANE_ID=""
CLIENT=""
THEME="catppuccin-mocha"

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
        --theme)
            THEME="$2"
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
# Labels are derived from the command (short on purpose); `bind -N` notes are ignored.
build_from_tmux() {
    tmux list-keys -F $'#{key_table}\t#{key_string}\t#{key_note}\t#{key_command}' | jq -Rn '
        [inputs | split("\t") | {t: .[0], k: .[1], c: (.[3:] | join(" "))}]
        # keys the popup cannot read (arrows, Alt, Shift, ...) and send-prefix are left out
        | map(select((.k | test("^(M-|S-|C-M-|C-(Up|Down|Left|Right)$|(Up|Down|Left|Right|DC|PPage|NPage|Home|End|BTab)$)") | not) and .c != "send-prefix")) as $b
        | def strip: sub("-(panes?|windows?|sessions?|clients?|buffers?|layouts?|mode)$"; "");
          def short:
              (.c | split(" ")) as $t
              | $t[0] as $w
              | if ($w | IN("confirm-before", "command-prompt", "if-shell")) then
                    (.c | capture("(?<x>(kill|rename|move|swap|join|select|break|new|respawn|choose)-[a-z]+)") // {x: $w}) | .x | strip
                elif $w == "source-file" then "reload"
                elif (.c | test("^select-window -t :=[0-9]$")) then "go " + .c[-1:]
                elif $w == "run-shell" then
                    if (.c | test("which-key")) then "which-key"
                    else (.c | capture("(?<x>[A-Za-z0-9_-]+)(\\.sh)?[\"\\u0027 ]*$") // {x: "run"}) | .x end
                else
                    ([$t[1:][] | .] ) as $a
                    | (reduce $a[] as $x ({o: [], d: false};
                          if .d or (($x | test("^-?[A-Za-z0-9:=+-]{1,12}$")) | not) then .d = true else .o += [$x] end)
                       | .o) as $ok
                    | (if ($ok | length) > 0 and ($ok | length) < ($a | length) and ($ok[-1] | test("^-[cptIFTxXyYdESsn]$"))
                       then $ok[:-1] else $ok end)[:2] as $args
                    | ([$w | strip] + $args) | join(" ")
                end;
          def leaf: {key: .k, type: "key", description: short, command: (.t + " " + .k)};
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
                 | {key: .k, type: "group", description: $t,
                    items: [$b[] | select(.t == $t) | leaf]}])}'
}

# Theme: a name in themes/ or a path to a file defining the C_* colors
if [[ "$THEME" == */* ]]; then THEME_FILE="$THEME"; else THEME_FILE="$PLUGIN_DIR/themes/$THEME.sh"; fi
if [[ ! -f "$THEME_FILE" ]]; then
    echo "Theme not found: $THEME_FILE"
    exit 1
fi
source "$THEME_FILE"
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
    local out="root"
    for idx in "${NAV_STACK[@]}"; do
        out+=" » +$(echo "$CONFIG" | jq -r "${path}[${idx}].description")"
        path="${path}[${idx}].items"
    done
    echo "$out"
}

# Repeat a string n times
rep() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

render_menu() {
    local title
    title=$(get_breadcrumb)

    local keys=() types=() descs=() kw=1
    while IFS=$'\t' read -r key type desc _cmd; do
        keys+=("$key")
        types+=("$type")
        descs+=("$desc")
        [[ ${#key} -gt $kw ]] && kw=${#key}
    done < <(get_current_items)

    local total=${#keys[@]}
    local area=$((COLS - 6))                       # inside border + 2 spaces each side
    local num_cols=4
    [[ $((area / num_cols)) -lt 22 ]] && num_cols=$((area / 22))
    [[ $num_cols -lt 1 ]] && num_cols=1
    local col_w=$((area / num_cols))
    local num_rows=$(( (total + num_cols - 1) / num_cols ))

    printf '\033[H'
    # Top border with the breadcrumb in it
    printf "%s╭─ %s%s%s %s╮%s\033[K\n" "$C_BORDER" "$C_TITLE" "$title" "$C_BORDER" "$(rep ─ $((COLS - ${#title} - 5)))" "$C_R"
    printf "%s│%s%*s%s│%s\033[K\n" "$C_BORDER" "$C_R" $((COLS - 2)) "" "$C_BORDER" "$C_R"

    local row col i
    for ((row = 0; row < num_rows; row++)); do
        printf "%s│%s  " "$C_BORDER" "$C_R"
        for ((col = 0; col < num_cols; col++)); do
            i=$((col * num_rows + row))
            if [[ $i -lt $total ]]; then
                local k="${keys[$i]}" d="${descs[$i]}" dc="$C_DESC"
                if [[ "${types[$i]}" == "group" ]]; then
                    d="+$d"
                    dc="$C_GRP"
                fi
                local maxd=$((col_w - kw - 4))
                d="${d:0:$maxd}"
                printf "%s%*s%s %s→%s %s%s%s%*s" "$C_KEY" "$kw" "$k" "$C_R" "$C_ARROW" "$C_R" "$dc" "$d" "$C_R" $((maxd - ${#d} + 1)) ""
            else
                printf "%*s" "$col_w" ""
            fi
        done
        printf "%*s  %s│%s\033[K\n" $((area - num_cols * col_w)) "" "$C_BORDER" "$C_R"
    done

    printf "%s│%s%*s%s│%s\033[K\n" "$C_BORDER" "$C_R" $((COLS - 2)) "" "$C_BORDER" "$C_R"
    # Footer hints, centered
    local hint="esc close"
    [[ ${#NAV_STACK[@]} -gt 0 ]] && hint+="   ⌫ back"
    local lpad=$(( (COLS - 2 - ${#hint}) / 2 ))
    printf "%s│%s%*s%s%s%*s%s│%s\033[K\n" "$C_BORDER" "$C_R" "$lpad" "" "$C_FOOT" "$hint" $((COLS - 2 - lpad - ${#hint})) "" "$C_BORDER" "$C_R"
    printf "%s╰%s╯%s\033[J" "$C_BORDER" "$(rep ─ $((COLS - 2)))" "$C_R"
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
