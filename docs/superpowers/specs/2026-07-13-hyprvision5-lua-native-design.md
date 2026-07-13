# HyprVision 5.0 — Design Lua-nativo

**Data:** 2026-07-13 · **Estado:** aprovado em conversa, aguarda revisão do spec
**Base:** v4.1.0 (`85bea4b`) · **Alvo:** Hyprland ≥ 0.55 com config `hyprland.lua`

## Objectivo

Reescrever o HyprVision como módulo Lua nativo do Hyprland, eliminando o
daemon Python, o CLI Python e o eval-shim, e extrair o máximo de qualidade
de imagem do painel real do utilizador (AU Optronics TN 8-bit 1080p, eDP-1,
sem HDR/10-bit). A experiência do menu Rofi mantém-se igual.

Fora de scope (decidido): automação por contexto (perfil por janela /
fullscreen / screenshare), recalibração visual do TN Recovery (fase
posterior, iterativa ao ecrã), suporte a hyprland.conf clássico (o 5.0 é
Lua-only; quem usa .conf fica na v4).

## Factos da plataforma (verificados ao vivo em 0.55.4)

- API `hl`: `config`, `monitor`, `bind`, `on`, `timer`, `notification`,
  `exec_cmd`, `get_monitors`, `dispatch`, `env`, … e **`io` Lua completo**.
- Eventos `hl.on` relevantes: `hyprland.start`, `config.reloaded`,
  `hyprland.shutdown`, `monitor.added/removed`.
- `hyprctl eval` **não devolve output** (responde sempre `ok`) — leitura de
  estado por processos externos tem de passar por ficheiro.
- `hyprctl keyword` falha em parser Lua com exit 0 + mensagem "Use eval".
- Opções de render úteis: `render:use_fp16`, `render:icc_vcgt_enabled`,
  `render:cm_enabled` (já true), CTM nativo.

## Arquitectura

```
~/.config/hypr/hyprvision/
  init.lua          -- wiring: binds, eventos, timers, restore no load
  core.lua          -- motor: perfis, compose GLSL, estado, apply, gamma
  config.lua        -- utilizador: horários, bateria, keybinds
  profiles/*.lua    -- 9 perfis como tabelas declarativas
  shaders/          -- GLSL intacto (perfis + extras da comunidade)
  ui/launcher.sh    -- menu Rofi (mantido)
  rofi/hyprvision.rasi
  state/state.json  -- estado corrente (interface de leitura p/ launcher)
```

Morre: `bin/hyprvision`, `bin/hyprvision-daemon`, `core/*.py`, PID files,
listener socket2, `daemon_config.toml` (→ `config.lua`), perfis TOML
(→ `profiles/*.lua`).

### Módulos

- **`init.lua`** — carregado por `require("hyprvision")` no `hyprland.lua`.
  Regista o global `hv` (interface para `hyprctl eval`), binds
  (Super+H menu, Super+Shift+H safe-reset), timers (horário 60 s, bateria
  30 s), `hl.on('config.reloaded')` e `hl.on('hyprland.shutdown')`, aplica
  as opções de render (fp16, icc_vcgt) e restaura o estado no load.
- **`core.lua`** — sem dependência directa de `hl` no import (recebe-o por
  injecção) para ser testável fora do compositor. Expõe: `load_profile(id)`,
  `compose(profile, overlays)`, `apply(id)`, `overlay(kind, level)`,
  `apply_extra(file)`, `safe_reset()`, `restore()`, `read_state()/write_state()`.
- **`config.lua`** — tabela Lua editável pelo utilizador; mesma semântica
  da config do daemon v4 (slots com `minute`, `plugged/unplugged`,
  `low_battery` + `restore_after_low`, `apply_on_start`).
- **`profiles/*.lua`** — cada ficheiro devolve
  `{ name, icon, category, shader, temperature, brightness, gamma, icc }`.

### Fluxo de aplicação

`hv.apply("night")` → `profiles/night.lua` → compose do GLSL (perfil +
paper texture + dim + **dither**, template string em Lua) → escreve em
`$XDG_RUNTIME_DIR/hyprvision/merged-<n>.glsl` (nome novo por compose,
apaga o anterior; mantém a ordem damage-tracking do v4 para shaders
animados) → `hl.config{ decoration = { screen_shader = path } }` → ICC via
`hl.monitor` (modo actual preservado, lido de `hl.get_monitors()`) → gamma
via wl-gammarelay-rs → `write_state()` → `hl.notification`.

### Gamma / temperatura / brightness

wl-gammarelay-rs mantém-se como único processo externo (rampas de hardware,
custo GPU zero). Chamadas `busctl` via `hl.exec_cmd`; arranque on-demand
como no v4. Transições suaves: rampa de ~10 passos com `hl.timer` (50 ms).

### Estado e interface com o menu

- O Lua é o único escritor de `state/state.json` (write + rename atómico).
- O launcher **lê** o JSON directamente e **escreve** acções via
  `hyprctl eval "hv.apply('…')"` / `hv.overlay(…)` / `hv.safe_reset()`.
- O launcher gera as linhas do menu a partir do JSON (a lógica de
  `--list-rofi` migra do Python para o launcher; formato pango igual).

### Arranque, reload e recuperação

O reload da config Lua re-executa `init.lua`; o init trata load e reload da
mesma forma: (re)aplica opções de render, (re)regista binds/timers/eventos
e restaura o estado do `state.json`. `hl.on('config.reloaded')` fica
registado como reserva — na implementação confirma-se qual dos mecanismos
dispara (runtime recriado vs persistente) e documenta-se; a lógica de
restore é idempotente para ser inofensiva se ambos correrem.

### Safe-reset (corrige o achado da revisão v4)

`hv.safe_reset()` repõe shader/ICC/gamma neutros e **renomeia**
`state.json` → `state.bak` (o arranque seguinte fica neutro — um perfil
roto não volta no boot), e o menu ganha "Recuperar último estado"
(`hv.restore_backup()`).

### Adaptativo

- **Horário:** timer de 60 s compara `os.date` com os slots (mesma
  semântica de wrap do v4, incluindo `minute`).
- **Bateria:** timer de 30 s lê `/sys/class/power_supply/BAT*/capacity` e
  `status` via `io` (sem upower). `low_battery` → perfil de poupança;
  `restore_after_low` → devolve o anterior; `plugged/unplugged` = `none`
  por omissão (não sobrepõe escolha manual), como no v4.

### Qualidade de imagem (painel 8-bit TN)

1. `render:use_fp16 = true` — curvas calculadas em FP16 interno.
2. Dither ~1 LSB no fim do shader composto, sempre activo (hash Dave
   Hoskins já existente; sem banding visível em Night/Dim).
3. `render:icc_vcgt_enabled = true` — rampas VCGT por KMS quando há ICC.
4. Shaders GLSL de perfil mantêm-se intactos.

### Robustez

Todos os handlers (timers, eventos, `hv.*`) embrulhados em `pcall`; erro →
`hl.notification` crítica + linha em `state/hyprvision.log` (com rotação
simples). Um perfil roto nunca derruba os handlers nem o compositor.
Super+Shift+H continua a ser a saída de emergência.

## Testes

`test_hyprvision.lua`, corrido com Lua standalone (`lua test_hyprvision.lua`),
com mock de `hl` injectado em `core.lua`:

- compose (highp forçado, `#version` único, parâmetros de overlay, dither presente)
- wrap de horários (incl. `minute` e slots que atravessam a meia-noite)
- round-trip do estado (+ safe_reset → `.bak` → restore_backup)
- lógica de bateria (thresholds, `restore_after_low`) com `/sys` mockado
- sintaxe GLSL de todos os shaders e compostos via glslangValidator
- **smoke test do launcher** (rofi/eval falsos → a acção certa é invocada;
  lição da regressão v4.1.0 do `set -e`)

## Migração e instalação

- Branch `v5` sobre `85bea4b`; a v4 fica intacta em `main` até o 5.0 estar
  verificado ao vivo.
- `install.sh`: rsync + acrescenta `require("hyprvision")` ao
  `hyprland.lua` (com o ajuste de `package.path`); remove artefactos v4
  obsoletos da instalação (bin/, core/, daemon). `uninstall.sh` idem.
- Conversão dos 9 perfis TOML→Lua e da `daemon_config.toml`→`config.lua`
  feita no repo (manual, os ficheiros são triviais).

## Critérios de sucesso

- Menu Rofi: aplicar perfil, overlays, extra, reset — tudo funcional ao vivo.
- `hyprctl reload` e restart do Hyprland preservam o perfil activo.
- Horário e bateria mudam de perfil sem daemon externo (`pgrep` só encontra
  o wl-gammarelay-rs).
- Degradê de teste em Night/Dim sem banding visível (antes/depois do dither).
- `lua test_hyprvision.lua` verde; zero Python na instalação.
