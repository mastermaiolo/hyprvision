#!/usr/bin/env bash
# HyprVision 5 · Desinstalador — reverte o install.sh: ecrã neutro,
# ficheiros removidos e require retirado do hyprland.lua.
set -euo pipefail

DEST="$HOME/.config/hypr/hyprvision"
HYPRLUA="$HOME/.config/hypr/hyprland.lua"

echo "── HyprVision 5 · desinstalação ──"
pkill -f hyprvision-daemon 2>/dev/null || true   # resto de v4, se houver

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl eval "hv.safe_reset()" >/dev/null 2>&1 || true
    echo "✓ Ecrã reposto ao neutro"
fi

if [[ -f "$HYPRLUA" ]]; then
    sed -i '/hyprvision/d' "$HYPRLUA"
    sed -i '/^-- HyprVision 5$/d' "$HYPRLUA"
    echo "✓ require removido do hyprland.lua"
fi

rm -rf "$DEST"
rm -rf "${XDG_RUNTIME_DIR:-/tmp}/hyprvision"
echo "✓ $DEST removido"
echo "── Feito. `hyprctl reload` para largar os binds desta sessão. ──"
