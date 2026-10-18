# tmux-which-key

A LazyVim-style which-key popup for tmux. Press a trigger key to open a discoverable, keyboard-driven command menu with nested groups, breadcrumb navigation, and Catppuccin Mocha themed colors.

> **Fork notice:** this is a fork of [Nucc/tmux-which-key](https://github.com/Nucc/tmux-which-key).
> The upstream menu is a static JSON file. This fork builds the menu from your live tmux key
> bindings (your `tmux.conf` and plugins), so what you see is what you have bound. Static JSON
> configs still work as an override.

![Catppuccin Mocha theme](https://img.shields.io/badge/theme-Catppuccin%20Mocha-CBA6F7?style=flat-square&labelColor=1E1E2E)
![tmux](https://img.shields.io/badge/tmux-3.4+-green?style=flat-square)

![tmux-which-key screenshot](docs/screenshot.png)

## Features

- **Dynamic keybindings** - the menu is read from your running tmux, so custom binds appear and run exactly as bound
- **Discoverable keybindings** - see all available commands at a glance
- **Nested groups** - organize commands hierarchically (git, window, session, etc.)
- **Breadcrumb navigation** - always know where you are in the menu tree
- **Themeable** - colors, popup background, icons, symbols and hint text live in one theme file (Catppuccin Mocha by default)
- **Icons** - Nerd Font icons per group, like nvim's which-key (on by default; `set -g @which-key-icons off` or `ICONS=0` in the theme turns them off)
- **Optional JSON configuration** - override the live menu with a static, hand-written one
- **Five action types** (static configs) - shell commands (with optional auto-execute), tmux commands, external scripts, popups, and nested groups
- **Single-keystroke input** - no Enter key required, instant response

## Requirements

- tmux >= 3.4 (for `display-popup`, `list-keys -F` and `send-keys -K`)
- `jq` (for JSON parsing)
- A terminal with true color (24-bit) support
- A [Nerd Font](https://www.nerdfonts.com/) for the icons (or set `ICONS=0` in the theme)

## Installation

### With [TPM](https://github.com/tmux-plugins/tpm) (recommended)

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'TheMasshiro/tmux-which-key'
```

Then press `prefix + I` to install.

### Manual

Clone the repository:

```bash
git clone https://github.com/TheMasshiro/tmux-which-key.git ~/.tmux/plugins/tmux-which-key
```

Add to your `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-which-key/which-key.tmux
```

Reload tmux:

```bash
tmux source-file ~/.tmux.conf
```

### Nix (with Flakes)

If you use Nix and Flakes, you can add this plugin to your [Home Manager](https://github.com/nix-community/home-manager) configuration.

1. Add to your `flake.nix` inputs:

```nix
{
  inputs.tmux-which-key.url = "github:TheMasshiro/tmux-which-key";
}
```

2. Add the package to `programs.tmux.plugins` in your configuration:

```nix
{ pkgs, inputs, ... }: {
  programs.tmux.plugins = [
    inputs.tmux-which-key.packages.${pkgs.system}.default
  ];
}
```

**Note:** Ensure `jq` is available in your system path, as it is required for JSON parsing.

## Usage

Press `prefix + Space` (default) to open the which-key popup.

- **Press a key** to execute the corresponding command or enter a group
- **Escape** to go back one level or close the menu
- **Backspace** to go back one level or close the menu

Keys are blue, actions rosewater, and groups are mauve with a `+` prefix. Pressing a group key opens its submenu with a breadcrumb showing your navigation path.

## Configuration

### Tmux Options

Set these in your `~/.tmux.conf` before loading the plugin:

| Option | Default | Description |
|--------|---------|-------------|
| `@which-key-trigger` | `Space` | Key binding (after prefix) to open the menu |
| `@which-key-config` | _(auto-detected)_ | Path to a custom JSON config file |
| `@which-key-theme` | `catppuccin-mocha` | Theme name in `themes/` or path to a theme file |
| `@which-key-icons` | _(theme's `ICONS`, on)_ | `on` / `off` to show or hide the Nerd Font icons |
| `@which-key-popup-height` | _(fits the menu)_ | Popup height in lines |
| `@which-key-popup-width` | _(fits the menu)_ | Popup width |
| `@which-key-popup-x` | `C` | Popup X position (`C` = centered) |
| `@which-key-popup-y` | `#{client_height}` | Popup Y position (`#{client_height}` = bottom of the client) |

Example:

```tmux
set -g @which-key-config '~/.config/tmux-which-key/config.json'
set -g @which-key-popup-height '20'
set -g @which-key-popup-width '120'
set -g @plugin 'TheMasshiro/tmux-which-key'
```

### Custom Key Binding

By default the plugin binds `prefix + Space`. You can override this with `@which-key-trigger`, or create your own binding entirely in `~/.tmux.conf`.

To bind `Ctrl-Space` directly (no prefix needed):

```tmux
# Disable the default prefix binding
set -g @which-key-trigger 'None'

# Bind Ctrl-Space directly (-n = no prefix)
bind-key -n C-Space run-shell "~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --open --client '#{client_name}' '#{pane_id}'"
```

The manual binding reads the same `@which-key-*` options (config, theme, popup size and position).

### Themes

Everything visual lives in a theme file. The default is `themes/catppuccin-mocha.sh`:

| Variable | What it styles |
|----------|----------------|
| `C_KEY`, `C_ARROW`, `C_DESC`, `C_GRP` | Key, arrow, action label, `+group` label |
| `C_BORDER`, `C_TITLE`, `C_FOOT` | Box border, breadcrumb, esc/back hints |
| `POPUP_BG` | Popup background (tmux color, e.g. `#181825`) |
| `ICON_ARROW`, `ICON_GROUP`, `ICON_SEP` | `→`, `+`, `»` |
| `BORDER_TL` `BORDER_TR` `BORDER_BL` `BORDER_BR` `BORDER_H` `BORDER_V` | Box corners and edges |
| `TITLE_ROOT`, `HINT_CLOSE`, `HINT_BACK` | `root`, `esc close`, `⌫ back` |
| `ICONS` | `1` shows a Nerd Font icon before each label, `0` hides the icon column |
| `ICON_<group>`, `COLOR_<group>` | Icon and color for a group and its actions (`pane`, `window`, `session`, `buffer`, `layout`, `misc`, or a key-table name like `move`) |
| `C_ICON` | Color for icons without a `COLOR_<group>` |

Colors are 24-bit ANSI escapes (`$'\033[38;2;R;G;Bm'`); symbols must be one column wide.
To customize, copy the file, edit it, and point the plugin at your copy:

```tmux
set -g @which-key-theme '~/.config/tmux-which-key/mytheme.sh'
```

A bare name (no `/`) loads `themes/<name>.sh` from the plugin.

### Custom Config File

The plugin looks for a config file in this order:

1. Path set via `@which-key-config` tmux option
2. `$XDG_CONFIG_HOME/tmux-which-key/config.json` (usually `~/.config/tmux-which-key/config.json`)
3. `~/.tmux-which-key.json`
4. Your live tmux key bindings (default)

With no config file, the menu is built from the `prefix` key table of the running tmux
server, so your own binds show up and run as bound. They are grouped by what they do:
`p` pane, `w` window, `s` session, `b` buffer, `l` layout, `m` misc (so split is `prefix Space p |`). A binding to `switch-client -T <table>`
becomes a group. Labels are plain words for known tmux commands ("Split vertical", "Kill pane");
for anything else a short `bind -N "note"` (up to 24 characters) is used, then the command name.
The popup is sized to the largest menu level, up to 4 columns. Needs tmux 3.4+.
`configs/default.json` is kept as an example static config.

To create your own config:

```bash
mkdir -p ~/.config/tmux-which-key
cp ~/.tmux/plugins/tmux-which-key/configs/default.json ~/.config/tmux-which-key/config.json
```

Then edit `~/.config/tmux-which-key/config.json` to your liking.

### Config File Format

The config file is a JSON object with a top-level `items` array. Each item has:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | yes | Single character that triggers this item |
| `type` | string | yes | One of: `group`, `action`, `tmux`, `script`, `popup` |
| `description` | string | yes | Label shown in the menu |
| `command` | string | for non-groups | Command to execute |
| `items` | array | for groups | Nested items in this group |
| `immediate` | boolean | no | For `action` type: also press Enter after pasting (default: `false`) |
| `icon` | string | no | Theme icon name (e.g. `pane`, reads `ICON_pane`) or a literal one-column glyph |

### Action Types

| Type | Behavior | Example |
|------|----------|---------|
| `group` | Opens a submenu with nested items | Navigate to git commands |
| `action` | Sends text to the active pane (as if typed). With `"immediate": true`, also presses Enter. | `git status` |
| `tmux` | Executes a tmux command directly | `split-window -h` |
| `script` | Runs a shell script via `tmux run-shell` | `~/scripts/my-script.sh` |
| `popup` | Opens command in a temporary `display-popup` at the pane's working directory. Closes on exit or Escape. | `lazygit` |

### Example Config

```json
{
  "items": [
    {
      "key": "g",
      "type": "group",
      "description": "git",
      "items": [
        { "key": "s", "type": "action", "command": "git status", "description": "Status", "immediate": true },
        { "key": "c", "type": "action", "command": "git commit", "description": "Commit" },
        { "key": "g", "type": "popup", "command": "lazygit", "description": "Lazygit" }
      ]
    },
    {
      "key": "w",
      "type": "group",
      "description": "window",
      "items": [
        { "key": "v", "type": "tmux", "command": "split-window -h -c '#{pane_current_path}'", "description": "Split vertical" },
        { "key": "s", "type": "tmux", "command": "split-window -v -c '#{pane_current_path}'", "description": "Split horizontal" }
      ]
    },
    { "key": "r", "type": "tmux", "command": "source-file ~/.tmux.conf \\; display-message 'Config reloaded'", "description": "Reload config" },
    { "key": "h", "type": "popup", "command": "htop", "description": "System monitor" },
    { "key": "d", "type": "script", "command": "~/scripts/deploy.sh", "description": "Deploy" }
  ]
}
```

## Default Keybindings

The built-in default config provides ~75 commands organized into 8 groups plus standalone items. Press `prefix + Space` to open the root menu:

### Root Menu

| Key | Type | Description |
|-----|------|-------------|
| `p` | group | **Pane** - split, navigate, zoom, swap, resize, and more |
| `w` | group | **Window** - create, kill, rename, find, navigate, move |
| `s` | group | **Session** - create, detach, choose, rename, kill, switch |
| `b` | group | **Buffer** - list, paste, choose, save/load, copy mode |
| `l` | group | **Layout** - cycle layouts and select presets |
| `C` | group | **Client** - list, choose, detach, refresh, lock |
| `o` | group | **Options** - show/set options, environment, messages |
| `g` | group | **Git** - status, diff, log, push, pull, branches, fetch, add, commit, rebase |
| `:` | tmux | Command prompt |
| `r` | tmux | Reload tmux config |
| `?` | tmux | List all keybindings |
| `c` | action | Clear screen |
| `t` | tmux | Clock mode |
| `d` | tmux | Display panes |

### Pane (`p`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `v` | Split vertical | `s` | Split horizontal |
| `h/j/k/l` | Navigate panes | `z` | Zoom toggle |
| `x` | Kill pane | `o` | Last pane |
| `!` | Break to window | `J` | Join pane |
| `m/M` | Mark/unmark pane | `{/}` | Swap up/down |
| `c` | Clear history | `q` | Capture to buffer |
| `p` | Respawn pane | `r` | **+Resize** (subgroup) |

### Window (`w`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `n` | New window | `x` | Kill window |
| `r` | Rename | `f` | Find window |
| `l` | Last window | `.` | Next window |
| `,` | Previous window | `w` | Choose window |
| `m` | Move window | `s` | Swap window |
| `R` | Rotate panes | | |

### Session (`s`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `n` | New session | `d` | Detach |
| `s` | Choose session | `w` | Choose tree |
| `r` | Rename | `k` | Kill session |
| `l` | List sessions | `L` | Lock session |
| `(` | Previous session | `)` | Next session |

### Buffer (`b`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `l` | List buffers | `p` | Paste |
| `c` | Choose buffer | `d` | Delete buffer |
| `s` | Save to file | `L` | Load from file |
| `v` | Show buffer | `y` | Copy mode |
| `C` | Capture pane | | |

### Layout (`l`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `n` | Next layout | `p` | Previous layout |
| `1` | Even horizontal | `2` | Even vertical |
| `3` | Main horizontal | `4` | Main vertical |
| `5` | Tiled | | |

### Client (`C`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `l` | List clients | `c` | Choose client |
| `d` | Detach | `D` | Detach other |
| `r` | Refresh | `s` | Suspend |
| `L` | Lock | | |

### Options (`o`)

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `g` | Show global options | `w` | Show window options |
| `e` | Show environment | `s` | Set global option |
| `c` | Customize mode | `m` | Show messages |
| `k` | List commands | | |

## License

MIT
