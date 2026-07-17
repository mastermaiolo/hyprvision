# HyprVision

[🇵🇹 Português](README.md) · 🇬🇧 **English** · [🇨🇳 简体中文](README.zh.md)

<p align="center"><img src="assets/profile_transition.gif" alt="Switching profiles in the HyprVision menu" width="480"></p>

**Native visual-ergonomics manager for Hyprland** — colour profiles with GLSL shaders, gamma/temperature/brightness, ICC profiles and composable overlays, all behind a Rofi menu. Runs entirely inside the compositor's Lua runtime: no daemon, no Python.

## Contents

[Features](#features) · [Included profiles](#included-profiles) · [Requirements](#requirements) · [Installation](#installation) · [Usage](#usage) · [Configuration](#configuration) · [Creating a profile](#creating-a-profile) · [Troubleshooting](#troubleshooting) · [Architecture](#architecture) · [Credits](#credits) · [Licence](#licence)

## Features

- **Visual profiles** defined in declarative Lua: shader + temperature + brightness + gamma + optional ICC
- **Composable overlays** on top of any profile:
  - *Paper Texture* (light/medium/heavy) — e-ink-style paper texture: two-octave grain, pulp mottling, anisotropic fibres and a warm shadow lift
  - *Extra Dim* (10–50%) — shader-based dimming, below the backlight's minimum
- **Anti-banding for 8-bit panels**: ~1 LSB dither always active in the composed shader + `render:use_fp16` (internal FP16 curves) + `render:icc_vcgt_enabled` (VCGT ramps via KMS)
- **Adaptive, no daemon**: profile switching by time of day and battery state (with automatic restore of the previous profile) via native `hl.timer`
- **Real persistence**: profiles survive `hyprctl reload` — the Lua runtime is recreated and `init.lua` restores state on load
- **Community extra shaders**: the `shaders/extras/` folder is wired into the menu
- **Rofi menu in 3 languages** (English, Portuguese, 中文, picked from the system locale) and following the current tonal colour: if you run [Caelestia](https://github.com/caelestia-dots/shell), the menu automatically follows your wallpaper's Material palette
- **Recoverable emergency reset** (`Super+Shift+H`): returns the screen to neutral and archives state to `state.bak` — the menu gains a "Recover last state" entry
- **Smooth transitions** for temperature/brightness/gamma via wl-gammarelay-rs (started on demand)

## Included profiles

| Profile | Category | What it's for |
|---|---|---|
| ✨ Cinema Desktop | correction | Subtle micro-contrast for everyday use |
| 🖥️ TN Recovery | correction | Compensation for washed-out TN panels |
| 🌌 Cinema OLED | experience | Crushed blacks + selective vibrance — an OLED look on an LCD |
| 🧡 Cinema OLED Warm | experience | Cinema OLED with a warmer temperature — films at night without eye strain |
| 🎬 Cinema Film | experience | S-curve, vignette and film grain |
| 📖 E-Ink | experience | E-ink-style desaturation (pairs well with Paper Texture) |
| 🕯️ E-Ink Warm Dark | experience | Warm, dark E-Ink — a Kindle by candlelight, deeper blacks |
| 🎯 Focus | experience | Concentration, distractions toned down |
| 🌙 Night | experience | Night-time, warm and dark |
| 📄 Paper | experience | Aged paper for reading and writing |
| 🌿 Paper Soft | experience | Even warmer, softer Paper, for long sessions |
| ⚡ Reset | system | Everything neutral |

## Requirements

- Hyprland ≥ 0.55 **with Lua config** (`~/.config/hypr/hyprland.lua`) — for the classic `hyprland.conf`, use v4 (tag `v4.1.0`)
- rofi
- **Recommended:** [wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs) — smooth temperature/brightness/gamma transitions
- Optional: libnotify (notifications); lua5.4 and glslangValidator are only needed to run the tests

## Installation

```bash
git clone https://github.com/mastermaiolo/hyprvision && cd hyprvision
./install.sh
```

The installer is interactive (English or 中文, based on the system locale) and, on a from-scratch install, also:
- checks for rofi, wl-gammarelay-rs and libnotify, and offers to install whatever's missing (pacman/apt/dnf; AUR via paru/yay for wl-gammarelay-rs);
- if `Super+H` or `Super+Shift+H` are already bound to something else, lets you pick a different key;
- asks whether you want to switch profiles manually or automatically by time of day (one day profile, one night profile).

After that, it copies everything to `~/.config/hypr/hyprvision`, adds `require("init")` to `hyprland.lua` and reloads Hyprland — it's active right away. Running it again updates without asking again or losing `config.lua` or state.

To uninstall (resets the screen and removes everything): `./uninstall.sh`.

Project self-check (state, profiles, compositor, schedules, battery, GLSL for every shader, menu smoke test): `lua5.4 test_hyprvision.lua`.

## Usage

`Super+H` opens the menu; `Super+Shift+H` is the emergency reset. For scripting, the same surface the menu uses:

```
hyprctl eval "hv.apply('night')"           apply a profile
hyprctl eval "hv.overlay('paper','medium')"  off | light | medium | heavy
hyprctl eval "hv.overlay('dim', 30)"       0 | 10 | 20 | 30 | 40 | 50
hyprctl eval "hv.apply_extra('x.glsl')"    an extra shader (in shaders/extras/)
hyprctl eval "hv.safe_reset()"             emergency reset
hyprctl eval "hv.restore_backup()"         recover the archived state
```

The current state is always readable at `~/.config/hypr/hyprvision/state/state` (key=value).

## Configuration

`~/.config/hypr/hyprvision/config.lua` — keybinds, schedules and battery. After editing: `hyprctl reload`. In any event, `profile = "none"` means "do nothing". Highlights:

- `battery.restore_after_low` — on recovering from low battery, automatically returns to whichever profile was active
- `schedule.apply_on_start` — defaults to `false`: startup respects your last profile; schedules only fire once the clock crosses a slot
- Slots accept `minute` in addition to `hour`

## Creating a profile

`profiles/my_profile.lua`:

```lua
-- One line about the profile.
return {
    name = "My Profile", icon = "🔥", category = "experience",
    temperature = 5800,   -- 2500–9000 K
    brightness  = 0.95,   -- 0.05–1.5
    gamma       = 1.0,    -- 0.5–2.0
    shader = "experience/my_profile.glsl",   -- in shaders/; nil = no shader
    -- icc = "my_monitor.icc",                -- optional, in icc/
}
```

**Important for shaders:** always use `precision highp float;`. With `mediump`, the classic noise trick `fract(sin(x) * 43758.5)` exceeds fp16's range on AMD/Mesa GPUs and produces NaN → **a fully black screen**. (Every shader shipped here is already fixed.)

## Troubleshooting

- **Screen went black/unreadable** → `Super+Shift+H` (safe reset); then "Recover last state" in the menu if that was a mistake.
- **Profile "disappeared" after touching the theme/config** → shouldn't happen (init restores on reload); check `state/hyprvision.log`.
- **Hyprland's "uniform 'time'" warning** → animated shaders require `debug:damage_tracking 0` (more GPU load); HyprVision handles this automatically, in the right order.
- Log: `~/.config/hypr/hyprvision/state/hyprvision.log`.

## Architecture

```
init.lua        compositor wiring: binds, timers, restore on load
core.lua        engine: state, profiles, GLSL compose, apply, gamma, ticks
config.lua      user configuration (keybinds, schedule, battery)
profiles/*.lua  declarative profiles
ui/launcher.sh  Rofi menu (reads state/, sends hyprctl eval "hv.*")
```

`hyprctl eval` doesn't return output, so the Lua side keeps `state/state` and `state/profiles.menu` as the read interface for the launcher. Composed shaders are generated under `$XDG_RUNTIME_DIR/hyprvision/`. Everything that runs inside the compositor is wrapped in `pcall` — a broken profile logs the error and never brings down a handler.

## Credits

The shaders in `shaders/extras/` come from the Hyprland community — kept as received, with only minimal compatibility tweaks (`highp`, see note above). Original authorship:

| Author | Project | Shaders |
|---|---|---|
| **[snes19xx](https://github.com/snes19xx)** | — | cinema, clarity_inefficient, crt_mode, focus, fuji_acros, gameboy, IBM5151, main, matte, night, night_vision, outdoor, reading_mode, soft, vhs |
| **0x15BA88FF** | [hyprshaders](https://github.com/0x15BA88FF/hyprshaders) | chromatic_abberation, colors, contrast, crt, drugs, extradark, grain, invert, retro, solarized |
| **Sijan-Bhusal** | [HyprShades](https://github.com/sijan-dev/HyprShades) | amoled, blue-light-filter, cyberpunk, matrix, retro |
| **ManofJELLO** | [HyprWindowShade](https://github.com/ManofJELLO/HyprWindowShade) | chromaGlitch, pixelate, wireframe |

Sources cited inside the shaders themselves:
- `0x15BA88FF_crt.frag` — © 2023 Maxim Samoliuk, MIT licence (full notice at the top of the file)
- `0x15BA88FF_colors.glsl` — based on a [discussion in the Hyprland repo](https://github.com/hyprwm/Hyprland/issues/1140#issuecomment-1614863627) and SweetFX's [Vibrance.fx](https://github.com/CeeJayDK/SweetFX/blob/a792aee788c6203385a858ebdea82a77f81c67f0/Shaders/Vibrance.fx#L20-L30)
- `0x15BA88FF_retro.glsl` — modified version of [wessles/GLSL-CRT](https://github.com/wessles/GLSL-CRT/blob/master/shader.frag)
- `0x15BA88FF_extradark.frag` — values adapted from a [ReShade forum thread](https://reshade.me/forum/shader-discussion/3673-blue-light-filter-similar-to-f-lux)

*(ManofJELLO's `HyprWindowShade` is a C++ plugin that applies shaders per-window — not the literal origin of the 3 files credited to him here, but it's the shader project of his we have at hand.)*

Thanks to all of them. If you authored one of these shaders and want an attribution fix, a licence note, or removal, please open an issue.

## Licence

MIT — see [LICENSE](LICENSE). Third-party shaders in `shaders/extras/` keep their own terms, noted in Credits above.

Version history: [CHANGELOG.md](CHANGELOG.md).
