# tmux-which-key menu builder (POSIX awk). Fed one tmux dump by which-key.sh:
#   D<TAB>client_width<TAB>client_height
#   K<TAB>table<TAB>key<TAB>repeat<TAB>note<TAB>command   one per binding (list-keys)
#   @name value                                    global options (show-options -g)
# Prints, fields separated by \037:
#   S name value                                   a setting (@which-key-<name>, client size)
#   M parent key type label icon command           a menu item; parent is "" at the root
#
# A binding is type key (command "<table> <key>", replayed once the popup closes) or,
# when bound with -r, type repeat (command is the tmux command; the popup stays open).
#
# Live menu: prefix bindings grouped by the tmux command family they run (pane, window, ...);
# a `switch-client -T <table>` binding becomes a group listing that table.
# Then the tmux.conf entries apply (the git group ships as such entries, configs/git.conf):
#   @which-key-group-<k> 'Name'          group k: new, or renames a live group ('none' removes)
#   @which-key-<g>-<k>   'Label : cmd'   entry k in group g ('none' removes)
#   @which-key-root-<k>  'Label : cmd'   top-level entry k ('none' removes)
# A key-table group whose key a tmux.conf group takes moves to a free key.

BEGIN { FS = "\t"; SEP = "\037"; nb = 0; ngo = 0; nent = 0; nroot = 0 }

/^D\t/ { print "S" SEP "client_width" SEP $2; print "S" SEP "client_height" SEP $3; next }

/^K\t/ {
    c = $6
    for (i = 7; i <= NF; i++) c = c " " $i
    # keys the popup cannot read (arrows, Alt, Shift, ...) and send-prefix are left out
    if ($3 ~ /^(M-|S-|C-M-|C-(Up|Down|Left|Right)$|(Up|Down|Left|Right|DC|PPage|NPage|Home|End|BTab)$)/ || c == "send-prefix") next
    nb++; bt[nb] = $2; bk[nb] = $3; br[nb] = $4; bn[nb] = $5; bc[nb] = c
    next
}

/^@which-key-/ {
    sp = index($0, " ")
    if (!sp) next
    name = substr($0, 12, sp - 12)
    v = unquote(substr($0, sp + 1))
    gsub(/[\t\n]/, " ", v)
    if (name ~ /^group-./)     { ngo++; gok[ngo] = substr(name, 7); gov[ngo] = v }
    else if (name ~ /^root-./) { nroot++; rok[nroot] = substr(name, 6); rov[nroot] = v }
    else if (name ~ /^.-./)    { nent++; eg[nent] = substr(name, 1, 1); ek[nent] = substr(name, 3); ev[nent] = v }
    else print "S" SEP name SEP v
}

# show-options quotes values: '' when empty, "..." with \-escapes, or bare
function unquote(s,   q, out, i, ch) {
    q = substr(s, 1, 1)
    if (q == "'") return substr(s, 2, length(s) - 2)
    if (q != "\"") { if (substr(s, 1, 1) == "\\") s = substr(s, 2); return s }
    s = substr(s, 2, length(s) - 2); out = ""
    for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (ch == "\\") { i++; ch = substr(s, i, 1) }
        out = out ch
    }
    return out
}

function cap(s) { return toupper(substr(s, 1, 1)) substr(s, 2) }
function pretty(s) { gsub(/[-_]/, " ", s); return cap(s) }
function word(s, n,   a) { split(s, a, " "); return a[n] }
function dir(c,   d) {
    if (!match(c, / -[LRUD]( |$)/)) return ""
    d = substr(c, RSTART + 2, 1)
    return d == "L" ? "left" : d == "R" ? "right" : d == "U" ? "up" : "down"
}
function after(c, re, skip) { match(c, re); return substr(c, RSTART + skip, RLENGTH - skip) }

# Label: known commands first, then a short `bind -N` note, then the command name
function name_of(c, n,   s) {
    if (c ~ /which-key/) return "Which key"
    if (c ~ /source-file/) return "Reload config"
    if (c ~ /^split-window.* -h( |$)/) return "Split vertical"
    if (c ~ /^split-window/) return "Split horizontal"
    if (c ~ /^select-pane -[LRUD]( |$)/) return "Pane " dir(c)
    if (c ~ /^select-pane -m/) return "Mark pane"
    if (c ~ /^select-pane -M/) return "Unmark pane"
    if (c ~ /select-pane -T/) return "Pane title"
    if (c ~ /^resize-pane -Z/) return "Zoom"
    if (c ~ /^resize-pane -[LRUD]( |$)/) return "Resize " dir(c)
    if (c ~ /^resize-pane -x "100%" -y "100%"/) return "Fill window"
    if (c ~ /^move-pane -P /) return pretty(after(c, "-P [a-z-]+", 3))
    if (c ~ /^if-shell.*Move & Resize/) return "Move + resize menu"
    if (c ~ /^if-shell.*Move/) return "Move menu"
    if (c ~ /^if-shell.*pane_floating_flag.*join-pane/) return "Toggle float"
    if (c == "new-pane") return "Float pane"
    if (c ~ /^kill-pane|confirm-before.*kill-pane/) return "Kill pane"
    if (c ~ /^last-pane/) return "Last pane"
    if (c ~ /^break-pane/) return "Break pane"
    if (c ~ /^join-pane/) return "Join pane"
    if (c ~ /^swap-pane -U/) return "Swap up"
    if (c ~ /^swap-pane -D/) return "Swap down"
    if (c ~ /^swap-pane/) return "Swap marked"
    if (c ~ /^display-panes/) return "Pane numbers"
    if (c ~ /^respawn-pane/) return "Respawn pane"
    if (c ~ /^select-window -t :=[0-9]+$/) return "Window " after(c, ":=[0-9]+", 2)
    if (c ~ /select-window/) return "Go to window"
    if (c ~ /^new-window/) return "New window"
    if (c ~ /^next-window -a/) return "Next alert"
    if (c ~ /^previous-window -a/) return "Prev alert"
    if (c ~ /^next-window/) return "Next window"
    if (c ~ /^previous-window/) return "Prev window"
    if (c ~ /^last-window/) return "Last window"
    if (c ~ /^rotate-window -D/) return "Rotate reverse"
    if (c ~ /^rotate-window/) return "Rotate panes"
    if (c ~ /^switch-client -p/) return "Prev session"
    if (c ~ /^switch-client -n/) return "Next session"
    if (c ~ /^switch-client -l/) return "Last session"
    if (c ~ /^choose-tree.* -[A-Za-z]*s/) return "Choose session"
    if (c ~ /^choose-tree.* -[A-Za-z]*w/) return "Choose window"
    if (c ~ /^choose-tree/) return "Choose tree"
    if (c ~ /^choose-client/) return "Choose client"
    if (c ~ /^detach-client/) return "Detach"
    if (c ~ /^suspend-client/) return "Suspend"
    if (c ~ /^refresh-client/) return "Refresh"
    if (c ~ /^display-menu.*window_index/) return "Window menu"
    if (c ~ /^display-menu.*pane_index/) return "Pane menu"
    if (c ~ /^select-layout -E/) return "Spread evenly"
    if (c ~ /^select-layout /) { s = c; sub(/^select-layout /, "", s); return pretty(s) }
    if (c ~ /^next-layout/) return "Next layout"
    if (c ~ /^copy-mode -u/) return "Scroll up"
    if (c ~ /^copy-mode/) return "Copy mode"
    if (c ~ /^paste-buffer/) return "Paste"
    if (c ~ /^list-buffers/) return "List buffers"
    if (c ~ /^delete-buffer/) return "Delete buffer"
    if (c ~ /^choose-buffer/) return "Choose buffer"
    if (c ~ /^command-prompt.*list-keys/) return "Describe key"
    if (c ~ /^list-keys/) return "List keys"
    if (c ~ /^command-prompt.*rename-(window|session)/) return "Rename " after(c, "rename-(window|session)", 7)
    if (c ~ /^command-prompt.*move-window/) return "Move window"
    if (c ~ /^command-prompt.*find-window/) return "Find window"
    if (c ~ /^confirm-before.*kill-/) return "Kill " after(c, "kill-[a-z]+", 5)
    if (c ~ /^command-prompt/) return "Command prompt"
    if (c ~ /^display-message$/) return "Info"
    if (c ~ /^clock-mode/) return "Clock"
    if (c ~ /^show-messages/) return "Messages"
    if (c ~ /^customize-mode/) return "Options"
    if (c ~ /^send-keys /) return "Send " word(c, 2)
    if (n != "" && length(n) <= 24) return n
    if (c ~ /^run-shell/) {
        if (!match(c, /[A-Za-z0-9_-]+(\.sh)?["' ]*$/)) return "Run script"
        s = substr(c, RSTART, RLENGTH); sub(/["' ]*$/, "", s); sub(/\.sh$/, "", s)
        return pretty(s)
    }
    return pretty(word(c, 1))
}

# Group of a binding: its first word, or the whole command for wrappers.
# Add a family here if one lands in misc.
function family(c,   x) {
    x = word(c, 1)
    if (x == "confirm-before" || x == "command-prompt" || x == "if-shell") x = c
    if (x ~ /pane|split-window|clear-history/) return "pane"
    if (x ~ /window|rotate/) return "window"
    if (x ~ /session|client|choose-tree/) return "session"
    if (x ~ /buffer|copy-mode/) return "buffer"
    if (x ~ /layout/) return "layout"
    return "misc"
}

# Sort order for tmux.conf keys: a A b B ... (show-options lists them A-Z then a-z)
function order(k) { return tolower(k) (k ~ /^[A-Z]$/ ? "1" : "0") }

# Insertion sort of index list idx[1..n] by order(keys[idx[i]])
function sort_idx(idx, n, keys,   i, j, t) {
    for (i = 2; i <= n; i++) {
        t = idx[i]
        for (j = i - 1; j >= 1 && order(keys[idx[j]]) > order(keys[t]); j--) idx[j + 1] = idx[j]
        idx[j + 1] = t
    }
}

# Root items: rk/rt/rl/ri/rc[r]; group r's items: ck/ct/cl/ci/cc[r, j], j <= cn[r]
function add_root(k, t, l, ic, c) { nr++; rk[nr] = k; rt[nr] = t; rl[nr] = l; ri[nr] = ic; rc[nr] = c; cn[nr] = 0; return nr }
function add_child(r, k, t, l, ic, c,   j) { j = ++cn[r]; ck[r, j] = k; ct[r, j] = t; cl[r, j] = l; ci[r, j] = ic; cc[r, j] = c }
function add_binding(r, i, ic) {
    if (br[i] == "1") add_child(r, bk[i], "repeat", name_of(bc[i], bn[i]), ic, bc[i])
    else add_child(r, bk[i], "key", name_of(bc[i], bn[i]), ic, bt[i] " " bk[i])
}
function find_root(k,   r) { for (r = 1; r <= nr; r++) if (rk[r] == k) return r; return 0 }

# Parses 'Label : command'; the command is typed into the pane unless prefixed tmux:, popup: or run:
function parse_entry(v) {
    if (match(v, /[ \t]+:[ \t]+/)) { E_LABEL = substr(v, 1, RSTART - 1); v = substr(v, RSTART + RLENGTH) }
    else { E_LABEL = v; v = "" }
    E_TYPE = "action"; E_CMD = v
    if (match(v, /^(tmux|popup|run):[ \t]*/)) {
        E_TYPE = substr(v, 1, index(v, ":") - 1)
        if (E_TYPE == "run") E_TYPE = "script"
        E_CMD = substr(v, RSTART + RLENGTH)
    }
}

function set_root(k, v,   r, j) {
    r = find_root(k)
    if (v == "none") { if (r) remove_root(r); return }
    parse_entry(v)
    if (!r) { add_root(k, E_TYPE, E_LABEL, "-", E_CMD); return }
    rt[r] = E_TYPE; rl[r] = E_LABEL; ri[r] = "-"; rc[r] = E_CMD; cn[r] = 0
}

function remove_root(r,   j, q) {
    for (; r < nr; r++) {
        rk[r] = rk[r + 1]; rt[r] = rt[r + 1]; rl[r] = rl[r + 1]; ri[r] = ri[r + 1]; rc[r] = rc[r + 1]; cn[r] = cn[r + 1]
        for (j = 1; j <= cn[r]; j++) { ck[r, j] = ck[r + 1, j]; ct[r, j] = ct[r + 1, j]; cl[r, j] = cl[r + 1, j]; ci[r, j] = ci[r + 1, j]; cc[r, j] = cc[r + 1, j] }
    }
    nr--
}

function set_child(r, k, v,   j, n) {
    n = cn[r]
    for (j = 1; j <= n && ck[r, j] != k; j++) ;
    if (v == "none") {
        if (j > n) return
        for (; j < n; j++) { ck[r, j] = ck[r, j + 1]; ct[r, j] = ct[r, j + 1]; cl[r, j] = cl[r, j + 1]; ci[r, j] = ci[r, j + 1]; cc[r, j] = cc[r, j + 1] }
        cn[r]--
        return
    }
    parse_entry(v)
    if (j > n) cn[r] = j
    ck[r, j] = k; ct[r, j] = E_TYPE; cl[r, j] = E_LABEL; ci[r, j] = ri[r]; cc[r, j] = E_CMD
}

function free_key(k, label,   c, i, all) {
    all = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    if (!(k in taken)) return k
    c = tolower(substr(label, 1, 1)); if (c != "" && !(c in taken)) return c
    c = toupper(c); if (c != "" && !(c in taken)) return c
    for (i = 1; i <= length(all); i++) { c = substr(all, i, 1); if (!(c in taken)) return c }
    return k
}

END {
    # live family groups, in this order with these keys
    split("pane window session buffer layout misc", fam, " ")
    split("p w s b l m", famkey, " ")
    for (f = 1; f <= 6; f++) famof[fam[f]] = f
    for (i = 1; i <= nb; i++) {
        if (bt[i] != "prefix" || bc[i] ~ /^switch-client -T /) continue
        f = famof[family(bc[i])]
        nfi[f]++; fi[f, nfi[f]] = i
    }
    for (f = 1; f <= 6; f++) if (nfi[f]) livefam[famkey[f]] = f

    # tmux.conf groups: rename a live family group, or claim the key as a new group
    for (g = 1; g <= ngo; g++) gidx[g] = g
    sort_idx(gidx, ngo, gok)
    for (g = 1; g <= ngo; g++) {
        k = gok[gidx[g]]; v = gov[gidx[g]]
        if (v == "none") { removed[k] = 1; continue }
        if (k in livefam) { rename[k] = v; continue }
        if (k in taken) continue
        taken[k] = 1
        add_root(k, "group", v, tolower(v), "")
    }

    for (f = 1; f <= 6; f++) {
        if (!nfi[f]) continue
        k = famkey[f]; taken[k] = 1
        r = add_root(k, "group", (k in rename) ? rename[k] : cap(fam[f]), fam[f], "")
        for (j = 1; j <= nfi[f]; j++) add_binding(r, fi[f, j], fam[f])
    }

    # key tables reached with switch-client -T
    for (i = 1; i <= nb; i++) {
        if (bt[i] != "prefix" || bc[i] !~ /^switch-client -T /) continue
        t = bc[i]; sub(/^switch-client -T /, "", t)
        label = pretty(t)
        k = free_key(bk[i], label); taken[k] = 1
        r = add_root(k, "group", label, t, "")
        for (j = 1; j <= nb; j++) if (bt[j] == t) add_binding(r, j, t)
    }

    for (k in removed) if (r = find_root(k)) remove_root(r)

    for (e = 1; e <= nent; e++) { eidx[e] = e; ekey[e] = eg[e] ek[e] }
    sort_idx(eidx, nent, ekey)
    for (e = 1; e <= nent; e++) {
        x = eidx[e]
        if ((r = find_root(eg[x])) && rt[r] == "group") set_child(r, ek[x], ev[x])
    }

    for (e = 1; e <= nroot; e++) ridx[e] = e
    sort_idx(ridx, nroot, rok)
    for (e = 1; e <= nroot; e++) set_root(rok[ridx[e]], rov[ridx[e]])

    for (r = 1; r <= nr; r++) print "M" SEP "" SEP rk[r] SEP rt[r] SEP rl[r] SEP ri[r] SEP rc[r]
    for (r = 1; r <= nr; r++)
        for (j = 1; j <= cn[r]; j++) print "M" SEP rk[r] SEP ck[r, j] SEP ct[r, j] SEP cl[r, j] SEP ci[r, j] SEP cc[r, j]
}
