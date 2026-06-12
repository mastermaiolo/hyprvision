#!/usr/bin/env bash
# HyprVision v4 · Launcher Rofi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$BASE_DIR/bin/hyprvision"
ROFI_THEME="$BASE_DIR/rofi/hyprvision.rasi"

[[ -f "$CLI" ]] || { notify-send -u critical "HyprVision" "CLI não encontrado: $CLI"; exit 1; }
[[ -x "$CLI" ]] || chmod +x "$CLI"

# Prompt de estado
STATUS=$("$CLI" --status 2>/dev/null | awk -F': ' '
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

PROFILES=$("$CLI" --list-rofi)

# Rofi
choice=$(echo -e "$PROFILES" | rofi \
    -dmenu \
    -p "$STATUS" \
    -theme "$ROFI_THEME" \
    -no-custom \
    -format s) || exit 0

[[ -z "$choice" ]] && exit 0

# Separadores de categoria não têm [id] — reabre o menu
[[ "$choice" == ──* ]] && exec "$0"

# Extrai ID entre [ ]
ID=$(echo "$choice" | grep -o '\[[^]]*\]' | tail -1 | tr -d '[]')
[[ -z "$ID" ]] && exec "$0"

case "$ID" in
    paper_tex_*)
        "$CLI" --paper-texture "${ID#paper_tex_}"
        ;;
    dim_*)
        "$CLI" --dim "${ID#dim_}"
        ;;
    __extras__)
        EXTRAS_DIR="$BASE_DIR/shaders/extras"
        count=$(find "$EXTRAS_DIR" \( -name "*.glsl" -o -name "*.frag" \) 2>/dev/null | wc -l)
        if [[ "$count" -eq 0 ]]; then
            rofi -e "Pasta extras vazia.\n\nColoca .glsl em:\n$EXTRAS_DIR" \
                -theme "$ROFI_THEME" || true
            exit 0
        fi
        extra_choice=$(find "$EXTRAS_DIR" \( -name "*.glsl" -o -name "*.frag" \) \
            -printf "%f\n" | sort | \
            rofi -dmenu -p "🌐 Extras" -theme "$ROFI_THEME") || exit 0
        [[ -z "$extra_choice" ]] && exit 0
        # Passa pelo pipeline: composto com overlays e registado no estado
        "$CLI" --apply-extra "$extra_choice"
        ;;
    __daemon_status__)
        # Só mostra info — reabre o menu
        exec "$0"
        ;;
    __daemon_config__)
        CONFIG="$HOME/.config/hypr/hyprvision/daemon_config.toml"
        # Garante que o ficheiro existe e tem TODAS as secções visíveis
        "$CLI" --init-config >/dev/null

        # Abre no editor preferido (XDG)
        EDITOR_CMD=""
        for ed in "${VISUAL:-}" "${EDITOR:-}" code gedit kate nano; do
            if [[ -n "$ed" ]] && command -v "${ed%% *}" &>/dev/null; then
                EDITOR_CMD="$ed"
                break
            fi
        done

        if [[ -z "$EDITOR_CMD" ]]; then
            notify-send -a "HyprVision" "Config" "Edita manualmente: $CONFIG"
            xdg-open "$CONFIG" 2>/dev/null || true
        else
            # GUI editors são lançados em background; editors de terminal
            # precisam de uma janela de terminal
            case "${EDITOR_CMD%% *}" in
                code|gedit|kate|nautilus|nemo|thunar)
                    $EDITOR_CMD "$CONFIG" &
                    disown
                    ;;
                *)
                    TERM_CMD=""
                    for t in foot kitty alacritty wezterm gnome-terminal konsole xterm; do
                        if command -v "$t" &>/dev/null; then TERM_CMD="$t"; break; fi
                    done
                    if [[ -n "$TERM_CMD" ]]; then
                        $TERM_CMD -e $EDITOR_CMD "$CONFIG" &
                        disown
                    else
                        xdg-open "$CONFIG" 2>/dev/null || true
                    fi
                    ;;
            esac
        fi
        notify-send -a "HyprVision" "Config" "Após guardar, corre: hyprvision --reload-daemon"
        ;;
    __daemon_reload__)
        "$CLI" --reload-daemon && \
            notify-send -a "HyprVision" "Daemon" "Configuração recarregada ✓" || \
            notify-send -a "HyprVision" "Daemon" "Daemon não está a correr."
        ;;
    __daemon_stop__)
        "$CLI" --daemon-stop && \
            notify-send -a "HyprVision" "Daemon" "Daemon parado." || \
            notify-send -u critical -a "HyprVision" "Daemon" "Falha ao parar o daemon."
        ;;
    __daemon_start__)
        "$CLI" --daemon-start && \
            notify-send -a "HyprVision" "Daemon" "Daemon iniciado ✓" || \
            notify-send -u critical -a "HyprVision" "Daemon" "Falha ao iniciar o daemon."
        ;;
    *)
        "$CLI" --apply "$ID"
        ;;
esac
