# Changelog

## v5.1.0 — 2026-07-17

Publicação no GitHub: internacionalização, instalador interativo e documentação em 3 idiomas.

### Adicionado
- **Menu Rofi em 3 idiomas** (inglês, português, 中文), pelo locale do sistema — inclui os nomes dos perfis e o placeholder de pesquisa, não só o texto de UI.
- **Menu Rofi segue a cor tonal actual do Caelestia**: lê o `scheme.json` Material gerado a partir do wallpaper e sobrepõe a paleta estática via `-theme-str`.
- **Instalador interativo** (inglês/中文): verifica e oferece instalar dependências em falta (pacman/apt/dnf; AUR via paru/yay para o wl-gammarelay-rs); deteta conflitos de atalho em `Super+H`/`Super+Shift+H` via `hyprctl binds` e deixa escolher outra tecla; pergunta entre troca manual de perfil ou automática por horário (dia/noite).
- **Licença MIT** (`LICENSE`) e créditos revistos, com tabela por autor e links para os projectos originais dos shaders da comunidade.
- Perfis **Cinema OLED Warm** e **E-Ink Warm Dark**.
- **README em português, inglês e 中文**, com índice, GIF de demonstração e secção de licença.
- Self-check ampliado: testes para o instalador (modo automático/manual, EOF seguro), o desinstalador, e a tradução de nomes de perfis.

### Corrigido
- **Reset** também limpa os overlays de Paper Texture e Extra Dim (antes só limpava perfil/shader/extra, deixando overlays "pendurados").
- **`install.sh` sobrescrevia `config.lua`** a cada reinstalação — o filtro `protect` do rsync só impede apagar, não sobrescrever; `config.lua` passa a ficheiro excluído do rsync.
- **`uninstall.sh` deixava um `require("init")` órfão** no `hyprland.lua`, fazendo o Hyprland reclamar módulo em falta a cada reload.
- **`uninstall.sh` executava `hyprctl reload` por acidente**: crases não escapadas dentro de aspas duplas disparam substituição de comando mesmo lá dentro.

### Alterado
- Nome do projecto passa a **"HyprVision"** (sem número de versão no nome — o "5" fica só nas entradas deste changelog).

## v5.0.0 — 2026-07-13

Reescrita Lua-nativa. O HyprVision passa a viver dentro do Hyprland.

### Alterado
- **Zero Python, zero daemon próprio**: `init.lua` + `core.lua` correm no runtime
  Lua do compositor; horário e bateria via `hl.timer`, reaplicação pós-reload
  via re-execução do init (o runtime é recriado em cada reload — verificado).
- Perfis passam de TOML para `profiles/*.lua`; config do daemon → `config.lua`.
- O launcher lê `state/state` (key=value) e envia acções via `hyprctl eval "hv.*"`.
- Gamma continua no wl-gammarelay-rs (rampas de hardware), com rampa suave
  de 10 passos e arranque on-demand.

### Adicionado
- **Dither ~1 LSB** sempre activo no shader composto + `render:use_fp16` +
  `render:icc_vcgt_enabled` — menos banding no painel 8-bit.
- **Safe-reset recuperável**: arquiva o estado em `state.bak` em vez de o
  apagar; entrada "Recuperar último estado" no menu.
- `test_hyprvision.lua` (lua5.4 standalone, `hl` mock) com smoke test do launcher.

### Removido
- CLI `hyprvision`, `hyprvision-daemon`, `core/*.py`, listener socket2,
  PID files, parser TOML, submenu do daemon no Rofi.

## v4.1.0 — 2026-07-13

### Corrigido
- **Menu Rofi não aplicava nada**: o refactor para `main_menu()` deixou `[[ -z "$ID" ]] && exec "$0"` como última linha da função — com ID válido o `[[ ]]` devolve 1, o `set -e` mata o script na chamada e o `case` das acções nunca corria. Toda a selecção (perfis, reset, submenus) falhava em silêncio. Coberto por smoke test do launcher (rofi e CLI falsos) no self-check.
- **`#version` fora da primeira linha** nos 9 shaders de perfil (comentários antes da directiva) — viola a spec GLSL ES 3.00; a Mesa tolera, outros drivers não. Detectado pelo novo self-check.
- **wl-gammarelay-rs nunca arrancava sozinho**: o pacote não traz D-Bus activation nem unit systemd, e nada o lançava — o backend caía silenciosamente para hyprsunset (só temperatura). O `WlGammaRelayBackend` agora arranca-o on-demand quando o binário existe mas o serviço não responde.

### Adicionado
- **`test_hyprvision.py`** — self-check sem frameworks (`python3 test_hyprvision.py`): compositor de shaders, wrap de horários, round-trip do state, validador e sintaxe GLSL de todos os shaders (incluindo os compostos gerados) via glslangValidator.
- **`uninstall.sh`** — reverte tudo: pára o daemon, repõe o ecrã neutro, remove ficheiros e o `source` do hyprland.conf.

## v4.0.0 — 2026-06-12

Reescrita de robustez sobre a v3, mantendo a arquitectura.

### Corrigido
- **Ecrã preto em perfis com grão** (paper, paper_soft, cinema_film): `precision mediump` executa em fp16 em GPUs AMD/Mesa e o ruído `fract(sin(x)*43758.5)` transborda → NaN → preto. Todos os shaders (perfis, extras e wrapper composto) passam a `highp`.
- **Perfis "desapareciam" após reload do Hyprland**: um `hyprctl reload` (ou theming dinâmico) limpa os keywords `screen_shader` e `monitor/icc`. O daemon agora escuta `configreloaded` no socket2 e reaplica os visuais; fallback de verificação a cada ciclo.
- **Aviso persistente "uniform 'time'"**: ao trocar de shader animado para estático, o damage_tracking subia antes de substituir o shader, fazendo o Hyprland revalidar o shader antigo. Ordem corrigida nos dois sentidos.
- **Daemon morria em qualquer erro de perfil** (`sys.exit` no pipeline). O pipeline devolve `bool`; o daemon regista em `state/daemon.log` e continua.
- **PID stale**: parar o daemon não limpava o `daemon.pid`. Agora SIGTERM é tratado, o PID é validado contra `/proc` e ficheiros obsoletos são removidos.
- **Wizard de atalhos**: keybinds aplicados em runtime só registavam a última acção (loop mal indentado) e o bloco no `.conf` era duplicado a cada execução (regex não casava com o próprio cabeçalho).
- **Menu**: seleccionar um separador de categoria fechava o menu em vez de o reabrir.
- **Paper Texture invisível**: amplitude efectiva ~3/255 e máscara de luminância que apagava a textura em temas escuros.

### Adicionado
- **Perfil Cinema OLED**: pretos esmagados a zero com toe suave + vibrance seletivo + punch nos realces.
- **Paper Texture redesenhada** (estilo e-ink): grão em duas oitavas + mottling de baixa frequência + fibras anisotrópicas + lift quente das sombras, calibrada visualmente (off→heavy medido 36→72 de grão em zona plana).
- **Extras integrados no pipeline** (`--apply-extra`): compostos com overlays, registados no estado, visíveis no `--status` e restaurados no `--restore`.
- **Reset de emergência** em atalho (`Super+Shift+H`).
- **Recuperação de bateria** (`restore_after_low`): ao sair de bateria fraca, volta ao perfil anterior.
- **`--daemon-start` / `--daemon-stop` / `--init-config`** no CLI; menu do daemon contextual (mostra só as acções válidas).
- **Restore no arranque** (`exec-once = hyprvision --restore`).
- Log do daemon com rotação (`state/daemon.log`), slots de horário com `minute`, instalador `install.sh`.

### Alterado
- Config do daemon totalmente explícita (sem defaults invisíveis); `"none"` desactiva qualquer evento; defaults de bateria deixaram de sobrepor o perfil manual (`plugged`/`unplugged` = `none`).
- O arranque e o reload da config já não forçam o perfil do horário (`apply_on_start = false` por omissão).
- Shaders compostos movidos de `/tmp` para `$XDG_RUNTIME_DIR/hyprvision/` (privado, tmpfs); limpeza só dos próprios ficheiros.
