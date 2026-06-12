#!/usr/bin/env bash
# HyprVision v4 · Instalador
# Instala em ~/.config/hypr/hyprvision e liga ao hyprland.conf.
# Idempotente: correr de novo actualiza a instalação sem perder o estado.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/hypr/hyprvision"
CONF="$HOME/.config/hypr/hyprvision.conf"
HYPR="$HOME/.config/hypr/hyprland.conf"

echo "── HyprVision v4 · instalação ─────────────────────────"

# Dependências
missing=()
command -v python3  &>/dev/null || missing+=("python3 (≥3.11)")
command -v hyprctl  &>/dev/null || missing+=("hyprland")
command -v rofi     &>/dev/null || missing+=("rofi")
if ((${#missing[@]})); then
    echo "✗ Dependências em falta: ${missing[*]}"
    exit 1
fi
command -v busctl &>/dev/null && busctl --user introspect rs.wl-gammarelay / &>/dev/null \
    || echo "⚠  wl-gammarelay-rs não detectado — gamma/brightness usarão hyprsunset/wlsunset (só temperatura)."

# Ficheiros
mkdir -p "$DEST"
rsync -a \
    --exclude 'state/' --exclude '.git/' --exclude '__pycache__/' \
    --exclude 'install.sh' --exclude 'README.md' --exclude 'CHANGELOG.md' \
    --exclude 'daemon_config.example.toml' --exclude 'hyprvision.conf.example' \
    "$SRC"/ "$DEST"/
chmod +x "$DEST"/bin/* "$DEST"/ui/launcher.sh
echo "✓ Ficheiros em $DEST"

# Config do daemon (completa o TOML sem tocar nos keybinds existentes)
"$DEST/bin/hyprvision" --init-config >/dev/null
echo "✓ daemon_config.toml"

# hyprvision.conf (não sobrescreve um existente — pode ter binds do utilizador)
if [[ ! -f "$CONF" ]]; then
    sed "s|@INSTALL@|$DEST|g" "$SRC/hyprvision.conf.example" > "$CONF"
    echo "✓ $CONF criado (keybinds: Super+H menu, Super+Shift+H reset)"
else
    echo "• $CONF já existe — mantido"
fi

# source no hyprland.conf
if [[ -f "$HYPR" ]] && ! grep -q "hyprvision.conf" "$HYPR"; then
    printf '\nsource = %s\n' "$CONF" >> "$HYPR"
    echo "✓ source adicionado ao hyprland.conf"
fi

# Arranque imediato se estamos dentro do Hyprland
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    "$DEST/bin/hyprvision" --daemon-stop  >/dev/null 2>&1 || true
    "$DEST/bin/hyprvision" --daemon-start >/dev/null
    hyprctl keyword bind "SUPER, H, exec, $DEST/ui/launcher.sh" >/dev/null
    hyprctl keyword bind "SUPER SHIFT, H, exec, $DEST/bin/hyprvision --safe-reset" >/dev/null
    echo "✓ Daemon a correr e atalhos activos nesta sessão"
fi

echo
echo "Pronto. Super+H abre o menu · Super+Shift+H repõe o ecrã neutro."
echo "Para escolher outro atalho: $DEST/bin/hyprvision-setup --force"
