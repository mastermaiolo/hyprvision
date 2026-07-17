#!/usr/bin/env bash
# HyprVision · Launcher Rofi
# Lê o estado de state/state (o `hyprctl eval` não devolve output — o
# ficheiro é a interface de leitura) e envia acções via hyprctl eval.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
STATE="$BASE_DIR/state/state"
MENU_IDX="$BASE_DIR/state/profiles.menu"
ROFI_THEME="$BASE_DIR/rofi/hyprvision.rasi"

sv() {   # valor de uma chave do estado (default $2)
    local v=""
    [[ -f "$STATE" ]] && v=$(grep -m1 "^$1=" "$STATE" | cut -d= -f2-) || true
    echo "${v:-${2:-}}"
}

hv() {   # invoca a superfície Lua
    hyprctl eval "hv.$1" >/dev/null
}

PROFILE=$(sv profile reset); EXTRA=$(sv extra); PAPER=$(sv paper off); DIM=$(sv dim 0)
STATUS="◈ ${EXTRA:-$PROFILE}"
[[ "$PAPER" != "off" ]] && STATUS="$STATUS  📄$PAPER"
[[ "$DIM" != "0" ]] && STATUS="$STATUS  🔅$DIM%"

rofi_menu() { rofi -dmenu -p "$1" -theme "$ROFI_THEME" -no-custom -markup-rows -format s; }
pick_id()   { grep -o '\[[^]]*\]' | tail -1 | tr -d '[]'; }
dim_row()   { printf '%s   <span alpha="30%%" size="small">[%s]</span>\n' "$1" "$2"; }
sep()       { printf '<span alpha="55%%" style="italic">──  %s  ──</span>\n' "$1"; }

main_rows() {
    local last_cat="" id icon name cat mark
    while IFS=$'\t' read -r id icon name cat; do
        if [[ "$cat" != "$last_cat" ]]; then
            case "$cat" in
                correction) sep "🔧 CORRECTION" ;;
                experience) sep "🎭 EXPERIENCE" ;;
                system)     sep "⚙️  SYSTEM" ;;
                *)          sep "$cat" ;;
            esac
            last_cat="$cat"
        fi
        mark=""; [[ "$id" == "$PROFILE" && -z "$EXTRA" ]] && mark="  ✓"
        dim_row "$icon $name$mark" "$id"
    done < "$MENU_IDX"

    sep "🧩 OVERLAYS · EXTRAS"
    local pm=""; [[ "$PAPER" != "off" ]] && pm="  ✓"
    dim_row "📄 Paper Texture: $PAPER  ▸$pm" "__paper__"
    local dm=""; [[ "$DIM" != "0" ]] && dm="  ✓"
    dim_row "🔅 Extra Dim: ${DIM}%  ▸$dm" "__dim__"
    local em=""; [[ -n "$EXTRA" ]] && em="  ✓"
    dim_row "🌐 Shaders extra${EXTRA:+: $EXTRA}  ▸$em" "__extras__"
    [[ -f "$STATE.bak" ]] && dim_row "↩ Recuperar último estado" "__recover__"
    dim_row "📝 Editar configuração" "__config__"
}

back_row() { dim_row "↩ Voltar" "__back__"; }

choice=$(main_rows | rofi_menu "$STATUS") || exit 0
[[ -z "$choice" ]] && exit 0
[[ "$choice" == *"──"* ]] && exec "$0"
ID=$(echo "$choice" | pick_id)
# `if`, nunca `[[ ]] &&` no fim de bloco: regressão set -e da v4.1.0
if [[ -z "$ID" ]]; then exec "$0"; fi

case "$ID" in
    __paper__)
        SEL=$({ back_row
                for lvl in off light medium heavy; do
                    mark=""; [[ "$lvl" == "$PAPER" ]] && mark="  ✓"
                    dim_row "📄 $lvl$mark" "$lvl"
                done; } | rofi_menu "📄 Paper Texture" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('paper', '$SEL')"
        ;;
    __dim__)
        SEL=$({ back_row
                for lvl in 0 10 20 30 40 50; do
                    mark=""; [[ "$lvl" == "$DIM" ]] && mark="  ✓"
                    dim_row "🔅 $lvl%$mark" "$lvl"
                done; } | rofi_menu "🔅 Extra Dim" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('dim', $SEL)"
        ;;
    __extras__)
        EXTRAS_DIR="$BASE_DIR/shaders/extras"
        mapfile -t EXTRAS < <(find "$EXTRAS_DIR" \( -name "*.glsl" -o -name "*.frag" \) \
            -printf "%f\n" 2>/dev/null | sort)
        if ((${#EXTRAS[@]} == 0)); then
            rofi -e "Pasta extras vazia.\n\nColoca .glsl em:\n$EXTRAS_DIR" \
                -theme "$ROFI_THEME" || true
            exit 0
        fi
        SEL=$({ back_row
                for f in "${EXTRAS[@]}"; do
                    mark=""; [[ "$f" == "$EXTRA" ]] && mark="  ✓"
                    dim_row "🌐 ${f%.*}$mark" "$f"
                done; } | rofi_menu "🌐 Shaders extra" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "apply_extra('$SEL')"
        ;;
    __recover__)
        hv "restore_backup()"
        ;;
    __config__)
        CONFIG="$BASE_DIR/config.lua"
        EDITOR_CMD=""
        for ed in "${VISUAL:-}" "${EDITOR:-}" code gedit kate nano; do
            if [[ -n "$ed" ]] && command -v "${ed%% *}" &>/dev/null; then
                EDITOR_CMD="$ed"; break
            fi
        done
        if [[ -z "$EDITOR_CMD" ]]; then
            xdg-open "$CONFIG" 2>/dev/null || \
                notify-send -a HyprVision "Config" "Edita manualmente: $CONFIG"
        else
            case "${EDITOR_CMD%% *}" in
                code|gedit|kate) $EDITOR_CMD "$CONFIG" & disown ;;
                *)
                    TERM_CMD=""
                    for t in foot kitty alacritty wezterm ghostty konsole xterm; do
                        command -v "$t" &>/dev/null && { TERM_CMD="$t"; break; }
                    done
                    if [[ -n "$TERM_CMD" ]]; then
                        $TERM_CMD -e $EDITOR_CMD "$CONFIG" & disown
                    else
                        xdg-open "$CONFIG" 2>/dev/null || true
                    fi ;;
            esac
        fi
        notify-send -a HyprVision "Config" "Após guardar: hyprctl reload"
        ;;
    *)
        hv "apply('$ID')"
        ;;
esac
