#!/usr/bin/env bash
# HyprVision · Desinstalador
# Reverte tudo o que o install.sh fez: daemon, ecrã, ficheiros e source.
set -euo pipefail

DEST="$HOME/.config/hypr/hyprvision"
CONF="$HOME/.config/hypr/hyprvision.conf"
HYPR="$HOME/.config/hypr/hyprland.conf"

echo "── HyprVision · desinstalação ─────────────────────────"

if [[ -x "$DEST/bin/hyprvision" ]]; then
    "$DEST/bin/hyprvision" --daemon-stop  >/dev/null 2>&1 || true
    "$DEST/bin/hyprvision" --safe-reset   >/dev/null 2>&1 || true
    echo "✓ Daemon parado e ecrã reposto ao neutro"
fi

if [[ -f "$HYPR" ]] && grep -q "hyprvision.conf" "$HYPR"; then
    sed -i "\|hyprvision.conf|d" "$HYPR"
    echo "✓ source removido do hyprland.conf"
fi

HYPRLUA="$HOME/.config/hypr/hyprland.lua"
if [[ -f "$HYPRLUA" ]] && grep -q "hyprvision_lua" "$HYPRLUA"; then
    sed -i -e '/^-- HyprVision$/d' \
           -e '\|hyprvision/?\.lua|d' \
           -e '/require("hyprvision_lua")/d' "$HYPRLUA"
    echo "✓ require removido do hyprland.lua"
fi

rm -f "$CONF" && echo "✓ $CONF removido"
rm -rf "$DEST" && echo "✓ $DEST removido"

# Atalhos da sessão actual (ignora erros fora do Hyprland)
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null 2>&1 || true
    echo "✓ Sessão recarregada sem os keybinds"
fi

echo
echo "Pronto. Obrigado por usares o HyprVision."
