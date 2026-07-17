# HyprVision

**Gestor de ergonomia visual nativo do Hyprland** — perfis de cor com shaders GLSL, gamma/temperatura/brightness, perfis ICC e overlays compostáveis, tudo num menu Rofi. Corre inteiro dentro do runtime Lua do compositor: sem daemon, sem Python.

> Lua-native visual profile manager for Hyprland ≥ 0.55: GLSL screen shaders, gamma control, ICC profiles and composable overlays behind a Rofi menu. Docs in Portuguese.

## Funcionalidades

- **Perfis visuais** definidos em Lua declarativo: shader + temperatura + brightness + gamma + ICC opcional
- **Overlays compostáveis** por cima de qualquer perfil:
  - *Paper Texture* (light/medium/heavy) — textura de papel estilo e-ink: grão em duas oitavas, mottling de polpa, fibras anisotrópicas e lift quente das sombras
  - *Extra Dim* (10–50%) — escurecimento por shader, abaixo do mínimo do backlight
- **Anti-banding para painéis 8-bit**: dither ~1 LSB sempre activo no shader composto + `render:use_fp16` (curvas em FP16 interno) + `render:icc_vcgt_enabled` (rampas VCGT por KMS)
- **Adaptativo sem daemon**: perfil por horário e por estado da bateria (com recuperação automática do perfil anterior) via `hl.timer` nativo
- **Persistência real**: os perfis sobrevivem a `hyprctl reload` — o runtime Lua é recriado e o `init.lua` restaura o estado ao carregar
- **Shaders extra da comunidade**: pasta `shaders/extras/` integrada no menu
- **Reset de emergência recuperável** (`Super+Shift+H`): repõe o ecrã neutro e arquiva o estado em `state.bak` — o menu ganha "Recuperar último estado"
- **Transições suaves** de temperatura/brightness/gamma via wl-gammarelay-rs (arranque on-demand)

## Perfis incluídos

| Perfil | Categoria | Para quê |
|---|---|---|
| ✨ Cinema Desktop | correction | Microcontraste suave para uso geral |
| 🖥️ TN Recovery | correction | Compensação de painéis TN lavados |
| 🌌 Cinema OLED | experience | Pretos esmagados a zero + vibrance seletivo — look OLED num LCD |
| 🧡 Cinema OLED Warm | experience | Cinema OLED com temperatura quente — filmes à noite sem cansar a vista |
| 🎬 Cinema Film | experience | Curva S, vinheta e grão de filme |
| 📖 E-Ink | experience | Dessaturação estilo tinta eletrónica (combina com Paper Texture) |
| 🕯️ E-Ink Warm Dark | experience | E-Ink quente e escuro — Kindle sob luz de vela, pretos mais profundos |
| 🎯 Focus | experience | Concentração, distrações atenuadas |
| 🌙 Night | experience | Noite, quente e escuro |
| 📄 Paper | experience | Papel envelhecido para leitura e escrita |
| 🌿 Paper Soft | experience | Paper ainda mais quente e suave, para sessões longas |
| ⚡ Reset | system | Tudo neutro |

## Requisitos

- Hyprland ≥ 0.55 **com config Lua** (`~/.config/hypr/hyprland.lua`) — para `hyprland.conf` clássico usa a v4 (tag `v4.1.0`)
- rofi
- **Recomendado:** [wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs) — temperatura, brightness e gamma com transições suaves
- Opcional: libnotify (notificações); lua5.4 e glslangValidator só para correr os testes

## Instalação

```bash
git clone <este-repo> && cd hyprvision
./install.sh
```

O instalador copia para `~/.config/hypr/hyprvision`, acrescenta o `require("init")` ao `hyprland.lua` e recarrega o Hyprland — fica logo activo. Correr de novo actualiza sem perder `config.lua` nem estado.

Para desinstalar (repõe o ecrã e remove tudo): `./uninstall.sh`.

Self-check do projeto (estado, perfis, compositor, horários, bateria, GLSL de todos os shaders, smoke test do menu): `lua5.4 test_hyprvision.lua`.

## Uso

`Super+H` abre o menu; `Super+Shift+H` é o reset de emergência. Para scripts, a mesma superfície que o menu usa:

```
hyprctl eval "hv.apply('night')"           aplica um perfil
hyprctl eval "hv.overlay('paper','medium')"  off | light | medium | heavy
hyprctl eval "hv.overlay('dim', 30)"       0 | 10 | 20 | 30 | 40 | 50
hyprctl eval "hv.apply_extra('x.glsl')"    shader extra (em shaders/extras/)
hyprctl eval "hv.safe_reset()"             reset de emergência
hyprctl eval "hv.restore_backup()"         recupera o estado arquivado
```

O estado actual está sempre legível em `~/.config/hypr/hyprvision/state/state` (key=value).

## Configuração

`~/.config/hypr/hyprvision/config.lua` — keybinds, horários e bateria. Depois de editar: `hyprctl reload`. Em qualquer evento, `profile = "none"` significa "não fazer nada". Destaques:

- `battery.restore_after_low` — ao recuperar de bateria fraca, volta sozinho ao perfil que estava activo
- `schedule.apply_on_start` — por omissão `false`: o arranque respeita o teu último perfil; os horários só disparam quando a hora cruza um slot
- Slots aceitam `minute` além de `hour`

## Criar um perfil

`profiles/meu_perfil.lua`:

```lua
-- Uma linha sobre o perfil.
return {
    name = "Meu Perfil", icon = "🔥", category = "experience",
    temperature = 5800,   -- 2500–9000 K
    brightness  = 0.95,   -- 0.05–1.5
    gamma       = 1.0,    -- 0.5–2.0
    shader = "experience/meu_perfil.glsl",   -- em shaders/; nil = sem shader
    -- icc = "meu_monitor.icc",              -- opcional, em icc/
}
```

**Importante nos shaders:** usa sempre `precision highp float;`. Com `mediump`, o ruído clássico `fract(sin(x) * 43758.5)` excede o alcance de fp16 em GPUs AMD/Mesa e produz NaN → **ecrã preto total**. (Todos os shaders incluídos já estão corrigidos.)

## Resolução de problemas

- **Ecrã ficou preto/ilegível** → `Super+Shift+H` (safe reset); depois "Recuperar último estado" no menu se foi engano.
- **Perfil "desapareceu" depois de mexer no tema/config** → não devia acontecer (o init restaura no reload); vê `state/hyprvision.log`.
- **Aviso "uniform 'time'"** do Hyprland → shaders animados exigem `debug:damage_tracking 0` (mais GPU); o HyprVision gere isto automaticamente e na ordem certa.
- Log: `~/.config/hypr/hyprvision/state/hyprvision.log`.

## Arquitectura

```
init.lua        wiring no compositor: binds, timers, restore no load
core.lua        motor: estado, perfis, compose GLSL, apply, gamma, ticks
config.lua      configuração do utilizador (keybinds, horário, bateria)
profiles/*.lua  perfis declarativos
ui/launcher.sh  menu Rofi (lê state/, envia hyprctl eval "hv.*")
```

O `hyprctl eval` não devolve output, por isso o Lua mantém `state/state` e `state/profiles.menu` como interface de leitura para o launcher. Os shaders compostos são gerados em `$XDG_RUNTIME_DIR/hyprvision/`. Tudo o que corre no compositor está embrulhado em `pcall` — um perfil roto regista no log e nunca derruba um handler.

## Créditos

Os shaders em `shaders/extras/` pertencem aos seus autores originais (0x15BA88FF, ManofJELLO, Sijan-Bhusal, snes19xx), com ajustes mínimos de compatibilidade (`highp`). Obrigado!
