# HyprVision · Pasta de ICC Profiles

Coloca aqui os teus ficheiros `.icc` ou `.icm`.

## De onde vêm perfis ICC?

- **DisplayCal** — calibra o teu monitor e gera um .icc personalizado (recomendado)
- **Fabricante do monitor** — muitos monitores têm perfis no site oficial
- `/usr/share/color/icc/` — perfis do sistema já instalados
- `~/.local/share/icc/` — perfis instalados pelo colord/GNOME Color Manager

## Como usar num perfil HyprVision

Num ficheiro TOML de perfil, adiciona:

```toml
[icc]
file = "meu_monitor.icc"
```

O HyprVision procura o ficheiro:
1. Nesta pasta (`icc/`)
2. Em `~/.local/share/icc/`
3. Em `/usr/share/color/icc/`
4. Path absoluto (se começar com `/`)

## Exemplo: Cinema Film com ICC

```toml
# profiles/experience/cinema_film.toml
[icc]
file = "sRGB_Color_Space_Profile.icm"   # perfil sRGB genérico para cinema
```

## Notas

- O campo `[icc]` é **completamente opcional** — perfis sem ICC funcionam normalmente
- Requer Hyprland ≥ 0.55 (suporte a ICC por output)
- Para desactivar ICC num perfil, omite a secção `[icc]` ou deixa `file = ""`
