#!/usr/bin/env bash
# HyprVision 5 · Instalador (Hyprland ≥ 0.55 com config hyprland.lua)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/hypr/hyprvision"
HYPRLUA="$HOME/.config/hypr/hyprland.lua"

echo "── HyprVision 5 · instalação ──"
[[ -f "$HYPRLUA" ]] || {
    echo "✗ $HYPRLUA não existe. O v5 requer config Lua (parser non-legacy)."
    echo "  Para hyprland.conf clássico usa a v4 (branch main)."
    exit 1
}
command -v rofi &>/dev/null || echo "⚠  rofi em falta (menu não funcionará)"
command -v wl-gammarelay-rs &>/dev/null || \
    echo "⚠  wl-gammarelay-rs em falta (temperatura/brightness desactivados)"

# daemon v4 ainda a correr? pára-o
pkill -f hyprvision-daemon 2>/dev/null || true

mkdir -p "$DEST"
rsync -a --delete \
    --exclude 'state/' --exclude '.git/' --exclude 'docs/' \
    --exclude 'install.sh' --exclude 'uninstall.sh' \
    --exclude 'test_hyprvision.lua' --exclude 'README.md' --exclude 'CHANGELOG.md' \
    --filter 'protect config.lua' \
    "$SRC"/ "$DEST"/
chmod +x "$DEST/ui/launcher.sh"
[[ -f "$DEST/config.lua" ]] || cp "$SRC/config.lua" "$DEST/config.lua"
echo "✓ Ficheiros em $DEST (config.lua e state/ preservados)"

# remove qualquer bloco HyprVision anterior (v4 ou v5) e recria — idempotente;
# apagar só o require v4 deixaria o package.path antigo a enganar checks de grep
sed -i -e '/hyprvision/d' -e '/^-- HyprVision/d' -e '/require("init")/d' "$HYPRLUA"
cat >> "$HYPRLUA" <<'LUA'
-- HyprVision 5
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/hyprvision/?.lua"
require("init")
LUA
echo "✓ require garantido no hyprland.lua"

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null && echo "✓ Hyprland recarregado — HyprVision activo"
fi
echo "── Pronto. Menu: SUPER+H · Reset: SUPER+SHIFT+H ──"
