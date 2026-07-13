# HyprVision v4

**Gestor modular de ergonomia visual para o Hyprland** — perfis de cor com shaders GLSL, gamma/temperatura/brightness, perfis ICC e overlays compostáveis, tudo num menu Rofi.

> Visual profile manager for Hyprland: GLSL screen shaders, gamma control, ICC profiles and composable overlays behind a Rofi menu. Docs in Portuguese.

## Funcionalidades

- **Perfis visuais** definidos em TOML simples: shader + temperatura + brightness + gamma + ICC opcional
- **Overlays compostáveis** por cima de qualquer perfil:
  - *Paper Texture* (light/medium/heavy) — textura de papel estilo e-ink: grão em duas oitavas, mottling de polpa, fibras anisotrópicas e lift quente das sombras
  - *Extra Dim* (10–50%) — escurecimento por shader, abaixo do mínimo do backlight
- **Daemon adaptativo**: muda de perfil por horário e por estado da bateria (com recuperação automática do perfil anterior), hot-reload da config via SIGHUP
- **Persistência real**: os perfis sobrevivem a `hyprctl reload` (o daemon escuta `configreloaded` no socket2 e reaplica shader/ICC, que o Hyprland limpa em cada reload)
- **Shaders extra da comunidade**: pasta `shaders/extras/` integrada no menu, com estado e restore
- **Reset de emergência** num atalho (`Super+Shift+H`) — se um perfil correr mal, um toque repõe o ecrã neutro
- **Transições suaves** de temperatura/brightness/gamma via wl-gammarelay-rs

## Perfis incluídos

| Perfil | Categoria | Para quê |
|---|---|---|
| ✨ Cinema Desktop | correction | Microcontraste suave para uso geral |
| 🖥️ TN Recovery | correction | Compensação de painéis TN lavados |
| 🌌 Cinema OLED | experience | Pretos esmagados a zero + vibrance seletivo — look OLED num LCD |
| 🎬 Cinema Film | experience | Curva S, vinheta e grão de filme |
| 📖 E-Ink | experience | Dessaturação estilo tinta eletrónica (combina com Paper Texture) |
| 🎯 Focus | experience | Concentração, distrações atenuadas |
| 🌙 Night | experience | Noite, quente e escuro |
| 📄 Paper / 🌿 Paper Soft | experience | Papel envelhecido para leitura e escrita |
| ⚡ Reset | system | Tudo neutro |

## Requisitos

- Hyprland ≥ 0.55
- Python ≥ 3.11 (usa `tomllib`, sem dependências pip)
- rofi
- **Recomendado:** [wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs) — temperatura, brightness e gamma com transições suaves (fallback: hyprsunset/wlsunset, só temperatura)
- Opcional: libnotify (notificações), zenity (wizard de atalhos)

## Instalação

```bash
git clone <este-repo> && cd hyprvision
./install.sh
```

O instalador copia para `~/.config/hypr/hyprvision`, adiciona o `source` ao `hyprland.conf`, cria a config do daemon e activa os atalhos na sessão actual. Para escolher outro atalho que não `Super+H`: `bin/hyprvision-setup --force`.

Para desinstalar (pára o daemon, repõe o ecrã e remove tudo): `./uninstall.sh`.

Self-check do projeto (compositor, horários, state, GLSL de todos os shaders): `python3 test_hyprvision.py`.

## Uso

`Super+H` abre o menu. Tudo o que o menu faz também existe no CLI:

```
hyprvision --apply <id>            aplica um perfil
hyprvision --apply-extra <file>    aplica um shader extra
hyprvision --paper-texture <lvl>   off | light | medium | heavy
hyprvision --dim <n>               0 | 10 | 20 | 30 | 40 | 50
hyprvision --status                estado actual
hyprvision --safe-reset            reset de emergência
hyprvision --restore               restaura o último estado
hyprvision --daemon-start/stop     controla o daemon
hyprvision --reload-daemon         relê o daemon_config.toml (SIGHUP)
hyprvision --init-config           cria/completa o daemon_config.toml
```

## Configuração do daemon

`~/.config/hypr/hyprvision/daemon_config.toml` (ver [daemon_config.example.toml](daemon_config.example.toml)) — tudo explícito, sem defaults invisíveis. Em qualquer evento, `profile = "none"` significa "não fazer nada". Destaques:

- `battery.restore_after_low` — ao recuperar de bateria fraca, volta sozinho ao perfil que estava activo
- `schedule.apply_on_start` — por omissão `false`: o arranque respeita o teu último perfil; os horários só disparam quando a hora cruza um slot
- Slots aceitam `minute` além de `hour`

## Criar um perfil

`profiles/<categoria>/meu_perfil.toml`:

```toml
name        = "Meu Perfil"
icon        = "🔥"
description = "..."
category    = "experience"

[gamma]
temperature = 5800      # 2500–9000 K
brightness  = 0.95      # 0.05–1.5
gamma       = 1.0       # 0.5–2.0

[shader]
file = "meu_perfil.glsl"   # em shaders/<categoria>/

# [icc]
# file = "meu_monitor.icc"
```

**Importante nos shaders:** usa sempre `precision highp float;`. Com `mediump`, o ruído clássico `fract(sin(x) * 43758.5)` excede o alcance de fp16 em GPUs AMD/Mesa e produz NaN → **ecrã preto total**. (Todos os shaders incluídos já estão corrigidos.)

## Resolução de problemas

- **Ecrã ficou preto/ilegível** → `Super+Shift+H` (safe reset). Causa habitual: shader com `mediump` (ver acima).
- **Perfil "desapareceu" depois de mexer no tema/config** → não devia acontecer (o daemon reaplica após `configreloaded`); verifica se o daemon corre: `hyprvision --status`.
- **Aviso "uniform 'time'"** do Hyprland → shaders animados exigem `debug:damage_tracking 0` (mais GPU); o HyprVision gere isto automaticamente e na ordem certa.
- Log do daemon: `~/.config/hypr/hyprvision/state/daemon.log`.

## Arquitectura

```
bin/hyprvision          CLI
bin/hyprvision-daemon   daemon adaptativo (bateria, horário, configreloaded)
bin/hyprvision-setup    wizard de atalhos
core/apply.py           pipeline: perfil → validação → shader composto → gamma → ICC → estado
core/shader.py          compositor GLSL de 3 camadas (perfil + paper texture + dim)
core/gamma.py           backends wl-gammarelay-rs / hyprsunset
core/daemonctl.py       PID, liveness, start/stop/reload
ui/launcher.sh          menu Rofi
```

Os shaders compostos são gerados em `$XDG_RUNTIME_DIR/hyprvision/`. O estado persiste em `state/current_state.json` (escrita atómica).

## Créditos

Os shaders em `shaders/extras/` pertencem aos seus autores originais (0x15BA88FF, ManofJELLO, Sijan-Bhusal, snes19xx), com ajustes mínimos de compatibilidade (`highp`). Obrigado!
