#!/usr/bin/env bash
# HyprVision · Desinstalador — reverte o install.sh: ecrã neutro,
# ficheiros removidos e require retirado do hyprland.lua.
set -euo pipefail

DEST="$HOME/.config/hypr/hyprvision"
HYPRLUA="$HOME/.config/hypr/hyprland.lua"

echo "── HyprVision · desinstalação ──"
pkill -f hyprvision-daemon 2>/dev/null || true   # resto de v4, se houver

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl eval "hv.safe_reset()" >/dev/null 2>&1 || true
    echo "✓ Ecrã reposto ao neutro"
fi

WIREFILE="$HYPRLUA"
[[ -f "$HOME/.config/hypr/user.lua" ]] && WIREFILE="$HOME/.config/hypr/user.lua"

if [[ -f "$HYPRLUA" ]]; then
    sed -i -e '/hyprvision/d' -e '/^-- HyprVision/d' -e '/require("init")/d' "$HYPRLUA"
    echo "✓ require removido do hyprland.lua"
fi
if [[ -f "$WIREFILE" && "$WIREFILE" != "$HYPRLUA" ]]; then
    sed -i -e '/-- HyprVision >>>/,/-- HyprVision <<</d' "$WIREFILE"
    echo "✓ require removido do user.lua"
fi

# ponte de cor tonal: retira o bloco que o install.sh acrescentou
NOCTALIA_CONF="$HOME/.config/noctalia/config.toml"
if [[ -f "$NOCTALIA_CONF" ]] && grep -q "theme.templates.user.hyprvision" "$NOCTALIA_CONF"; then
    sed -i '/\[theme\.templates\.user\.hyprvision\]/,/^\s*output_path = .*noctalia-colors\.rasi"$/d' "$NOCTALIA_CONF"
    echo "✓ ponte de cor tonal removida do Noctalia"
fi
# A layerrule "rofi-glass" em windowrules.lua fica: o namespace é partilhado
# com o Hypr.AI e removê-la aqui tiraria o vidro do outro launcher também.

rm -rf "$DEST"
rm -rf "${XDG_RUNTIME_DIR:-/tmp}/hyprvision"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/hyprvision"
echo "✓ $DEST removido"
echo "── Feito. \`hyprctl reload\` para largar os binds desta sessão. ──"
