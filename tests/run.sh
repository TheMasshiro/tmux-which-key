#!/usr/bin/env bash
# Tests tmux-which-key against tests/fixture.dump (no tmux needed).
# Usage: tests/run.sh                  with awk from PATH
#        AWK='busybox awk' tests/run.sh
#        UPDATE=1 tests/run.sh         rewrite the expected files from the current output
set -uo pipefail
cd "$(dirname "$0")" || exit
AWK=${AWK:-awk}
fail=0

check() {   # name expected-file actual-output
    if [[ -n "${UPDATE:-}" ]]; then
        printf '%s\n' "$3" > "$2"
        echo "updated $2"
    elif diff -u "$2" - <<< "$3"; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        fail=1
    fi
}

# Menu: the dump through menu.awk, fields shown as |
menu=$($AWK -f ../scripts/menu.awk fixture.dump)
check "menu ($AWK)" expected.menu "$(tr '\037' '|' <<< "$menu")"

# Popup: root, then group p, then back (backspace) and end of input, drawn at 100x12
items=$(grep '^M' <<< "$menu" | sed 's/^M'$'\037''//')
frames=$(printf 'p\177' | WK_MENU="$items" bash ../scripts/which-key.sh \
    --theme ../themes/catppuccin-mocha.sh --icons 1 --size 100 12 --client test %0 2>&1)
check "popup (bash ${BASH_VERSION%%(*})" expected.popup "$(cat -v <<< "$frames")"

exit "$fail"
