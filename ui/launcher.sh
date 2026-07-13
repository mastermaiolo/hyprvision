#!/usr/bin/env bash
# HyprVision · Launcher Rofi
# Menu principal (perfis) + submenus: Paper Texture, Extra Dim, Extras, Daemon.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$BASE_DIR/bin/hyprvision"
ROFI_THEME="$BASE_DIR/rofi/hyprvision.rasi"

[[ -f "$CLI" ]] || { notify-send -u critical "HyprVision" "CLI não encontrado: $CLI"; exit 1; }
[[ -x "$CLI" ]] || chmod +x "$CLI"

STATUS_RAW=$("$CLI" --status 2>/dev/null)

# Prompt de estado
STATUS=$(echo "$STATUS_RAW" | awk -F': ' '
    /^Perfil/    { p=$2 }
    /^Extra /    { ex=$2 }
    /^Paper Tex/ { pt=$2 }
    /^Dim/       { d=$2 }
    END {
        s = "◈ " p
        if (ex != "(nenhum)") s = s "  🌐" ex
        if (pt != "off")      s = s "  📄" pt
        if (d != "0%")        s = s "  🔅" d
        print s
    }
')

rofi_menu() {   # $1 prompt · stdin linhas → escolha (raw)
    rofi -dmenu -p "$1" -theme "$ROFI_THEME" -no-custom -markup-rows -format s
}

pick_id() {   # extrai o [id] da linha escolhida
    grep -o '\[[^]]*\]' | tail -1 | tr -d '[]'
}

# Submenu genérico: linhas "icone texto [id]"; devolve id (vazio = cancelado)
submenu() {   # $1 prompt
    rofi_menu "$1" | pick_id || true
}

main_menu() {
    local choice
    choice=$("$CLI" --list-rofi | rofi_menu "$STATUS") || exit 0
    [[ -z "$choice" ]] && exit 0
    # Separadores de categoria não têm [id] — reabre o menu
    [[ "$choice" == *"──"* ]] && exec "$0"
    ID=$(echo "$choice" | pick_id)
    # `if` e não `[[ ]] &&`: como última linha da função, o status 1 do
    # teste falhado matava o script inteiro via set -e (menu "não fazia nada")
    if [[ -z "$ID" ]]; then exec "$0"; fi
}

back_row() { printf '↩ Voltar   <span alpha="30%%" size="small">[__back__]</span>\n'; }

main_menu

case "$ID" in
    __paper__)
        CUR=$(echo "$STATUS_RAW" | awk -F': ' '/^Paper Tex/ {print $2}')
        SEL=$({ back_row
                for lvl in off light medium heavy; do
                    mark=""; [[ "$lvl" == "$CUR" ]] && mark="  ✓"
                    printf '📄 %s%s   <span alpha="30%%" size="small">[%s]</span>\n' "$lvl" "$mark" "$lvl"
                done; } | submenu "📄 Paper Texture")
        [[ -z "$SEL" ]] && exit 0
        [[ "$SEL" == "__back__" ]] && exec "$0"
        "$CLI" --paper-texture "$SEL"
        ;;
    __dim__)
        CUR=$(echo "$STATUS_RAW" | awk -F': ' '/^Dim/ {print $2}')
        SEL=$({ back_row
                for lvl in 0 10 20 30 40 50; do
                    mark=""; [[ "${lvl}%" == "$CUR" ]] && mark="  ✓"
                    printf '🔅 %s%%%s   <span alpha="30%%" size="small">[%s]</span>\n' "$lvl" "$mark" "$lvl"
                done; } | submenu "🔅 Extra Dim")
        [[ -z "$SEL" ]] && exit 0
        [[ "$SEL" == "__back__" ]] && exec "$0"
        "$CLI" --dim "$SEL"
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
        CUR=$(echo "$STATUS_RAW" | awk -F': ' '/^Extra / {print $2}')
        SEL=$({ back_row
                for f in "${EXTRAS[@]}"; do
                    mark=""; [[ "$f" == "$CUR" ]] && mark="  ✓"
                    printf '🌐 %s%s   <span alpha="30%%" size="small">[%s]</span>\n' "${f%.*}" "$mark" "$f"
                done; } | submenu "🌐 Shaders extra")
        [[ -z "$SEL" ]] && exit 0
        [[ "$SEL" == "__back__" ]] && exec "$0"
        # Passa pelo pipeline: composto com overlays e registado no estado
        "$CLI" --apply-extra "$SEL"
        ;;
    __daemon__)
        if "$CLI" --status | grep -q "a correr"; then
            ROWS=$'🔄 Recarregar config   <span alpha="30%" size="small">[reload]</span>\n🛑 Parar daemon   <span alpha="30%" size="small">[stop]</span>'
        else
            ROWS='▶️  Iniciar daemon   <span alpha="30%" size="small">[start]</span>'
        fi
        SEL=$({ back_row; echo "$ROWS"
                echo '📝 Editar configuração (TOML)   <span alpha="30%" size="small">[config]</span>'
              } | submenu "⚙️ Daemon")
        [[ -z "$SEL" ]] && exit 0
        case "$SEL" in
            __back__) exec "$0" ;;
            start)  "$CLI" --daemon-start  && notify-send -a HyprVision "Daemon" "Iniciado ✓" ;;
            stop)   "$CLI" --daemon-stop   && notify-send -a HyprVision "Daemon" "Parado." ;;
            reload) "$CLI" --reload-daemon && notify-send -a HyprVision "Daemon" "Config recarregada ✓" ;;
            config)
                CONFIG="$HOME/.config/hypr/hyprvision/daemon_config.toml"
                "$CLI" --init-config >/dev/null
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
                        code|gedit|kate)
                            $EDITOR_CMD "$CONFIG" & disown ;;
                        *)
                            TERM_CMD=""
                            for t in foot kitty alacritty wezterm ghostty gnome-terminal konsole xterm; do
                                command -v "$t" &>/dev/null && { TERM_CMD="$t"; break; }
                            done
                            if [[ -n "$TERM_CMD" ]]; then
                                $TERM_CMD -e $EDITOR_CMD "$CONFIG" & disown
                            else
                                xdg-open "$CONFIG" 2>/dev/null || true
                            fi ;;
                    esac
                fi
                notify-send -a HyprVision "Config" "Após guardar: hyprvision --reload-daemon"
                ;;
        esac
        ;;
    *)
        "$CLI" --apply "$ID"
        ;;
esac
