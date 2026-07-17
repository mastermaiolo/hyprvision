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

# ── i18n: config.lua (language=) força; senão, locale do sistema ────────
LANG_CFG="$(grep -m1 '^\s*language\s*=' "$BASE_DIR/config.lua" 2>/dev/null \
            | sed -E 's/.*=\s*"([^"]*)".*/\1/' || true)"
case "$LANG_CFG" in
    en|pt|zh) L="$LANG_CFG" ;;
    *)
        case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in
            zh*) L=zh ;;
            pt*) L=pt ;;
            *)   L=en ;;
        esac
        ;;
esac
declare -A T=(
    [en:cat_correction]="CORRECTION"          [pt:cat_correction]="CORREÇÃO"           [zh:cat_correction]="校正"
    [en:cat_experience]="EXPERIENCE"          [pt:cat_experience]="EXPERIÊNCIA"        [zh:cat_experience]="体验"
    [en:cat_system]="SYSTEM"                  [pt:cat_system]="SISTEMA"                [zh:cat_system]="系统"
    [en:overlays]="OVERLAYS & EXTRAS"         [pt:overlays]="OVERLAYS E EXTRAS"        [zh:overlays]="叠加层与附加效果"
    [en:paper_texture]="Paper Texture"        [pt:paper_texture]="Textura de Papel"    [zh:paper_texture]="纸质纹理"
    [en:extra_dim]="Extra Dim"                [pt:extra_dim]="Escurecimento Extra"     [zh:extra_dim]="额外调暗"
    [en:extra_shaders]="Extra Shaders"        [pt:extra_shaders]="Shaders Extra"       [zh:extra_shaders]="额外着色器"
    [en:recover]="Recover last state"         [pt:recover]="Recuperar último estado"   [zh:recover]="恢复上一个状态"
    [en:edit_config]="Edit configuration"     [pt:edit_config]="Editar configuração"   [zh:edit_config]="编辑配置"
    [en:back]="Back"                          [pt:back]="Voltar"                       [zh:back]="返回"
    [en:extras_empty]="Extras folder is empty.\n\nPut .glsl files in:\n%s"
    [pt:extras_empty]="Pasta extras vazia.\n\nColoca .glsl em:\n%s"
    [zh:extras_empty]="额外资源文件夹是空的。\n\n把 .glsl 文件放到:\n%s"
    [en:config_title]="Config"                [pt:config_title]="Configuração"         [zh:config_title]="配置"
    [en:config_manual]="Edit manually: %s"    [pt:config_manual]="Edita manualmente: %s" [zh:config_manual]="请手动编辑: %s"
    [en:config_saved]="After saving: hyprctl reload" [pt:config_saved]="Após guardar: hyprctl reload" [zh:config_saved]="保存后执行: hyprctl reload"
)
t() { printf -- "${T[$L:$1]}" "${2:-}"; }

PROFILE=$(sv profile reset); EXTRA=$(sv extra); PAPER=$(sv paper off); DIM=$(sv dim 0)
STATUS="◈ ${EXTRA:-$PROFILE}"
[[ "$PAPER" != "off" ]] && STATUS="$STATUS  📄$PAPER"
[[ "$DIM" != "0" ]] && STATUS="$STATUS  🔅$DIM%"

# ── cor tonal actual (Caelestia): sobrepõe a paleta estática do .rasi ────
SCHEME_JSON="$HOME/.local/state/caelestia/scheme.json"

scheme_color() {   # $1=campo do scheme.json → hex de 6 dígitos, ou nada se não existir
    [[ -f "$SCHEME_JSON" ]] || return
    sed -n "s/.*\"$1\": *\"\([0-9a-fA-F]\{6\}\)\".*/\1/p" "$SCHEME_JSON" | head -1
}

dynamic_theme() {   # bloco -theme-str com as cores do esquema actual, ou "" se não houver Caelestia
    local primary; primary="$(scheme_color primary)"
    [[ -n "$primary" ]] || return
    local background surf_hi surf on_bg on_surf_var outline_var on_primary error
    background="$(scheme_color background)"
    surf_hi="$(scheme_color surfaceContainerHigh)"
    surf="$(scheme_color surfaceContainer)"
    on_bg="$(scheme_color onBackground)"
    on_surf_var="$(scheme_color onSurfaceVariant)"
    outline_var="$(scheme_color outlineVariant)"
    on_primary="$(scheme_color onPrimary)"
    error="$(scheme_color error)"
    cat <<RASI
* {
    bg0: #${background}F2; bg1: #${surf_hi}; bg2: #${surf}80; bg3: #${primary}F2;
    fg0: #${on_bg}; fg2: #${on_surf_var}; fg3: #${outline_var}; sep: #${outline_var};
}
window { border-color: #${primary}33; }
element.selected.normal, element.selected.active { text-color: #${on_primary}; }
error-message { border-color: #${error}F2; }
RASI
}

rofi_menu() {
    local dyn=(); local d; d="$(dynamic_theme)"
    [[ -n "$d" ]] && dyn=(-theme-str "$d")
    rofi -dmenu -p "$1" -theme "$ROFI_THEME" "${dyn[@]}" -no-custom -markup-rows -format s
}
pick_id()   { grep -o '\[[^]]*\]' | tail -1 | tr -d '[]'; }
dim_row()   { printf '%s   <span alpha="30%%" size="small">[%s]</span>\n' "$1" "$2"; }
sep()       { printf '<span alpha="55%%" style="italic">──  %s  ──</span>\n' "$1"; }

main_rows() {
    local last_cat="" id icon name cat mark
    while IFS=$'\t' read -r id icon name cat; do
        if [[ "$cat" != "$last_cat" ]]; then
            case "$cat" in
                correction) sep "🔧 $(t cat_correction)" ;;
                experience) sep "🎭 $(t cat_experience)" ;;
                system)     sep "⚙️  $(t cat_system)" ;;
                *)          sep "$cat" ;;
            esac
            last_cat="$cat"
        fi
        mark=""; [[ "$id" == "$PROFILE" && -z "$EXTRA" ]] && mark="  ✓"
        dim_row "$icon $name$mark" "$id"
    done < "$MENU_IDX"

    sep "🧩 $(t overlays)"
    local pm=""; [[ "$PAPER" != "off" ]] && pm="  ✓"
    dim_row "📄 $(t paper_texture): $PAPER  ▸$pm" "__paper__"
    local dm=""; [[ "$DIM" != "0" ]] && dm="  ✓"
    dim_row "🔅 $(t extra_dim): ${DIM}%  ▸$dm" "__dim__"
    local em=""; [[ -n "$EXTRA" ]] && em="  ✓"
    dim_row "🌐 $(t extra_shaders)${EXTRA:+: $EXTRA}  ▸$em" "__extras__"
    [[ -f "$STATE.bak" ]] && dim_row "↩ $(t recover)" "__recover__"
    dim_row "📝 $(t edit_config)" "__config__"
}

back_row() { dim_row "↩ $(t back)" "__back__"; }

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
                done; } | rofi_menu "📄 $(t paper_texture)" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('paper', '$SEL')"
        ;;
    __dim__)
        SEL=$({ back_row
                for lvl in 0 10 20 30 40 50; do
                    mark=""; [[ "$lvl" == "$DIM" ]] && mark="  ✓"
                    dim_row "🔅 $lvl%$mark" "$lvl"
                done; } | rofi_menu "🔅 $(t extra_dim)" | pick_id) || true
        [[ -z "${SEL:-}" ]] && exit 0
        if [[ "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('dim', $SEL)"
        ;;
    __extras__)
        EXTRAS_DIR="$BASE_DIR/shaders/extras"
        mapfile -t EXTRAS < <(find "$EXTRAS_DIR" \( -name "*.glsl" -o -name "*.frag" \) \
            -printf "%f\n" 2>/dev/null | sort)
        if ((${#EXTRAS[@]} == 0)); then
            dyn=(); d="$(dynamic_theme)"; [[ -n "$d" ]] && dyn=(-theme-str "$d")
            rofi -e "$(t extras_empty "$EXTRAS_DIR")" -theme "$ROFI_THEME" "${dyn[@]}" || true
            exit 0
        fi
        SEL=$({ back_row
                for f in "${EXTRAS[@]}"; do
                    mark=""; [[ "$f" == "$EXTRA" ]] && mark="  ✓"
                    dim_row "🌐 ${f%.*}$mark" "$f"
                done; } | rofi_menu "🌐 $(t extra_shaders)" | pick_id) || true
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
                notify-send -a HyprVision "$(t config_title)" "$(t config_manual "$CONFIG")"
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
        notify-send -a HyprVision "$(t config_title)" "$(t config_saved)"
        ;;
    *)
        hv "apply('$ID')"
        ;;
esac
