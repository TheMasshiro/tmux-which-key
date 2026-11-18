#!/usr/bin/env bash
# tmux-which-key - which-key popup for tmux
# Usage: which-key.sh --open --client <name> <pane_id>
#            Builds the menu, sizes a popup to fit it and opens it (what which-key.tmux binds).
#        WK_MENU=<menu> which-key.sh --theme <file> --icons <0|1> --size <cols> <rows> --client <name> <pane_id>
#            Runs the menu inside the popup.
# Kept light on purpose: opening is one tmux call and one awk pass, the popup spawns nothing until a key runs.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR/..

PLUGIN_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PANE_ID="" CLIENT="" THEME_FILE="" ICONS=1 COLS="" ROWS="" OPEN="" REPLAY_TABLE="" REPLAY_KEY=""
US=$'\037'   # field separator of the menu lines (see menu.awk)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --client) CLIENT="$2"; shift 2 ;;
        --theme)  THEME_FILE="$2"; shift 2 ;;
        --icons)  ICONS="$2"; shift 2 ;;
        --size)   COLS="$2" ROWS="$3"; shift 3 ;;
        --open)   OPEN=1; shift ;;
        --replay) REPLAY_TABLE="$2" REPLAY_KEY="$3"; shift 3 ;;
        *)        PANE_ID="$1"; shift ;;
    esac
done

if [[ -z "$PANE_ID" ]]; then
    echo "Usage: which-key.sh --open --client <name> <pane_id>"
    exit 1
fi

# Errors go to the tmux status line: inside a popup or run-shell an echo would be lost or open a view
die() {
    echo "tmux-which-key: $1" >&2
    tmux display-message -l ${CLIENT:+-c "$CLIENT"} "tmux-which-key: $1"
    exit 1
}

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

# Open mode: build the menu, size the popup to its biggest level, then run this script inside it
if [[ -n "$OPEN" ]]; then
    declare -A OPT=()
    MENU=""
    while IFS= read -r line; do
        if [[ "$line" == S"$US"* ]]; then
            line=${line#S"$US"}
            OPT[${line%%"$US"*}]=${line#*"$US"}
        else
            MENU+=${line#M"$US"}$'\n'
        fi
    done < <(tmux display-message -p -c "$CLIENT" $'D\t#{client_width}\t#{client_height}' \; \
                  list-keys -F $'K\t#{key_table}\t#{key_string}\t#{key_repeat}\t#{key_note}\t#{key_command}' \; \
                  show-options -g | awk -f "$PLUGIN_DIR/scripts/menu.awk")
    [[ -n "${OPT[client_width]:-}" ]] || die "could not read the tmux bindings"
    # Settings removed in the jq-free rewrite (the check reads the dump, so it costs nothing otherwise)
    if [[ -n "${OPT[config]:-}" || "${OPT[extras]:-}" == *.json ]]; then
        tmux display-message -c "$CLIENT" -d 5000 \
            "tmux-which-key: @which-key-config and JSON extras were removed; see the README (Your Own Keys)"
    fi

    theme=${OPT[theme]:-catppuccin-mocha}
    theme=${theme/#\~/$HOME}
    if [[ "$theme" == */* ]]; then THEME_FILE="$theme"; else THEME_FILE="$PLUGIN_DIR/themes/$theme.sh"; fi
    [[ -f "$THEME_FILE" ]] || die "theme not found: $THEME_FILE"
    # shellcheck source=themes/catppuccin-mocha.sh
    source "$THEME_FILE"
    case "${OPT[icons]:-on}" in off|0|no|false) ICONS=0 ;; esac
    ICON_W=$(( ICONS ? 2 : 0 ))   # icon glyph + space

    # Per level: item count, widest key, widest label
    declare -A n=() kw=() dw=()
    while IFS="$US" read -r parent key type label _; do
        [[ "$type" == group ]] && label="$ICON_GROUP$label"
        p="_$parent"
        (( n[$p] = ${n[$p]:-0} + 1 ))
        (( ${#key} > ${kw[$p]:-0} )) && kw[$p]=${#key}
        (( ${#label} > ${dw[$p]:-0} )) && dw[$p]=${#label}
    done <<< "${MENU%$'\n'}"
    cw=${OPT[client_width]} ch=${OPT[client_height]}
    w=40 h=0   # 40 leaves room for the breadcrumb and footer
    for p in "${!n[@]}"; do
        layout "${n[$p]}" "${kw[$p]}" "${dw[$p]}" $((cw - 6))
        (( L_WIDTH + 6 > w )) && w=$((L_WIDTH + 6))
        (( L_ROWS + 2 > h )) && h=$((L_ROWS + 2))
    done
    (( w > cw )) && w=$cw
    (( h > ch )) && h=$ch
    (( h < 3 )) && h=3   # an empty menu still needs its border and hint
    pw=${OPT[popup-width]:-$w} ph=${OPT[popup-height]:-$h}
    # The menu draws to the popup size; for a size like 80% it asks the terminal instead
    size=()
    [[ "$pw$ph" =~ ^[0-9]+$ ]] && size=(--size "$pw" "$ph")

    tmux display-popup -E -B -c "$CLIENT" -t "$PANE_ID" -w "$pw" -h "$ph" \
        -x "${OPT[popup-x]:-C}" -y "${OPT[popup-y]:-#{client_height}}" \
        -s "bg=$POPUP_BG" -e "WK_MENU=$MENU" \
        "$(printf '%q ' "$PLUGIN_DIR/scripts/which-key.sh" --theme "$THEME_FILE" --icons "$ICONS" "${size[@]}" --client "$CLIENT" "$PANE_ID")"
    exit 0
fi

# Popup mode: everything below runs without starting a process until a key runs something
[[ -f "$THEME_FILE" ]] || die "theme not found: $THEME_FILE"
C_ICON=""
# shellcheck source=themes/catppuccin-mocha.sh
source "$THEME_FILE"
C_R=$'\033[0m'
ICON_W=$(( ICONS ? 2 : 0 ))
[[ -z "$COLS" ]] && read -r ROWS COLS < <(stty size)

# Menu items as parallel arrays
M_PARENT=() M_KEY=() M_TYPE=() M_LABEL=() M_ICON=() M_CMD=()
while IFS="$US" read -r parent key type label icon cmd; do
    M_PARENT+=("$parent") M_KEY+=("$key") M_TYPE+=("$type") M_LABEL+=("$label") M_ICON+=("$icon") M_CMD+=("$cmd")
done <<< "${WK_MENU%$'\n'}"

CUR=""        # key of the open group, "" at the root
CUR_LABEL=""

printf '\033[?25l\033[2J'
trap 'printf "\033[?25h"' EXIT

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

# Repeat a string n times
rep() { local s; printf -v s '%*s' "$2" ''; printf -v REP '%s' "${s// /$1}"; }

render_menu() {
    local title="$TITLE_ROOT"
    [[ -n "$CUR" ]] && title+=" $ICON_SEP $ICON_GROUP$CUR_LABEL"

    local idx=() kw=1 dw=1 i d
    for i in "${!M_KEY[@]}"; do
        [[ "${M_PARENT[$i]}" == "$CUR" ]] || continue
        idx+=("$i")
        d="${M_LABEL[$i]}"
        [[ "${M_TYPE[$i]}" == group ]] && d="$ICON_GROUP$d"
        (( ${#M_KEY[$i]} > kw )) && kw=${#M_KEY[$i]}
        (( ${#d} > dw )) && dw=${#d}
    done

    local total=${#idx[@]}
    local area=$((COLS - 6))                       # inside border + 2 spaces each side
    layout "$total" "$kw" "$dw" "$area"
    local num_cols=$L_COLS num_rows=$L_ROWS
    local box_rows=$(( ROWS - 2 > num_rows ? ROWS - 2 : num_rows ))   # fill the popup on smaller levels
    local col_w=$((area / num_cols))
    local maxd=$((col_w - kw - 4 - ICON_W))
    (( maxd > MAX_DESC )) && maxd=$MAX_DESC

    local out
    # Top border with the breadcrumb in it
    rep "$BORDER_H" $((COLS - ${#title} - 5))
    printf -v out "\033[H%s%s%s %s%s%s %s%s%s\033[K\n" "$C_BORDER" "$BORDER_TL" "$BORDER_H" "$C_TITLE" "$title" "$C_BORDER" "$REP" "$BORDER_TR" "$C_R"

    local row col n k dc
    for ((row = 0; row < box_rows; row++)); do
        if (( row >= num_rows )); then
            printf -v out "%s%s%s%s%*s%s%s%s\033[K\n" "$out" "$C_BORDER" "$BORDER_V" "$C_R" $((COLS - 2)) "" "$C_BORDER" "$BORDER_V" "$C_R"
            continue
        fi
        out+="$C_BORDER$BORDER_V$C_R  "
        for ((col = 0; col < num_cols; col++)); do
            n=$((col * num_rows + row))
            if (( n < total )); then
                i=${idx[$n]}
                k="${M_KEY[$i]}" d="${M_LABEL[$i]}" dc="$C_DESC"
                [[ "${M_TYPE[$i]}" == group ]] && d="$ICON_GROUP$d" dc="$C_GRP"
                d="${d:0:$maxd}"
                printf -v out "%s%s%*s%s %s%s%s " "$out" "$C_KEY" "$kw" "$k" "$C_R" "$C_ARROW" "$ICON_ARROW" "$C_R"
                if (( ICONS )); then
                    icon_of "${M_ICON[$i]}"
                    printf -v out "%s%s%-1s%s " "$out" "$IC_COLOR" "${IC:- }" "$C_R"
                fi
                printf -v out "%s%s%s%s%*s" "$out" "$dc" "$d" "$C_R" $((col_w - kw - 3 - ICON_W - ${#d})) ""
            else
                printf -v out "%s%*s" "$out" "$col_w" ""
            fi
        done
        printf -v out "%s%*s  %s%s%s\033[K\n" "$out" $((area - num_cols * col_w)) "" "$C_BORDER" "$BORDER_V" "$C_R"
    done

    # Bottom border with the key hints centered in it
    local hint="$HINT_CLOSE"
    [[ -n "$CUR" ]] && hint+="  $HINT_BACK"
    local left=$(( (COLS - 4 - ${#hint}) / 2 )) lrep
    rep "$BORDER_H" "$left"; lrep=$REP
    rep "$BORDER_H" $((COLS - 4 - ${#hint} - left))
    printf -v out "%s%s%s%s %s%s%s %s%s%s\033[J" "$out" "$C_BORDER" "$BORDER_BL" "$lrep" "$C_FOOT" "$hint" "$C_BORDER" "$REP" "$BORDER_BR" "$C_R"
    printf '%s' "$out"   # one write per frame
}

# Quotes a string as one sh word, with # doubled so run-shell does not expand it as a format
sh_arg() { local s="'${1//\'/\'\\\'\'}'"; printf '%s' "${s//\#/##}"; }

# Runs a tmux command string through tmux's own parser, so quotes, braces and ; work as in tmux.conf.
# An error shows in the status line, like one from a typed key.
run_tmux() {
    local out
    out=$(printf '%s\n' "$1" | tmux source-file - 2>&1) || tmux display-message -l -c "$CLIENT" "$out"
}

handle_key() {
    local i command
    for i in "${!M_KEY[@]}"; do
        [[ "${M_PARENT[$i]}" == "$CUR" && "${M_KEY[$i]}" == "$1" ]] || continue
        command="${M_CMD[$i]}"
        case "${M_TYPE[$i]}" in
            group)
                CUR="${M_KEY[$i]}" CUR_LABEL="${M_LABEL[$i]}"
                return 0
                ;;
            repeat)
                # bind -r: run it now and stay open, so the key can be pressed again
                run_tmux "$command"
                return 0
                ;;
            action)
                tmux send-keys -t "$PANE_ID" -l "$command" \; send-keys -t "$PANE_ID" Enter
                ;;
            popup)
                local pane_path
                pane_path=$(tmux display-message -t "$PANE_ID" -p '#{pane_current_path}')
                tmux run-shell -b "sleep 0.1 && tmux display-popup -E -h 80% -w 80% -d $(sh_arg "$pane_path") $(sh_arg "$command")"
                ;;
            key)
                local tbl ks
                read -r tbl ks <<< "$command"
                tmux run-shell -b "$(sh_arg "$PLUGIN_DIR/scripts/which-key.sh") --replay $(sh_arg "$tbl") $(sh_arg "$ks") --client $(sh_arg "$CLIENT") $(sh_arg "$PANE_ID")"
                ;;
            tmux)
                case "$command" in
                    choose-*|command-prompt*|customize-mode*|copy-mode*)
                        # these need the popup gone first
                        tmux run-shell -b "sleep 0.1 && printf '%s\n' $(sh_arg "$command") | tmux source-file -"
                        ;;
                    *)
                        run_tmux "$command"
                        ;;
                esac
                ;;
            script)
                tmux run-shell "$command"
                ;;
        esac
        exit 0
    done
}

# Main loop
while true; do
    render_menu

    IFS= read -rsn1 keypress || exit 0

    # Escape
    if [[ "$keypress" == $'\x1b' ]]; then
        read -rsn1 -t 0.1 seq1 || true
        # Drop the rest of an escape sequence (arrows, F-keys) so it is not read as menu keys
        [[ -n "$seq1" ]] && while read -rsn1 -t 0.01 _; do :; done
        if [[ -z "$seq1" ]]; then
            [[ -n "$CUR" ]] || exit 0
            CUR=""
        fi
        continue
    fi

    # Backspace
    if [[ "$keypress" == $'\x7f' || "$keypress" == $'\x08' ]]; then
        [[ -n "$CUR" ]] || exit 0
        CUR=""
        continue
    fi

    # Regular key
    if [[ -n "$keypress" ]]; then
        case "$keypress" in
            ' ')    keypress=Space ;;
            $'\t')  keypress=Tab ;;
            [$'\x01'-$'\x1a'])
                printf -v n '%d' "'$keypress"
                printf -v hex '%x' $((n + 96))
                printf -v keypress 'C-%b' "\\x$hex"
                ;;
        esac
        handle_key "$keypress"
    fi
done
