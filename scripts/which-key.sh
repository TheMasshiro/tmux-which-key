#!/usr/bin/env bash
# tmux-which-key - which-key popup for tmux
# Usage: which-key.sh --open --client <name> <pane_id>
#            Builds the menu, sizes a popup to fit it and opens it (what which-key.tmux binds).
#        which-key.sh [--config <path>] [--theme <name|path>] [--client <name>] <pane_id>
#            Runs the menu in the current terminal (inside the popup).

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE=""
PANE_ID=""
CLIENT=""
THEME=""
OPEN=""
REPLAY_TABLE=""
REPLAY_KEY=""

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
        --open)
            OPEN=1
            shift
            ;;
        --replay)
            REPLAY_TABLE="$2"
            REPLAY_KEY="$3"
            shift 3
            ;;
        *)
            PANE_ID="$1"
            shift
            ;;
    esac
done

if [[ -z "$PANE_ID" ]]; then
    echo "Usage: which-key.sh [--open] [--config <path>] [--theme <name|path>] [--client <name>] <pane_id>"
    exit 1
fi

# Errors go to the tmux status line: inside a popup or run-shell an echo would be lost or open a view
die() {
    echo "tmux-which-key: $1" >&2
    tmux display-message -l ${CLIENT:+-c "$CLIENT"} "tmux-which-key: $1"
    exit 1
}

[[ -z "$CLIENT" ]] && CLIENT=$(tmux display-message -p '#{client_name}')

# Replay mode: run the real binding once the popup has closed (started by the `key` action below).
# Its error, e.g. "can't find window: 3", is shown like tmux shows it for a typed key.
if [[ -n "$REPLAY_TABLE" ]]; then
    sleep 0.1
    [[ "$REPLAY_KEY" == ";" ]] && REPLAY_KEY='\;'   # a bare ; is tmux's command separator
    if ! out=$(tmux switch-client -c "$CLIENT" -T "$REPLAY_TABLE" 2>&1 && tmux send-keys -K -c "$CLIENT" "$REPLAY_KEY" 2>&1); then
        tmux switch-client -c "$CLIENT" -T root 2>/dev/null
        tmux display-message -l -c "$CLIENT" "${out:-$REPLAY_KEY failed}"
    fi
    exit 0
fi

command -v jq >/dev/null || die "jq is required but not installed"

get_tmux_option() {
    local value
    value=$(tmux show-option -gqv "$1")
    echo "${value:-$2}"
}

[[ -z "$THEME" ]] && THEME=$(get_tmux_option "@which-key-theme" "catppuccin-mocha")
[[ -z "$CONFIG_FILE" ]] && CONFIG_FILE=$(get_tmux_option "@which-key-config" "")
THEME="${THEME/#\~/$HOME}"
CONFIG_FILE="${CONFIG_FILE/#\~/$HOME}"

# Resolve config file: explicit/@which-key-config > XDG > user home > live tmux bindings (CONFIG_FILE stays empty)
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
# Labels come from a table of known commands, then a short `bind -N` note, then the command name.
build_from_tmux() {
    tmux list-keys -F $'#{key_table}\t#{key_string}\t#{key_note}\t#{key_command}' | jq -Rn '
        [inputs | split("\t") | {t: .[0], k: .[1], n: .[2], c: (.[3:] | join(" "))}]
        # keys the popup cannot read (arrows, Alt, Shift, ...) and send-prefix are left out
        | map(select((.k | test("^(M-|S-|C-M-|C-(Up|Down|Left|Right)$|(Up|Down|Left|Right|DC|PPage|NPage|Home|End|BTab)$)") | not) and .c != "send-prefix")) as $b
        | def cap: (.[:1] | ascii_upcase) + .[1:];
          def pretty: gsub("[-_]"; " ") | cap;
          def dir: {L: "left", R: "right", U: "up", D: "down"}[capture(" -(?<d>[LRUD])\\b").d];
          def name_of:
              .c as $c | .n as $n
              | if   $c | test("which-key") then "Which key"
                elif $c | test("source-file") then "Reload config"
                elif $c | test("^split-window.* -h\\b") then "Split vertical"
                elif $c | test("^split-window") then "Split horizontal"
                elif $c | test("^select-pane -[LRUD]\\b") then "Pane " + ($c | dir)
                elif $c | test("^select-pane -m") then "Mark pane"
                elif $c | test("^select-pane -M") then "Unmark pane"
                elif $c | test("select-pane -T") then "Pane title"
                elif $c | test("^resize-pane -Z") then "Zoom"
                elif $c | test("^resize-pane -[LRUD]\\b") then "Resize " + ($c | dir)
                elif $c | test("^resize-pane -x \"100%\" -y \"100%\"") then "Fill window"
                elif $c | test("^move-pane -P ") then ($c | capture("-P (?<x>[a-z-]+)").x | pretty)
                elif $c | test("^if-shell.*Move & Resize") then "Move + resize menu"
                elif $c | test("^if-shell.*Move") then "Move menu"
                elif $c | test("^if-shell.*pane_floating_flag.*join-pane") then "Toggle float"
                elif $c == "new-pane" then "Float pane"
                elif $c | test("^kill-pane|confirm-before.*kill-pane") then "Kill pane"
                elif $c | test("^last-pane") then "Last pane"
                elif $c | test("^break-pane") then "Break pane"
                elif $c | test("^join-pane") then "Join pane"
                elif $c | test("^swap-pane -U") then "Swap up"
                elif $c | test("^swap-pane -D") then "Swap down"
                elif $c | test("^swap-pane") then "Swap marked"
                elif $c | test("^display-panes") then "Pane numbers"
                elif $c | test("^respawn-pane") then "Respawn pane"
                elif $c | test("^select-window -t :=[0-9]+$") then "Window " + ($c | capture(":=(?<n>[0-9]+)").n)
                elif $c | test("select-window") then "Go to window"
                elif $c | test("^new-window") then "New window"
                elif $c | test("^next-window -a") then "Next alert"
                elif $c | test("^previous-window -a") then "Prev alert"
                elif $c | test("^next-window") then "Next window"
                elif $c | test("^previous-window") then "Prev window"
                elif $c | test("^last-window") then "Last window"
                elif $c | test("^rotate-window -D") then "Rotate reverse"
                elif $c | test("^rotate-window") then "Rotate panes"
                elif $c | test("^switch-client -p") then "Prev session"
                elif $c | test("^switch-client -n") then "Next session"
                elif $c | test("^switch-client -l") then "Last session"
                elif $c | test("^choose-tree.* -[A-Za-z]*s") then "Choose session"
                elif $c | test("^choose-tree.* -[A-Za-z]*w") then "Choose window"
                elif $c | test("^choose-tree") then "Choose tree"
                elif $c | test("^choose-client") then "Choose client"
                elif $c | test("^detach-client") then "Detach"
                elif $c | test("^suspend-client") then "Suspend"
                elif $c | test("^refresh-client") then "Refresh"
                elif $c | test("^display-menu.*window_index") then "Window menu"
                elif $c | test("^display-menu.*pane_index") then "Pane menu"
                elif $c | test("^select-layout -E") then "Spread evenly"
                elif $c | test("^select-layout ") then ($c | sub("^select-layout "; "") | pretty)
                elif $c | test("^next-layout") then "Next layout"
                elif $c | test("^copy-mode -u") then "Scroll up"
                elif $c | test("^copy-mode") then "Copy mode"
                elif $c | test("^paste-buffer") then "Paste"
                elif $c | test("^list-buffers") then "List buffers"
                elif $c | test("^delete-buffer") then "Delete buffer"
                elif $c | test("^choose-buffer") then "Choose buffer"
                elif $c | test("^command-prompt.*list-keys") then "Describe key"
                elif $c | test("^list-keys") then "List keys"
                elif $c | test("^command-prompt.*rename-(window|session)") then "Rename " + ($c | capture("rename-(?<x>window|session)").x)
                elif $c | test("^command-prompt.*move-window") then "Move window"
                elif $c | test("^command-prompt.*find-window") then "Find window"
                elif $c | test("^confirm-before.*kill-") then "Kill " + ($c | capture("kill-(?<x>[a-z]+)").x)
                elif $c | test("^command-prompt") then "Command prompt"
                elif $c | test("^display-message$") then "Info"
                elif $c | test("^clock-mode") then "Clock"
                elif $c | test("^show-messages") then "Messages"
                elif $c | test("^customize-mode") then "Options"
                elif $c | test("^send-keys ") then "Send " + ($c | split(" ")[1])
                elif $n != "" and ($n | length) <= 24 then $n
                elif $c | test("^run-shell") then ($c | capture("(?<x>[A-Za-z0-9_-]+)(\\.sh)?[\"\\x27 ]*$") // {x: "Run script"} | .x | pretty)
                else $c | split(" ")[0] | pretty end;
          def leaf: {key: .k, type: "key", description: name_of, command: (.t + " " + .k)};
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
               | [$p[] | select((is_table | not) and cat == $n) | leaf | .icon = $n] as $i
               | select($i | length > 0)
               | {key: $k, type: "group", description: ($n | cap), icon: $n, items: $i}]
              + [$p[] | select(is_table)
                 | (.c | sub("^switch-client -T "; "")) as $t
                 | {key: .k, type: "group", description: ($t | pretty), icon: $t,
                    items: [$b[] | select(.t == $t) | leaf | .icon = $t]}])}'
}

if [[ -n "${WK_CONFIG:-}" ]]; then
    CONFIG="$WK_CONFIG"
elif [[ -z "$CONFIG_FILE" ]]; then
    CONFIG=$(build_from_tmux)
elif [[ -f "$CONFIG_FILE" ]]; then
    CONFIG=$(cat "$CONFIG_FILE")
else
    die "config not found: $CONFIG_FILE"
fi
jq -e '.items | type == "array"' >/dev/null 2>&1 <<< "$CONFIG" || die "config has no valid items array: ${CONFIG_FILE:-live bindings}"

# Layout: up to MAX_COLS columns of "key → label", packed to the content
MAX_COLS=4
GAP=4
MAX_DESC=28

# Sets L_COLS/L_ROWS/L_WIDTH for n items with key width kw and label width dw within avail columns
layout() {
    local n=$1 kw=$2 dw=$(( $3 < MAX_DESC ? $3 : MAX_DESC )) avail=$4
    local cell=$((kw + 3 + ICON_W + dw))
    L_COLS=$(( n < MAX_COLS ? n : MAX_COLS ))
    while (( L_COLS > 1 && L_COLS * cell + (L_COLS - 1) * GAP > avail )); do ((L_COLS--)); done
    (( L_COLS < 1 )) && L_COLS=1
    L_ROWS=$(( (n + L_COLS - 1) / L_COLS ))
    L_WIDTH=$(( L_COLS * cell + (L_COLS - 1) * GAP ))
}

# Theme: a name in themes/ or a path to a file defining colors, popup bg, symbols and text
if [[ "$THEME" == */* ]]; then THEME_FILE="$THEME"; else THEME_FILE="$PLUGIN_DIR/themes/$THEME.sh"; fi
[[ -f "$THEME_FILE" ]] || die "theme not found: $THEME_FILE"
C_ICON=""
source "$THEME_FILE"
C_R=$'\033[0m'
ICONS=1
case "$(get_tmux_option "@which-key-icons" "on")" in
    off|0|no|false) ICONS=0 ;;
esac
ICON_W=$(( ICONS ? 2 : 0 ))   # icon glyph + space

# Sets IC/IC_COLOR for an item's icon field: a theme name (ICON_<name>/COLOR_<name>) or a literal glyph
icon_of() {
    IC="" IC_COLOR="$C_ICON"
    [[ "$1" == "-" ]] && return
    if [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]; then
        local i="ICON_$1" c="COLOR_$1"
        IC="${!i:-}"
        IC_COLOR="${!c:-$C_ICON}"
    else
        IC="$1"
    fi
}

# Open mode: size the popup to the biggest menu level, then run this script inside it
if [[ -n "$OPEN" ]]; then
    read -r cw ch < <(tmux display-message -p -c "$CLIENT" '#{client_width} #{client_height}')
    w=40 h=0   # 40 leaves room for the breadcrumb and footer
    while read -r n kw dw; do
        layout "$n" "$kw" "$dw" $((cw - 6))
        (( L_WIDTH + 6 > w )) && w=$((L_WIDTH + 6))
        (( L_ROWS + 2 > h )) && h=$((L_ROWS + 2))
    done < <(jq -r '[.items, (.. | objects | select(.type? == "group") | .items)][] | select(length > 0)
        | "\(length) \(map(.key | length) | max) \(map((.description | length) + (if .type == "group" then $g else 0 end)) | max)"' --argjson g "${#ICON_GROUP}" <<< "$CONFIG")
    (( w > cw )) && w=$cw
    (( h > ch )) && h=$ch
    (( h < 3 )) && h=3   # an empty menu still needs its border and hint
    tmux display-popup -E -B -c "$CLIENT" -t "$PANE_ID" \
        -w "$(get_tmux_option "@which-key-popup-width" "$w")" \
        -h "$(get_tmux_option "@which-key-popup-height" "$h")" \
        -x "$(get_tmux_option "@which-key-popup-x" "C")" \
        -y "$(get_tmux_option "@which-key-popup-y" "#{client_height}")" \
        -s "bg=$POPUP_BG" \
        -e "WK_CONFIG=$(jq -c . <<< "$CONFIG")" \
        "$(printf '%q ' "$PLUGIN_DIR/scripts/which-key.sh" --theme "$THEME" --client "$CLIENT" "$PANE_ID")"
    exit 0
fi

printf '\033[?25l\033[2J'
trap 'printf "\033[?25h"' EXIT

COLS=$(tput cols 2>/dev/null || echo 100)
ROWS=$(tput lines 2>/dev/null || echo 10)

# Navigation stack (jq path indices)
NAV_STACK=()

# Get current items as tab-separated lines: key\ttype\tdescription\tcommand\timmediate
# Single jq call per menu level instead of per-item
get_current_items() {
    local path=".items"
    for idx in "${NAV_STACK[@]}"; do
        path="${path}[${idx}].items"
    done
    echo "$CONFIG" | jq -r "${path}[] | [.key, .type, .description, (.icon // \"-\"), (.command // \"\"), (if .immediate then \"true\" else \"false\" end)] | map(tostring | gsub(\"\t\"; \" \")) | join(\"\t\")" 2>/dev/null
}

get_breadcrumb() {
    local path=".items"
    local out="$TITLE_ROOT"
    for idx in "${NAV_STACK[@]}"; do
        out+=" $ICON_SEP $ICON_GROUP$(echo "$CONFIG" | jq -r "${path}[${idx}].description")"
        path="${path}[${idx}].items"
    done
    echo "$out"
}

# Repeat a string n times
rep() { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }

render_menu() {
    local title
    title=$(get_breadcrumb)

    local keys=() types=() descs=() kw=1 dw=1
    local icons=()
    while IFS=$'\t' read -r key type desc icon _rest; do
        [[ "$type" == "group" ]] && desc="$ICON_GROUP$desc"
        keys+=("$key")
        types+=("$type")
        descs+=("$desc")
        icons+=("$icon")
        (( ${#key} > kw )) && kw=${#key}
        (( ${#desc} > dw )) && dw=${#desc}
    done < <(get_current_items)

    local total=${#keys[@]}
    local area=$((COLS - 6))                       # inside border + 2 spaces each side
    layout "$total" "$kw" "$dw" "$area"
    local num_cols=$L_COLS num_rows=$L_ROWS
    local box_rows=$(( ROWS - 2 > num_rows ? ROWS - 2 : num_rows ))   # fill the popup on smaller levels
    local col_w=$((area / num_cols))

    printf '\033[H'
    # Top border with the breadcrumb in it
    printf "%s%s%s %s%s%s %s%s%s\033[K\n" "$C_BORDER" "$BORDER_TL" "$BORDER_H" "$C_TITLE" "$title" "$C_BORDER" "$(rep "$BORDER_H" $((COLS - ${#title} - 5)))" "$BORDER_TR" "$C_R"

    local row col i
    for ((row = 0; row < box_rows; row++)); do
        if (( row >= num_rows )); then
            printf "%s%s%s%*s%s%s%s\033[K\n" "$C_BORDER" "$BORDER_V" "$C_R" $((COLS - 2)) "" "$C_BORDER" "$BORDER_V" "$C_R"
            continue
        fi
        printf "%s%s%s  " "$C_BORDER" "$BORDER_V" "$C_R"
        for ((col = 0; col < num_cols; col++)); do
            i=$((col * num_rows + row))
            if [[ $i -lt $total ]]; then
                local k="${keys[$i]}" d="${descs[$i]}" dc="$C_DESC"
                [[ "${types[$i]}" == "group" ]] && dc="$C_GRP"
                local maxd=$((col_w - kw - 4 - ICON_W))
                (( maxd > MAX_DESC )) && maxd=$MAX_DESC
                d="${d:0:$maxd}"
                printf "%s%*s%s %s%s%s " "$C_KEY" "$kw" "$k" "$C_R" "$C_ARROW" "$ICON_ARROW" "$C_R"
                if (( ICONS )); then
                    icon_of "${icons[$i]}"
                    printf "%s%-1s%s " "$IC_COLOR" "${IC:- }" "$C_R"
                fi
                printf "%s%s%s%*s" "$dc" "$d" "$C_R" $((col_w - kw - 3 - ICON_W - ${#d})) ""
            else
                printf "%*s" "$col_w" ""
            fi
        done
        printf "%*s  %s%s%s\033[K\n" $((area - num_cols * col_w)) "" "$C_BORDER" "$BORDER_V" "$C_R"
    done

    # Bottom border with the key hints centered in it
    local hint="$HINT_CLOSE"
    [[ ${#NAV_STACK[@]} -gt 0 ]] && hint+="  $HINT_BACK"
    local left=$(( (COLS - 4 - ${#hint}) / 2 ))
    printf "%s%s%s %s%s%s %s%s%s\033[J" "$C_BORDER" "$BORDER_BL" "$(rep "$BORDER_H" "$left")" "$C_FOOT" "$hint" "$C_BORDER" "$(rep "$BORDER_H" $((COLS - 4 - ${#hint} - left)))" "$BORDER_BR" "$C_R"
}

handle_key() {
    local keypress="$1"
    local i=0

    while IFS=$'\t' read -r key type desc _icon command immediate; do
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
                    local cmd
                    cmd=$(printf '%q ' "$PLUGIN_DIR/scripts/which-key.sh" --replay "$tbl" "$ks" --client "$CLIENT" "$PANE_ID")
                    tmux run-shell -b "${cmd//\#/##}"   # ## so run-shell does not expand # as a format
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
        # Drop the rest of an escape sequence (arrows, F-keys) so it is not read as menu keys
        [[ -n "$seq1" ]] && while read -rsn1 -t 0.01 _; do :; done
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
