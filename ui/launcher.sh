#!/usr/bin/env bash
# HyprVision · Launcher Rofi
# Lê o estado de state/state (o `hyprctl eval` não devolve output — o
# ficheiro é a interface de leitura) e envia acções via hyprctl eval.
#
# Estrutura visual partilhada com o Hypr.AI: grid de 4, raios concêntricos,
# cabeçalhos discretos, fileira de categorias e ponte tonal (Noctalia ou
# Caelestia). Ver rofi/hyprvision.rasi e DESIGN.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
STATE="$BASE_DIR/state/state"
MENU_IDX="$BASE_DIR/state/profiles.menu"
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprvision/rofi/hyprvision.rasi" ]]; then
    ROFI_THEME="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprvision/rofi/hyprvision.rasi"
elif [[ -f "$BASE_DIR/rofi/hyprvision.rasi" ]]; then
    ROFI_THEME="$BASE_DIR/rofi/hyprvision.rasi"
else
    ROFI_THEME="glass"
fi
USER_RASI="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprvision/rofi/user.rasi"

sv() {   # valor de uma chave do estado (default $2)
    local v=""
    [[ -f "$STATE" ]] && v=$(grep -m1 "^$1=" "$STATE" | cut -d= -f2-) || true
    echo "${v:-${2:-}}"
}

hv() {   # invoca a superfície Lua
    hyprctl eval "hv.$1" >/dev/null
}

# ── i18n: en / pt / zh a partir do locale do sistema, en por omissão ────
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in
    zh*) L=zh ;;
    pt*) L=pt ;;
    *)   L=en ;;
esac
# Cabeçalhos e chips em capitalização normal, não MAIÚSCULAS: maiúsculas
# destroem a forma da palavra, que é o que torna uma lista rápida de
# percorrer. Rótulo curto (uma palavra quando possível) porque a fileira
# de chips quebra em duas linhas desalinhadas se o texto crescer.
declare -A T=(
    [en:cat_correction]="Correction"          [pt:cat_correction]="Correção"           [zh:cat_correction]="校正"
    [en:cat_experience]="Experience"          [pt:cat_experience]="Experiência"        [zh:cat_experience]="体验"
    [en:cat_system]="System"                  [pt:cat_system]="Sistema"                [zh:cat_system]="系统"
    [en:overlays]="Overlays"                  [pt:overlays]="Overlays"                 [zh:overlays]="叠加层"
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
    [en:search_placeholder]="search profile..."      [pt:search_placeholder]="pesquisar perfil..."   [zh:search_placeholder]="搜索配置..."
)
# shellcheck disable=SC2059  # o formato É a tradução (leva %s)
t() { printf -- "${T[$L:$1]}" "${2:-}"; }

# ── nomes dos perfis traduzidos (inglês usa o nome tal como vem do profiles.menu) ─
declare -A PNAME=(
    [pt:cinema_desktop]="Cinema Desktop"    [zh:cinema_desktop]="影院桌面"
    [pt:cinema_film]="Cinema Filme"         [zh:cinema_film]="电影胶片"
    [pt:cinema_oled]="Cinema OLED"          [zh:cinema_oled]="影院 OLED"
    [pt:cinema_oled_warm]="Cinema OLED Quente" [zh:cinema_oled_warm]="暖色影院 OLED"
    [pt:eink]="E-Ink"                       [zh:eink]="电子墨水"
    [pt:eink_warm_dark]="E-Ink Quente e Escuro" [zh:eink_warm_dark]="暖色电子墨水"
    [pt:focus]="Foco"                       [zh:focus]="专注模式"
    [pt:night]="Noite"                      [zh:night]="夜间模式"
    [pt:paper]="Papel"                      [zh:paper]="纸质"
    [pt:paper_soft]="Papel Suave"           [zh:paper_soft]="柔和纸质"
    [pt:reset]="Reset"                      [zh:reset]="重置"
    [pt:tn_recovery]="Recuperação TN"       [zh:tn_recovery]="TN 面板修复"
)

PROFILE=$(sv profile reset); EXTRA=$(sv extra); PAPER=$(sv paper off); DIM=$(sv dim 0)
STATUS="◈ ${EXTRA:-$PROFILE}"
[[ "$PAPER" != "off" ]] && STATUS="$STATUS  📄$PAPER"
[[ "$DIM" != "0" ]] && STATUS="$STATUS  🔅$DIM%"

# ── Cor tonal do sistema ────────────────────────────────────────────────
# TODOS os neutros seguem o esquema activo, não só o accent: com o accent
# dinâmico e o resto fixo, o launcher lê como chrome alheio assim que o
# Noctalia/Caelestia pintam o resto do desktop (GTK, Qt, barra) noutro
# esquema. Ordem: Noctalia (ficheiro já renderizado) → Caelestia (JSON
# bruto) → paleta estática do .rasi.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprvision"
NOCTALIA_THEME="$STATE_DIR/noctalia-colors.rasi"
SCHEME_JSON="$HOME/.local/state/caelestia/scheme.json"

scheme_color() {   # $1=campo do scheme.json → hex de 6 dígitos, ou nada
    [[ -f "$SCHEME_JSON" ]] || return
    sed -n "s/.*\"$1\": *\"\([0-9a-fA-F]\{6\}\)\".*/\1/p" "$SCHEME_JSON" | head -1
}

# Guarda de legibilidade: aceita o accent só se contrastar ≥ 3:1 com o fundo
# (WCAG 1.4.11, componentes não-texto — prompt, scrollbar). Contraste e não
# brilho absoluto: num esquema claro o primary do M3 é escuro de propósito,
# e uma guarda de brilho rejeitava todo wallpaper claro (o menu caía no
# violeta estático). awk só pela vírgula flutuante da curva sRGB.
_contrast_ok() {   # $1=accent $2=fundo, hex sem '#'
    awk -v a="$1" -v b="$2" '
        function ch(h,   v) { h = tolower(h)   # gawk não lê "0x.." de string
                              v = (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 \
                                +  index("0123456789abcdef", substr(h, 2, 1)) - 1
                              v /= 255
                              return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(h) { return 0.2126 * ch(substr(h, 1, 2)) + 0.7152 * ch(substr(h, 3, 2)) \
                               + 0.0722 * ch(substr(h, 5, 2)) }
        BEGIN { la = lum(a); lb = lum(b)
                r = la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05)
                exit !(r >= 3) }'
}

dynamic_theme() {
    # 1) Noctalia — já renderizou theme/noctalia.rasi.tmpl inteiro (todos os
    # tokens, não só o accent); basta repassar o ficheiro.
    if [[ -s "$NOCTALIA_THEME" ]] && ! grep -q '{{' "$NOCTALIA_THEME"; then
        local accent bg
        accent="$(sed -n 's/.*bg3:[[:space:]]*#\([0-9a-fA-F]\{6\}\).*/\1/p' "$NOCTALIA_THEME" | head -1)"
        bg="$(sed -n 's/.*bg0:[[:space:]]*#\([0-9a-fA-F]\{6\}\).*/\1/p' "$NOCTALIA_THEME" | head -1)"
        if [[ -n "$accent" && -n "$bg" ]] && _contrast_ok "$accent" "$bg"; then
            cat "$NOCTALIA_THEME"
            return 0
        fi
    fi

    # 2) Caelestia (compat) — só JSON bruto, então remonta o mesmo conjunto
    # de tokens à mão a partir dos papéis M3 que o scheme expõe.
    local primary; primary="$(scheme_color primary)"
    [[ -n "$primary" ]] || return 0
    # Sem background não há contra o que medir — mede contra o fundo estático.
    local bg_c; bg_c="$(scheme_color background)"
    _contrast_ok "$primary" "${bg_c:-0D0D10}" || return 0

    local background surf_hi surf on_bg on_surf_var outline on_primary prim_cont on_prim_cont error
    background="$(scheme_color background)"
    surf_hi="$(scheme_color surfaceContainerHigh)"
    surf="$(scheme_color surfaceContainer)"
    on_bg="$(scheme_color onBackground)"
    on_surf_var="$(scheme_color onSurfaceVariant)"
    outline="$(scheme_color outline)"
    on_primary="$(scheme_color onPrimary)"
    prim_cont="$(scheme_color primaryContainer)"
    on_prim_cont="$(scheme_color onPrimaryContainer)"
    error="$(scheme_color error)"

    if [[ -n "$background" && -n "$on_bg" ]]; then
        # Os alphas (99/E6/99) são o que faz o vidro aparecer — ver o
        # comentário no .rasi: acima de ~85% o blur do compositor deixa de
        # contribuir e o painel lê como tinta chapada.
        cat <<RASI
* {
    bg0:        #${background}99;
    bg1:        #${surf_hi:-$background}E6;
    bg2:        #${surf:-$background}99;
    bg3:        #${primary}F2;
    fg0:        #${on_bg};
    fg2:        #${on_surf_var:-$on_bg};
    fg3:        #${outline:-$on_surf_var};
    accent-fg:  #${on_primary:-000000};
    error:      #${error:-E97871}F2;
    sel:        #${primary}1F;
    sep:        #${outline:-$on_surf_var};
    chip-bg:    #${prim_cont:-$primary};
    chip-fg:    #${on_prim_cont:-$on_bg};
    rim-top:    #${on_bg}38;
}
RASI
    else
        # Sem papéis suficientes para os neutros — só o accent, como compat
        # mínimo (a estrutura/grid do tema não muda).
        printf '* { bg3: #%sF2; sel: #%s1F; chip-bg: #%s24; }\n' "$primary" "$primary" "$primary"
    fi
}

# notify-send é opcional (libnotify) — sem ele a mensagem perde-se, mas com
# set -e um "command not found" terminava o launcher a meio.
notify() {
    command -v notify-send &>/dev/null || return 0
    notify-send -a HyprVision "$@" || true
}

# Abre $@ num terminal com o título $1. Cada terminal tem a sua sintaxe: o
# "-e" que servia a todos não existe no kitty nem no foot, que recebem o
# comando direto. Vazio se não houver nenhum.
term_argv() {
    local title="$1" t bin=""; shift
    for t in foot kitty alacritty wezterm ghostty konsole xterm; do
        bin="$(command -v "$t" 2>/dev/null)" && break
    done
    TERM_ARGV=()
    [[ -n "$bin" ]] || return 1
    case "${bin##*/}" in
        kitty)     TERM_ARGV=("$bin" --title "$title" "$@") ;;
        foot)      TERM_ARGV=("$bin" "--title=$title" "$@") ;;
        ghostty)   TERM_ARGV=("$bin" "--title=$title" -e "$@") ;;
        alacritty) TERM_ARGV=("$bin" --title "$title" -e "$@") ;;
        wezterm)   TERM_ARGV=("$bin" start --always-new-process -- "$@") ;;
        *)         TERM_ARGV=("$bin" -e "$@") ;;
    esac
}

# Editores de terminal conhecidos abrem num terminal; qualquer outro é
# tratado como gráfico — ao contrário de uma lista de GUIs, em que um
# $VISUAL gráfico fora da lista (subl, gnome-text-editor…) abria um
# terminal vazio a correr uma janela. EDITOR="code --wait" funciona (vira
# palavras); um editor num caminho com espaços não, como em qualquer $EDITOR.
edit_config() {
    local target="$1" ed bin
    local -a cmd=()
    for ed in "${VISUAL:-}" "${EDITOR:-}" code gedit kate gnome-text-editor nano; do
        [[ -n "$ed" ]] || continue
        read -ra cmd <<< "$ed"
        bin="$(command -v -- "${cmd[0]}" 2>/dev/null)" || continue
        cmd[0]="$bin"
        case "${bin##*/}" in
            nvim|vim|vi|nano|micro|hx|helix|kak|emacs|ne|joe|mcedit)
                term_argv "${target##*/}" "${cmd[@]}" "$target" || continue
                "${TERM_ARGV[@]}" &>/dev/null & disown
                return ;;
        esac
        "${cmd[@]}" "$target" &>/dev/null & disown
        return
    done
    if command -v xdg-open &>/dev/null; then
        xdg-open "$target" &>/dev/null & disown
    else
        notify "$(t config_title)" "$(t config_manual "$target")"
    fi
}

# ── Construção das linhas ───────────────────────────────────────────────
# Texto e id em arrays paralelos. O rofi devolve o índice (-format i), por
# isso o id nunca precisa de aparecer no ecrã — nada de [reset] a ocupar
# uma coluna em todas as linhas.
ROW_TEXT=()
ROW_ID=()

row() { ROW_TEXT+=("$1"); ROW_ID+=("${2:-}"); }

# Pango markup: '&' e '<' num nome de perfil partem a linha inteira.
esc() { printf '%s' "${1//&/&amp;}" | sed 's/</\&lt;/g'; }

# Cabeçalho de secção: pequeno, discreto, sem preenchimento, sem moldura e
# sem os traços `──`. O elemento menos importante do ecrã não leva o
# tratamento mais pesado.
sep() { row "$(printf '<span size="small" weight="600" alpha="45%%" letter_spacing="900">%s</span>' "$(esc "$1")")"; }

# Linha: ícone, nome e (opcional) subtexto discreto à direita.
item() {
    local icon="$1" name; name="$(esc "$2")"
    local desc="${3:-}" id="${4:-}"
    local lead; lead="$(printf '<span background="%s"> %s </span>  ' "$CHIP_BG" "$icon")"
    if [[ -n "$desc" ]]; then
        row "$(printf '%s%s   <span size="small" alpha="50%%">%s</span>' \
                "$lead" "$name" "$(esc "$desc")")" "$id"
    else
        row "$(printf '%s%s' "$lead" "$name")" "$id"
    fi
}

back_row() { row "$(printf '↩  <span alpha="70%%">%s</span>' "$(t back)")" "__back__"; }

# Resolve o tema dinâmico uma única vez por execução — run_menu e os chips
# em pango partilham o mesmo resultado, para o badge do prompt (renderizado
# pelo rofi, lê @chip-bg do .rasi) e os chips de categoria/ícone (texto
# pango, sem acesso a variáveis do tema) nunca dessincronizarem.
DYNAMIC_THEME_STR="$(dynamic_theme)"

_token() {
    sed -n "s/.*\b$1:[[:space:]]*\(#[0-9a-fA-F]\{6,8\}\).*/\1/p" <<<"$DYNAMIC_THEME_STR" | head -1
}

# Chip de categoria/ícone: elevação NEUTRA (bg1/fg2 — o mesmo "content
# material" do inputbar), não o accent. Com 4 categorias + 16 ícones de
# linha tingidos de accent, a lista inteira vira um bloco da mesma cor e
# "um accent só, 1-2 elementos" deixa de valer. Pango não lê variáveis do
# tema, por isso o valor já resolvido entra aqui como hex literal.
CHIP_BG="$(_token bg1)"; CHIP_BG="${CHIP_BG:-#1C1C21}"
CHIP_FG="$(_token fg2)"; CHIP_FG="${CHIP_FG:-#9E9EA3}"
chip() { printf '<span background="%s" foreground="%s" size="small" weight="600">  %s  </span>' \
            "$CHIP_BG" "$CHIP_FG" "$(esc "$1")"; }

# Fileira de categorias acima da lista, via -mesg. Não é clicável (o dmenu
# do rofi não alterna modos sem reescrever isto como múltiplos "modi" de
# script); é a legenda visual dos grupos da lista.
chips_row() {
    local out="" first=1 c
    for c in "$@"; do
        [[ $first -eq 0 ]] && out+="  "
        out+="$(chip "$c")"
        first=0
    done
    printf '%s' "$out"
}

# Corre o menu com as linhas já construídas. $2 = linha selecionada de
# início (1 = o primeiro item real, para o cursor não abrir em cima de um
# cabeçalho). $3 = markup da fileira de categorias (opcional).
run_menu() {
    local dyn=(); [[ -n "$DYNAMIC_THEME_STR" ]] && dyn=(-theme-str "$DYNAMIC_THEME_STR")
    local mesg=(); [[ -n "${3:-}" ]] && mesg=(-mesg "$3")
    # Ajustes pessoais (posição, largura, fonte) — depois do tema dinâmico,
    # para ganharem sempre. O install.sh nunca apaga este ficheiro.
    local usr=(); [[ -s "$USER_RASI" ]] && usr=(-theme-str "$(cat "$USER_RASI")")
    # Linha sem id é cabeçalho: nonselectable — o rofi continua a parar nela
    # nas setas (a opção só impede o Enter), mas o Enter já não reabre o menu.
    local i
    for i in "${!ROW_TEXT[@]}"; do
        if [[ -z "${ROW_ID[i]:-}" ]]; then
            printf '%s\x00nonselectable\x1ftrue\n' "${ROW_TEXT[i]}"
        else
            printf '%s\n' "${ROW_TEXT[i]}"
        fi
    done | rofi -dmenu -p "$1" -theme "$ROFI_THEME" \
        -theme-str "entry { placeholder: \"$(t search_placeholder)\"; }" \
        "${dyn[@]}" "${usr[@]}" "${mesg[@]}" -no-custom -markup-rows -format i -selected-row "${2:-1}"
}

# Mostra o menu e devolve o id escolhido (vazio = cancelou ou cabeçalho).
pick() {
    local idx
    idx=$(run_menu "$1" "${2:-1}" "${3:-}") || return 1
    [[ "${idx:-}" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "${ROW_ID[$idx]:-}"
}

build_main() {
    ROW_TEXT=(); ROW_ID=()
    local last_cat="" id icon name cat mark
    while IFS=$'\t' read -r id icon name cat; do
        if [[ "$cat" != "$last_cat" ]]; then
            case "$cat" in
                correction) sep "$(t cat_correction)" ;;
                experience) sep "$(t cat_experience)" ;;
                system)     sep "$(t cat_system)" ;;
                *)          sep "$cat" ;;
            esac
            last_cat="$cat"
        fi
        mark=""; [[ "$id" == "$PROFILE" && -z "$EXTRA" ]] && mark="✓"
        name="${PNAME[$L:$id]:-$name}"
        item "$icon" "$name" "$mark" "$id"
    done < "$MENU_IDX"

    sep "$(t overlays)"
    local pm=""; [[ "$PAPER" != "off" ]] && pm="  ✓"
    item "📄" "$(t paper_texture)" "$PAPER  ▸$pm" "__paper__"
    local dm=""; [[ "$DIM" != "0" ]] && dm="  ✓"
    item "🔅" "$(t extra_dim)" "${DIM}%  ▸$dm" "__dim__"
    local em=""; [[ -n "$EXTRA" ]] && em="  ✓"
    item "🌐" "$(t extra_shaders)" "${EXTRA:-—}  ▸$em" "__extras__"
    [[ -f "$STATE.bak" ]] && item "↩" "$(t recover)" "" "__recover__"
    item "📝" "$(t edit_config)" "config.lua" "__config__"
}

MAIN_CHIPS="$(chips_row "$(t cat_correction)" "$(t cat_experience)" "$(t cat_system)" "$(t overlays)")"

build_main
# O cursor abre na linha 1, não na 0: a 0 é um cabeçalho de secção.
ID="$(pick "$STATUS" 1 "$MAIN_CHIPS")" || exit 0
# `if`, nunca `[[ ]] &&` no fim de bloco: regressão set -e da v4.1.0
if [[ -z "$ID" ]]; then exec "$0"; fi

case "$ID" in
    __paper__)
        ROW_TEXT=(); ROW_ID=(); back_row
        for lvl in off light medium heavy; do
            mark=""; [[ "$lvl" == "$PAPER" ]] && mark="✓"
            item "📄" "$lvl" "$mark" "$lvl"
        done
        SEL="$(pick "📄 $(t paper_texture)" 1)" || exit 0
        if [[ -z "$SEL" || "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('paper', '$SEL')"
        ;;
    __dim__)
        ROW_TEXT=(); ROW_ID=(); back_row
        for lvl in 0 10 20 30 40 50; do
            mark=""; [[ "$lvl" == "$DIM" ]] && mark="✓"
            item "🔅" "$lvl%" "$mark" "$lvl"
        done
        SEL="$(pick "🔅 $(t extra_dim)" 1)" || exit 0
        if [[ -z "$SEL" || "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "overlay('dim', $SEL)"
        ;;
    __extras__)
        EXTRAS_DIR="$BASE_DIR/shaders/extras"
        mapfile -t EXTRAS < <(find "$EXTRAS_DIR" \( -name "*.glsl" -o -name "*.frag" \) \
            -printf "%f\n" 2>/dev/null | sort)
        if ((${#EXTRAS[@]} == 0)); then
            dyn=(); [[ -n "$DYNAMIC_THEME_STR" ]] && dyn=(-theme-str "$DYNAMIC_THEME_STR")
            rofi -e "$(t extras_empty "$EXTRAS_DIR")" -theme "$ROFI_THEME" "${dyn[@]}" || true
            exit 0
        fi
        ROW_TEXT=(); ROW_ID=(); back_row
        for f in "${EXTRAS[@]}"; do
            mark=""; [[ "$f" == "$EXTRA" ]] && mark="✓"
            item "🌐" "${f%.*}" "$mark" "$f"
        done
        SEL="$(pick "🌐 $(t extra_shaders)" 1)" || exit 0
        if [[ -z "$SEL" || "$SEL" == "__back__" ]]; then exec "$0"; fi
        hv "apply_extra('$SEL')"
        ;;
    __recover__)
        hv "restore_backup()"
        ;;
    __config__)
        CONFIG="$BASE_DIR/config.lua"
        edit_config "$CONFIG"
        notify "$(t config_title)" "$(t config_saved)"
        ;;
    *)
        hv "apply('$ID')"
        ;;
esac
