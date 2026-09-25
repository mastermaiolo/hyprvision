#!/usr/bin/env bash
# HyprVision · Desinstalador — reverte o install.sh: ecrã neutro,
# ficheiros removidos e require retirado do hyprland.lua.
set -euo pipefail

DEST="$HOME/.config/hypr/hyprvision"
HYPRLUA="$HOME/.config/hypr/hyprland.lua"

# ── i18n: en / pt / zh a partir do locale (o mesmo critério do launcher) ──
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in
    zh*) L=zh ;;
    pt*) L=pt ;;
    *)   L=en ;;
esac
declare -A T=(
    [en:title]="── HyprVision · uninstall ──"            [pt:title]="── HyprVision · desinstalação ──"          [zh:title]="── HyprVision · 卸载 ──"
    [en:reset]="✓ Screen reset to neutral"               [pt:reset]="✓ Ecrã reposto ao neutro"                 [zh:reset]="✓ 屏幕已恢复为中性"
    [en:require]="✓ require removed from %s"             [pt:require]="✓ require removido do %s"               [zh:require]="✓ 已从 %s 中移除 require"
    [en:noctalia]="✓ tonal colour bridge removed from Noctalia" [pt:noctalia]="✓ ponte de cor tonal removida do Noctalia" [zh:noctalia]="✓ 已从 Noctalia 中移除色调桥接"
    [en:removed]="✓ %s removed"                          [pt:removed]="✓ %s removido"                          [zh:removed]="✓ 已移除 %s"
    [en:finished]="── Done. \`hyprctl reload\` to drop this session's binds. ──" \
    [pt:finished]="── Feito. \`hyprctl reload\` para largar os binds desta sessão. ──" \
    [zh:finished]="── 完成。运行 \`hyprctl reload\` 以清除本次会话的快捷键。──"
)
# shellcheck disable=SC2059  # o formato É a tradução (leva %s)
t()   { printf -- "${T[$L:$1]}" "${@:2}"; }
say() { t "$@"; echo; }

# Escreve por cima do conteúdo em vez de mv/sed -i: um arquivo que seja
# symlink (stow, repositório de dotfiles) continua symlink, e a mudança cai
# no arquivo real em vez de o substituir por uma cópia solta.
write_through() {   # $1=arquivo  stdin=conteúdo novo
    local tmp; tmp="$(mktemp)"
    cat > "$tmp" && cat "$tmp" > "$1"
    rm -f "$tmp"
}

# Tira do arquivo só o que o instalador lá pôs: o bloco entre
# "-- HyprVision >>>" e "-- HyprVision <<<" e, de instalações v5.0/v5.1
# (sem marcadores), exatamente as três linhas consecutivas que elas
# escreviam. Antes era sed '/hyprvision/d' + '/require("init")/d': levava
# também qualquer comentário do utilizador com a palavra e qualquer
# require("init") dele — um módulo "init" próprio deixava de carregar.
strip_hyprvision() {   # $1=arquivo
    [[ -f "$1" ]] || return 0
    awk '
        { line[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) {
                if (line[i] ~ /^-- HyprVision >>>[[:space:]]*$/) {
                    while (i <= n && line[i] !~ /^-- HyprVision <<<[[:space:]]*$/) i++
                    continue
                }
                if (line[i] ~ /^-- HyprVision( 5)?[[:space:]]*$/ \
                    && line[i+1] ~ /^package\.path = .*\/\.config\/hypr\/hyprvision\/\?\.lua"\)?[[:space:]]*$/ \
                    && line[i+2] ~ /^require\("(init|hyprvision_lua)"\)[[:space:]]*$/) {
                    i += 2
                    continue
                }
                print line[i]
            }
        }
    ' "$1" | write_through "$1"
}

say title
pkill -f hyprvision-daemon 2>/dev/null || true   # resto de v4, se houver

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl eval "hv.safe_reset()" >/dev/null 2>&1 || true
    say reset
fi

# O require pode estar no hyprland.lua (formato antigo, ou sem user.lua) e/ou
# no user.lua — tira-se dos dois, e só o que o install.sh lá pôs.
for f in "$HYPRLUA" "$HOME/.config/hypr/user.lua"; do
    [[ -f "$f" ]] || continue
    grep -qE -- '-- HyprVision|hyprvision/\?\.lua' "$f" || continue
    strip_hyprvision "$f"
    say require "${f##*/}"
done

# ponte de cor tonal: retira o bloco que o install.sh acrescentou (até ao
# próximo cabeçalho [..], que pode ser o do Hypr.AI — esse fica)
NOCTALIA_CONF="$HOME/.config/noctalia/config.toml"
if [[ -f "$NOCTALIA_CONF" ]] && grep -q "theme.templates.user.hyprvision" "$NOCTALIA_CONF"; then
    awk '
      /^[[:space:]]*\[theme\.templates\.user\.hyprvision\][[:space:]]*$/ { skip = 1; next }
      skip && /^[[:space:]]*\[/ { skip = 0 }
      !skip
    ' "$NOCTALIA_CONF" | write_through "$NOCTALIA_CONF"
    say noctalia
fi
# A layerrule "rofi-glass" em windowrules.lua fica: o namespace é partilhado
# com o Hypr.AI e removê-la aqui tiraria o vidro do outro launcher também.

rm -rf "$DEST"
rm -rf "${XDG_RUNTIME_DIR:-/tmp}/hyprvision"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/hyprvision" "${XDG_CACHE_HOME:-$HOME/.cache}/hyprvision"
say removed "$DEST"
say finished
