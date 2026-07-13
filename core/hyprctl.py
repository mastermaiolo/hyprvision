"""
HyprVision · Camada única de escrita de opções no Hyprland.

Hyprland com config Lua (hyprland.lua, parser "non-legacy") rejeita
`hyprctl keyword` — mas com exit code 0 e a mensagem "keyword can't
work with non-legacy parsers. Use eval.", ou seja, a falha é invisível
para quem só olha ao returncode. Este módulo tenta `keyword` uma vez e,
ao detectar o parser Lua, passa a usar `hyprctl eval` (hl.config /
hl.monitor) em todas as escritas seguintes do processo.
"""
import subprocess

_use_eval = False   # detectado na primeira escrita e memorizado


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True)


def _ok(r: subprocess.CompletedProcess) -> bool:
    return r.returncode == 0 and "ok" in (r.stdout or "")


def _lua_value(value) -> str:
    s = str(value)
    if s.lstrip("-").replace(".", "", 1).isdigit():
        return s
    return f"[[{s}]]"


def _lua_config_expr(option: str, value) -> str:
    expr = _lua_value(value)
    for key in reversed(option.split(":")):
        expr = f"{{ {key} = {expr} }}"
    return f"hl.config({expr})"


def set_option(option: str, value) -> bool:
    """Escreve uma opção (ex.: decoration:screen_shader) por keyword ou eval."""
    global _use_eval
    if not _use_eval:
        r = _run(["keyword", option, str(value)])
        if "non-legacy" not in (r.stdout or "") + (r.stderr or ""):
            return _ok(r)
        _use_eval = True
    return _ok(_run(["eval", _lua_config_expr(option, value)]))


def set_monitor_icc(mon: dict, icc_path: str) -> bool:
    """(Re)define um monitor mantendo o modo actual, com/sem perfil ICC."""
    global _use_eval
    name  = mon.get("name", "")
    mode  = f"{mon.get('width', 1920)}x{mon.get('height', 1080)}" \
            f"@{mon.get('refreshRate', 60.0)}"
    pos   = f"{mon.get('x', 0)}x{mon.get('y', 0)}"
    scale = mon.get("scale", 1.0)

    if not _use_eval:
        spec = f"{name},{mode},{pos},{scale},icc,{icc_path}"
        r = _run(["keyword", "monitor", spec])
        if "non-legacy" not in (r.stdout or "") + (r.stderr or ""):
            return _ok(r)
        _use_eval = True

    return _ok(_run(["eval",
        f"hl.monitor({{ output = [[{name}]], mode = [[{mode}]], "
        f"position = [[{pos}]], scale = {scale}, icc = [[{icc_path}]] }})"]))
