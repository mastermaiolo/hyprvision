#!/usr/bin/env bash
# HyprVision · Instalador (Hyprland ≥ 0.55 com config hyprland.lua)
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/hypr/hyprvision"
HYPRLUA="$HOME/.config/hypr/hyprland.lua"

# ── i18n: inglês / mandarim simplificado a partir do locale ─────────────
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in
    zh*) L=zh ;;
    *)   L=en ;;
esac
declare -A T=(
    [en:title]="── HyprVision · Installer ──"                                    [zh:title]="── HyprVision · 安装程序 ──"
    [en:no_hyprlua]="✗ %s not found. HyprVision needs the Lua config (hyprland.lua)." [zh:no_hyprlua]="✗ 找不到 %s。HyprVision 需要 Lua 配置文件 (hyprland.lua)。"
    [en:no_hyprlua_hint]="  For the classic hyprland.conf, use v4 (tag v4.1.0) instead." [zh:no_hyprlua_hint]="  如果你用旧版 hyprland.conf，请改用 v4（tag v4.1.0）。"
    [en:files_copied]="✓ Files installed to %s (config.lua and state/ kept)"     [zh:files_copied]="✓ 文件已安装到 %s（保留 config.lua 和 state/）"
    [en:require_ok]="✓ require added to %s"                                     [zh:require_ok]="✓ 已在 %s 中添加 require"
    [en:reloaded]="✓ Hyprland reloaded — HyprVision is active"                  [zh:reloaded]="✓ Hyprland 已重新加载 — HyprVision 已启用"
    [en:done]="── Done. Menu: %s · Reset: %s ──"                                 [zh:done]="── 完成。菜单：%s · 重置：%s ──"

    [en:noctalia_ok]="✓ Tonal colour bridge registered with Noctalia"           [zh:noctalia_ok]="✓ 已在 Noctalia 中注册色调桥接"
    [en:noctalia_found]="✓ Tonal colour bridge already registered with Noctalia" [zh:noctalia_found]="✓ Noctalia 中已注册色调桥接"
    [en:glass_found]="✓ Glass exception for the 'rofi' namespace already in place" [zh:glass_found]="✓ 'rofi' 命名空间的玻璃例外已就绪"
    [en:glass_ask]="Layer-shell popups get no blur in Hyprland unless a layerrule targets their namespace — without it the glass theme renders as a flat, near-opaque panel. Add one for 'rofi' in windowrules.lua? [y/N] " \
    [zh:glass_ask]="除非 layerrule 指定命名空间，Hyprland 不会对 layer-shell 弹窗应用模糊 — 没有它，玻璃主题会显示为扁平、近乎不透明的面板。要为 'rofi' 添加一条吗？[y/N] "
    [en:glass_ok]="✓ Glass exception added to windowrules.lua"                  [zh:glass_ok]="✓ 已将玻璃例外添加到 windowrules.lua"
    [en:glass_skip]="→ No exception — the menu uses the global blur as-is"      [zh:glass_skip]="→ 不添加例外 — 菜单沿用全局模糊"
    [en:glass_manual]="Add this to your Hyprland config by hand to get real glass:" \
    [zh:glass_manual]="请手动将以下内容添加到 Hyprland 配置中以获得真正的玻璃效果："

    [en:bind_conflict]="⚠ %s is already bound to something else."              [zh:bind_conflict]="⚠ %s 已经被绑定到别的功能。"
    [en:bind_prompt]="  New key to use instead (one letter, Enter keeps %s): "  [zh:bind_prompt]="  改用哪个键？（一个字母，回车保持 %s）："

    [en:deps_title]="Checking dependencies..."                                  [zh:deps_title]="正在检查依赖..."
    [en:dep_missing]="⚠ Missing: %s (%s)"                                       [zh:dep_missing]="⚠ 缺少：%s（%s）"
    [en:dep_required]="required"                                                [zh:dep_required]="必需"
    [en:dep_recommended]="recommended"                                          [zh:dep_recommended]="推荐"
    [en:ask_install]="  Install %s now? [Y/n] "                                  [zh:ask_install]="  现在安装 %s 吗？[Y/n] "
    [en:no_pkg_mgr]="  No supported package manager found — install %s manually." [zh:no_pkg_mgr]="  没有找到受支持的包管理器 — 请手动安装 %s。"
    [en:aur_needed]="  %s is AUR-only. Install it with paru/yay, or see:"        [zh:aur_needed]="  %s 只能通过 AUR 安装。请用 paru/yay 安装，或参考："
    [en:installing]="  Installing %s..."                                        [zh:installing]="  正在安装 %s..."
    [en:dep_ok]="✓ dependencies OK"                                              [zh:dep_ok]="✓ 依赖已就绪"

    [en:mode_title]="How do you want to switch visual profiles?"                [zh:mode_title]="你想怎么切换视觉配置？"
    [en:mode_manual]="Manual — switch profiles myself from the Rofi menu"       [zh:mode_manual]="手动 — 我自己在 Rofi 菜单里切换"
    [en:mode_auto]="Automatic — switch by time of day (day / night)"            [zh:mode_auto]="自动 — 按时间切换（白天 / 夜晚）"
    [en:pick_mode]="Choice [1-2]: "                                              [zh:pick_mode]="请选择 [1-2]："
    [en:profiles_list]="Available profiles:"                                    [zh:profiles_list]="可用的配置："
    [en:pick_day_profile]="Day profile number: "                                [zh:pick_day_profile]="白天配置的编号："
    [en:pick_night_profile]="Night profile number: "                            [zh:pick_night_profile]="夜晚配置的编号："
    [en:pick_day_hour]="Hour to switch to the day profile [0-23]: "             [zh:pick_day_hour]="切换到白天配置的时间 [0-23]："
    [en:pick_night_hour]="Hour to switch to the night profile [0-23]: "         [zh:pick_night_hour]="切换到夜晚配置的时间 [0-23]："
    [en:bad_number]="  Please enter a valid number from the list."             [zh:bad_number]="  请输入列表中的有效编号。"
    [en:bad_hour]="  Please enter a whole number from 0 to 23."                [zh:bad_hour]="  请输入 0 到 23 之间的整数。"
    [en:schedule_set]="✓ Schedule set: %s at %02d:00, %s at %02d:00"            [zh:schedule_set]="✓ 日程已设置：%s 于 %02d:00，%s 于 %02d:00"
    [en:manual_set]="✓ Manual mode — automatic schedule left disabled"          [zh:manual_set]="✓ 手动模式 — 自动日程保持关闭"
)
t() { local key="$1"; shift; printf -- "${T[$L:$key]}" "$@"; }

echo "$(t title)"
[[ -f "$HYPRLUA" ]] || {
    echo "$(t no_hyprlua "$HYPRLUA")"
    echo "$(t no_hyprlua_hint)"
    exit 1
}

# ── dependências: deteta o gestor de pacotes do sistema ─────────────────
PKG_MGR="" PKG_INSTALL=""
if command -v pacman &>/dev/null; then PKG_MGR=pacman; PKG_INSTALL="sudo pacman -S --needed --noconfirm"
elif command -v apt-get &>/dev/null; then PKG_MGR=apt; PKG_INSTALL="sudo apt-get install -y"
elif command -v dnf &>/dev/null; then PKG_MGR=dnf; PKG_INSTALL="sudo dnf install -y"
fi

pkg_name() {   # nome do pacote da dependência lógica ($1) neste gestor
    case "$PKG_MGR:$1" in
        *:rofi)           echo rofi ;;
        pacman:libnotify) echo libnotify ;;
        apt:libnotify)    echo libnotify-bin ;;
        dnf:libnotify)    echo libnotify ;;
    esac
}

install_pkg() {   # $1 = dependência lógica (rofi, libnotify)
    local pkg; pkg="$(pkg_name "$1")"
    if [[ -z "$PKG_MGR" || -z "$pkg" ]]; then
        echo "$(t no_pkg_mgr "$1")"; return
    fi
    local ans
    printf '%s' "$(t ask_install "$pkg")" >&2
    if read -r ans; then ans="${ans:-Y}"; else ans="N"; fi
    [[ "$ans" =~ ^[Yy] ]] || return
    echo "$(t installing "$pkg")"
    $PKG_INSTALL "$pkg"
}

install_wl_gammarelay() {
    local aur=""
    command -v paru &>/dev/null && aur=paru
    [[ -z "$aur" ]] && command -v yay &>/dev/null && aur=yay
    if [[ -z "$aur" ]]; then
        echo "$(t aur_needed "wl-gammarelay-rs")"
        echo "  https://github.com/MaxVerevkin/wl-gammarelay-rs"
        return
    fi
    local ans
    printf '%s' "$(t ask_install "wl-gammarelay-rs")" >&2
    if read -r ans; then ans="${ans:-Y}"; else ans="N"; fi
    [[ "$ans" =~ ^[Yy] ]] || return
    echo "$(t installing "wl-gammarelay-rs")"
    "$aur" -S --noconfirm wl-gammarelay-rs
}

check_and_offer() {   # $1=comando a testar  $2=dependência lógica  $3=required|recommended
    command -v "$1" &>/dev/null && return 0
    echo "$(t dep_missing "$1" "$(t "dep_$3")")"
    if [[ "$2" == wl-gammarelay-rs ]]; then install_wl_gammarelay; else install_pkg "$2"; fi
}

echo; echo "$(t deps_title)"
check_and_offer rofi rofi required
check_and_offer wl-gammarelay-rs wl-gammarelay-rs recommended
check_and_offer notify-send libnotify recommended
echo "$(t dep_ok)"

# daemon v4 ainda a correr? pára-o
pkill -f hyprvision-daemon 2>/dev/null || true

mkdir -p "$DEST"
rsync -a --delete \
    --exclude 'state/' --exclude '.git/' --exclude 'docs/' --exclude 'assets/' \
    --exclude 'install.sh' --exclude 'uninstall.sh' \
    --exclude 'test_hyprvision.lua' --exclude 'README*.md' --exclude 'CHANGELOG.md' \
    --exclude 'config.lua' \
    "$SRC"/ "$DEST"/
chmod +x "$DEST/ui/launcher.sh"
CONFIG_IS_NEW=0
if [[ ! -f "$DEST/config.lua" ]]; then
    cp "$SRC/config.lua" "$DEST/config.lua"
    CONFIG_IS_NEW=1
fi
echo "$(t files_copied "$DEST")"

# ── atalhos: só verifica conflitos numa instalação de raiz, e só dentro
#    de uma sessão Hyprland viva (hyprctl binds precisa do compositor) ───
bind_taken() {   # $1=modmask  $2=tecla → 0 se já há algum bind (nosso ou de terceiros) nessa combinação
    hyprctl -j binds 2>/dev/null | awk -v want_mod="$1" -v want_key="$2" '
        /"modmask":/ { m = $0; gsub(/[^0-9]/, "", m); mod = m }
        /"key":/ {
            k = $0; sub(/.*"key": *"/, "", k); sub(/".*/, "", k)
            if (mod == want_mod && tolower(k) == tolower(want_key)) found = 1
        }
        END { exit !found }
    '
}

# ── modo de perfis: só pergunta numa instalação de raiz (config.lua novo) ─
list_profiles() {   # id|nome, uma linha por perfil, na ordem dos ficheiros
    local f id name
    for f in "$SRC"/profiles/*.lua; do
        id="$(basename "$f" .lua)"
        name="$(grep -m1 'name = ' "$f" | sed -E 's/.*name = "([^"]+)".*/\1/')"
        echo "$id|$name"
    done
}

disable_schedule() {   # só desliga schedule.enabled — não toca em battery.enabled
    awk '
        /^    schedule = \{$/ { in_sched = 1 }
        in_sched && /^        enabled = true,$/ { sub(/true/, "false"); in_sched = 0 }
        { print }
    ' "$DEST/config.lua" > "$DEST/config.lua.tmp" && mv "$DEST/config.lua.tmp" "$DEST/config.lua"
}

apply_schedule() {   # $1=id dia $2=hora dia $3=id noite $4=hora noite
    awk -v day_id="$1" -v day_hour="$2" -v night_id="$3" -v night_hour="$4" '
        /^        slots = \{$/ {
            print
            printf "            { name = \"day\",   enabled = true, hour = %s, profile = \"%s\" },\n", day_hour, day_id
            printf "            { name = \"night\", enabled = true, hour = %s, profile = \"%s\" },\n", night_hour, night_id
            in_slots = 1; next
        }
        in_slots && /^        \},$/ { in_slots = 0; print; next }
        in_slots { next }
        /^        apply_on_start = false,/ { sub(/false/, "true"); print; next }
        { print }
    ' "$DEST/config.lua" > "$DEST/config.lua.tmp" && mv "$DEST/config.lua.tmp" "$DEST/config.lua"
}

ask_profile_number() {   # $1=chave do prompt → id escolhido, ou "" se não houver resposta
    local n id
    printf '%s' "$(t "$1")" >&2; read -r n || { echo ""; return; }
    while true; do
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#PROFILES[@]} )); then
            IFS='|' read -r id _ <<< "${PROFILES[n-1]}"
            echo "$id"; return
        fi
        echo "$(t bad_number)" >&2
        printf '%s' "$(t "$1")" >&2; read -r n || { echo ""; return; }
    done
}

ask_hour() {   # $1=chave do prompt → hora escolhida, ou "" se não houver resposta
    local h
    printf '%s' "$(t "$1")" >&2; read -r h || { echo ""; return; }
    while true; do
        [[ "$h" =~ ^[0-9]+$ ]] && (( h >= 0 && h <= 23 )) && { echo "$h"; return; }
        echo "$(t bad_hour)" >&2
        printf '%s' "$(t "$1")" >&2; read -r h || { echo ""; return; }
    done
}

if (( CONFIG_IS_NEW )); then
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        MENU_KEY=H; RESET_KEY=H
        if bind_taken 64 "$MENU_KEY"; then
            echo; echo "$(t bind_conflict "SUPER + $MENU_KEY")"
            NEW=""; printf '%s' "$(t bind_prompt "$MENU_KEY")" >&2; read -r NEW || true
            [[ -n "$NEW" ]] && MENU_KEY="${NEW:0:1}" && MENU_KEY="${MENU_KEY^^}"
        fi
        if bind_taken 65 "$RESET_KEY"; then
            echo; echo "$(t bind_conflict "SUPER + SHIFT + $RESET_KEY")"
            NEW=""; printf '%s' "$(t bind_prompt "$RESET_KEY")" >&2; read -r NEW || true
            [[ -n "$NEW" ]] && RESET_KEY="${NEW:0:1}" && RESET_KEY="${RESET_KEY^^}"
        fi
        [[ "$MENU_KEY" != "H" ]] && sed -i "s/menu  = \"SUPER + H\"/menu  = \"SUPER + ${MENU_KEY}\"/" "$DEST/config.lua"
        [[ "$RESET_KEY" != "H" ]] && sed -i "s/reset = \"SUPER + SHIFT + H\"/reset = \"SUPER + SHIFT + ${RESET_KEY}\"/" "$DEST/config.lua"
    fi

    echo; echo "$(t mode_title)"
    echo "  1) $(t mode_manual)"
    echo "  2) $(t mode_auto)"
    MODE=1
    while true; do
        printf '%s' "$(t pick_mode)" >&2; read -r MODE || { MODE=1; break; }
        [[ "$MODE" == "1" || "$MODE" == "2" ]] && break
        echo "$(t bad_number)" >&2
    done

    if [[ "$MODE" == "2" ]]; then
        mapfile -t PROFILES < <(list_profiles)
        echo "$(t profiles_list)"
        i=1
        for p in "${PROFILES[@]}"; do
            IFS='|' read -r _ name <<< "$p"
            printf "  %2d) %s\n" "$i" "$name"
            ((i++))
        done
        DAY_ID=$(ask_profile_number pick_day_profile)
        [[ -n "$DAY_ID" ]] && DAY_HOUR=$(ask_hour pick_day_hour)
        [[ -n "${DAY_HOUR:-}" ]] && NIGHT_ID=$(ask_profile_number pick_night_profile)
        [[ -n "${NIGHT_ID:-}" ]] && NIGHT_HOUR=$(ask_hour pick_night_hour)

        if [[ -n "${NIGHT_HOUR:-}" ]]; then
            apply_schedule "$DAY_ID" "$DAY_HOUR" "$NIGHT_ID" "$NIGHT_HOUR"
            echo "$(t schedule_set "$DAY_ID" "$DAY_HOUR" "$NIGHT_ID" "$NIGHT_HOUR")"
        else
            disable_schedule
            echo "$(t manual_set)"
        fi
    else
        disable_schedule
        echo "$(t manual_set)"
    fi
fi

# onde ligar o require: hyprland.lua normalmente, mas em Ryoku (e em qualquer
# setup que semeie um user.lua nunca tocado por updates) esse ficheiro é o
# baseline shipped do sistema — um `ryoku update`/materialize reescreve-o e
# apaga o require sem aviso (os ficheiros do HyprVision continuam em disco, só
# o require desaparece). user.lua sobrevive a isso, por isso é preferido
# quando existe.
WIREFILE="$HYPRLUA"
[[ -f "$HOME/.config/hypr/user.lua" ]] && WIREFILE="$HOME/.config/hypr/user.lua"

# remove qualquer bloco HyprVision anterior — formato antigo (v4/v5, sem
# marcadores, só existiu em hyprland.lua) e o novo formato com marcadores
# (pode estar em hyprland.lua ou em user.lua, conforme uma instalação
# anterior o tenha posto) — e recria, idempotente
sed -i -e '/hyprvision/d' -e '/^-- HyprVision/d' -e '/require("init")/d' "$HYPRLUA"
[[ -f "$WIREFILE" ]] && sed -i -e '/-- HyprVision >>>/,/-- HyprVision <<</d' "$WIREFILE"
cat >> "$WIREFILE" <<'LUA'
-- HyprVision >>>
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/hyprvision/?.lua"
require("init")
-- HyprVision <<<
LUA
echo "$(t require_ok "$(basename "$WIREFILE")")"

# ── cor tonal: registra o template no Noctalia, se instalado ────────────
# O Noctalia re-renderiza theme/noctalia.rasi.tmpl sozinho a cada troca de
# wallpaper/scheme e escreve o resultado no state dir; o launcher só lê o
# ficheiro. Sem Noctalia, o launcher cai no Caelestia (scheme.json) e, sem
# nenhum dos dois, na paleta estática do .rasi.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprvision"
mkdir -p "$STATE_DIR"
NOCTALIA_CONF="$HOME/.config/noctalia/config.toml"
if [[ -f "$NOCTALIA_CONF" ]]; then
    if grep -q "theme.templates.user.hyprvision" "$NOCTALIA_CONF" 2>/dev/null; then
        echo "$(t noctalia_found)"
    else
        cat >> "$NOCTALIA_CONF" <<EOF

    [theme.templates.user.hyprvision]
    input_path = "$DEST/theme/noctalia.rasi.tmpl"
    output_path = "$STATE_DIR/noctalia-colors.rasi"
EOF
        echo "$(t noctalia_ok)"
    fi
fi

# ── vidro: layerrule para o namespace "rofi" ────────────────────────────
# No Hyprland, um layer-shell popup não recebe blur por omissão — sem uma
# regra explícita, o tema de vidro renderiza como painel quase opaco. A
# regra é partilhada com o Hypr.AI (mesmo namespace), por isso se já
# existir não duplicamos.
GLASS_RULE='hl.layer_rule({ name = "rofi-glass", match = { namespace = "^rofi$" }, ignore_alpha = 0.2, blur = true, xray = false })'
WINDOWRULES="$HOME/.config/hypr/config/windowrules.lua"
if [[ -f "$WINDOWRULES" ]]; then
    if grep -q 'namespace = "\^rofi\$"' "$WINDOWRULES" 2>/dev/null; then
        echo "$(t glass_found)"
    elif [[ -t 0 ]]; then
        read -r -p "$(t glass_ask)" GLASS_ANS
        case "$GLASS_ANS" in
            [yY]*|[sS]*)
                cat >> "$WINDOWRULES" <<'EOF'

-- Rofi launchers (HyprVision, Hypr.AI): layer-shell popups get no blur by
-- default in Hyprland unless a layerrule targets their namespace explicitly —
-- without this, the glass theme renders as a flat, near-opaque panel.
hl.layer_rule({
  name = "rofi-glass",
  match = { namespace = "^rofi$" },
  ignore_alpha = 0.2,
  blur = true,
  xray = false,
})
EOF
                echo "$(t glass_ok)"
                ;;
            *) echo "$(t glass_skip)" ;;
        esac
    else
        echo "$(t glass_manual)"
        printf '%s\n' "$GLASS_RULE"
    fi
else
    echo "$(t glass_manual)"
    printf '%s\n' "$GLASS_RULE"
fi

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    hyprctl reload >/dev/null && echo "$(t reloaded)"
fi
FINAL_MENU="$(grep -m1 'menu  =' "$DEST/config.lua" | sed -E 's/.*"([^"]+)".*/\1/')"
FINAL_RESET="$(grep -m1 'reset =' "$DEST/config.lua" | sed -E 's/.*"([^"]+)".*/\1/')"
echo "$(t done "$FINAL_MENU" "$FINAL_RESET")"
