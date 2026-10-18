# Catppuccin Mocha theme for tmux-which-key.
# Copy this file, edit anything below, and set @which-key-theme to the copy's path.

# Colors: 24-bit ANSI foreground escapes, \033[38;2;R;G;Bm
C_KEY=$'\033[38;2;137;180;250m'       # #89B4FA blue     - key
C_ARROW=$'\033[38;2;108;112;134m'     # #6C7086 overlay0 - arrow between key and label
C_DESC=$'\033[38;2;249;226;175m'      # #F9E2AF yellow   - action label
C_GRP=$'\033[38;2;203;166;247m'       # #CBA6F7 mauve    - +group label
C_BORDER=$'\033[38;2;137;180;250m'    # #89B4FA blue     - box border
C_TITLE=$'\033[38;2;203;166;247m'     # #CBA6F7 mauve    - breadcrumb in the top border
C_FOOT=$'\033[38;2;147;153;178m'      # #9399B2 overlay2 - hints in the bottom border

# Popup background (tmux style color)
POPUP_BG="#181825"                    # mantle

# Symbols: each must be one terminal column wide
ICON_ARROW="→"
ICON_GROUP="+"
ICON_SEP="»"
BORDER_TL="╭" BORDER_TR="╮" BORDER_BL="╰" BORDER_BR="╯" BORDER_H="─" BORDER_V="│"

# Text
TITLE_ROOT="root"
HINT_CLOSE="esc close"
HINT_BACK="⌫ back"
