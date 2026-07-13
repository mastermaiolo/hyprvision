#!/usr/bin/env python3
"""
HyprVision · self-check (sem frameworks: `python3 test_hyprvision.py`)
Cobre a lógica não-trivial: compositor de shaders, wrap de horários,
round-trip do state, validador e sintaxe GLSL de todos os shaders.
Não toca no estado real: corre num XDG_RUNTIME_DIR temporário.
"""
import glob
import importlib.machinery
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace

ROOT = os.path.abspath(os.path.dirname(__file__))
sys.path.insert(0, ROOT)

# Isola os shaders compostos num tmpdir descartável
_TMP = tempfile.mkdtemp(prefix="hyprvision-test-")
os.environ["XDG_RUNTIME_DIR"] = _TMP

from core.config import DaemonConfig, ScheduleSlot          # noqa: E402
from core.models import RuntimeState, OverlayState, Profile, GammaSettings  # noqa: E402
from core.shader import compose_shader, shader_is_animated  # noqa: E402
from core.state import StateManager                         # noqa: E402
from core.validator import ProfileValidator                 # noqa: E402


def _load_daemon_module():
    loader = importlib.machinery.SourceFileLoader(
        "hvdaemon", os.path.join(ROOT, "bin", "hyprvision-daemon"))
    spec = importlib.util.spec_from_loader("hvdaemon", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def test_shader_compose():
    night = os.path.join(ROOT, "shaders", "experience", "night.glsl")

    assert compose_shader(None, "off", 0) is None, "nada activo devia dar None (reset)"
    assert compose_shader(night, "off", 0) == night, "perfil puro devia passar directo"

    merged = compose_shader(night, "medium", 30)
    src = open(merged, encoding="utf-8").read()
    assert "precision highp float;" in src, "wrapper tem de forçar highp"
    assert "_profile_main()" in src, "main do perfil devia ser renomeado"
    assert "0.0520" in src and "0.3000" in src, "intensidades paper/dim erradas"
    assert src.count("#version") == 1, "#version duplicado no shader composto"

    dim_only = compose_shader(None, "off", 20)
    assert dim_only and "0.2000" in open(dim_only, encoding="utf-8").read()


def test_shader_template_params():
    with tempfile.NamedTemporaryFile("w", suffix=".glsl", delete=False) as f:
        f.write("void main() { fragColor = vec4(vec3({{ strength }}), 1.0); }")
        path = f.name
    merged = compose_shader(path, "off", 0, params={"strength": 0.42})
    assert "0.42" in open(merged, encoding="utf-8").read(), "{{ param }} não substituído"
    os.remove(path)


def test_shader_animated_detection():
    def _tmp(src):
        f = tempfile.NamedTemporaryFile("w", suffix=".glsl", delete=False)
        f.write(src); f.close()
        return f.name
    yes = _tmp("uniform float time;\nvoid main(){}")
    no  = _tmp("// uniform float time; (comentário)\nvoid main(){}")
    assert shader_is_animated(yes) is True
    assert shader_is_animated(no) is False
    os.remove(yes); os.remove(no)


def test_schedule_wrap():
    daemon = _load_daemon_module()
    cfg = DaemonConfig()
    cfg.schedule.slots = [
        ScheduleSlot("dawn",  True, 6,  0, "reset"),
        ScheduleSlot("night", True, 21, 0, "night"),
    ]

    import datetime as real_dt
    def _at(h, m):
        daemon.datetime = SimpleNamespace(datetime=SimpleNamespace(
            now=lambda: real_dt.datetime(2026, 1, 1, h, m)))
        slot = daemon.current_schedule_slot(cfg)
        return slot.name if slot else None

    assert _at(5, 30) == "night", "antes do 1º slot devia fazer wrap para o último"
    assert _at(6, 0)  == "dawn"
    assert _at(12, 0) == "dawn"
    assert _at(21, 0) == "night"
    assert _at(23, 59) == "night"


def test_state_roundtrip():
    d = tempfile.mkdtemp(prefix="hv-state-")
    mgr = StateManager(os.path.join(d, "s.json"))
    st = RuntimeState(active_profile="night", temperature=3500, shader="night.glsl",
                      overlay=OverlayState(paper_texture="heavy", dim_level=40))
    mgr.write_state(st)
    back = mgr.read_state()
    assert back == st, "round-trip do state perdeu dados"

    # Tolerância a chaves desconhecidas (state de versão futura)
    import json
    data = json.load(open(mgr.state_file))
    data["campo_do_futuro"] = 123
    json.dump(data, open(mgr.state_file, "w"))
    assert mgr.read_state().active_profile == "night"
    shutil.rmtree(d)


def test_validator_limits():
    p = Profile(id="x", gamma=GammaSettings(temperature=99999))
    try:
        ProfileValidator.validate(p, [])
        raise AssertionError("temperatura absurda devia falhar validação")
    except ValueError:
        pass
    ProfileValidator.validate(Profile(id="ok"), [])


def test_hyprctl_lua_expr():
    from core.hyprctl import _lua_config_expr, _lua_value
    assert _lua_config_expr("decoration:screen_shader", "/a b/x.glsl") == \
        "hl.config({ decoration = { screen_shader = [[/a b/x.glsl]] } })"
    assert _lua_config_expr("debug:damage_tracking", "0") == \
        "hl.config({ debug = { damage_tracking = 0 } })"
    assert _lua_value(1.5) == "1.5" and _lua_value("") == "[[]]"


def test_glsl_syntax():
    tool = shutil.which("glslangValidator")
    if not tool:
        print("  (glslangValidator ausente — validação GLSL saltada)")
        return
    bad, count = [], 0

    def _check(path):
        nonlocal count
        count += 1
        r = subprocess.run([tool, "--stdin", "-S", "frag"],
                           input=open(path, encoding="utf-8").read(),
                           capture_output=True, text=True)
        if r.returncode != 0:
            bad.append((path, r.stdout.strip()))

    for f in glob.glob(os.path.join(ROOT, "shaders", "**", "*.glsl"), recursive=True):
        _check(f)
    # Compostos: validar um de cada vez — compose_shader apaga o merged anterior
    night = os.path.join(ROOT, "shaders", "experience", "night.glsl")
    for lvl in ("light", "medium", "heavy"):
        _check(compose_shader(night, lvl, 30))
    assert not bad, "GLSL inválido:\n" + "\n".join(f"{f}\n{e}" for f, e in bad)
    print(f"  ({count} shaders GLSL validados)")


def test_launcher_applies_selection():
    """Smoke test do launcher: rofi falso escolhe um perfil → o CLI tem de
    receber --apply. Apanha regressões de fluxo/set -e no bash."""
    sand = tempfile.mkdtemp(prefix="hyprvision-launcher-")
    calls = os.path.join(sand, "calls.log")
    for d in ("ui", "bin", "rofi", "fakebin"):
        os.makedirs(os.path.join(sand, d))
    shutil.copy(os.path.join(ROOT, "ui", "launcher.sh"),
                os.path.join(sand, "ui", "launcher.sh"))
    open(os.path.join(sand, "rofi", "hyprvision.rasi"), "w").close()

    fake_cli = os.path.join(sand, "bin", "hyprvision")
    with open(fake_cli, "w") as f:
        f.write(f"""#!/usr/bin/env bash
echo "$@" >> {calls}
case "$1" in
  --status) printf 'Perfil     : reset\\nExtra      : (nenhum)\\nPaper Tex  : off\\nDim        : 0%%\\nDaemon     : parado\\n' ;;
  --list-rofi) printf "🌙 Night   <span size='small'>[night]</span>\\n" ;;
esac
""")
    with open(os.path.join(sand, "fakebin", "rofi"), "w") as f:
        f.write('#!/usr/bin/env bash\ngrep -m1 night\n')   # "escolhe" a linha night
    with open(os.path.join(sand, "fakebin", "notify-send"), "w") as f:
        f.write('#!/usr/bin/env bash\nexit 0\n')
    for p in (fake_cli, os.path.join(sand, "fakebin", "rofi"),
              os.path.join(sand, "fakebin", "notify-send")):
        os.chmod(p, 0o755)

    env = dict(os.environ, PATH=os.path.join(sand, "fakebin") + ":" + os.environ["PATH"])
    r = subprocess.run(["bash", os.path.join(sand, "ui", "launcher.sh")],
                       capture_output=True, text=True, env=env, timeout=15)
    logged = open(calls).read() if os.path.exists(calls) else ""
    shutil.rmtree(sand, ignore_errors=True)
    assert "--apply night" in logged, \
        f"launcher não chegou ao --apply (exit={r.returncode}); chamadas:\n{logged}"


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        print(f"• {t.__name__}")
        t()
    shutil.rmtree(_TMP, ignore_errors=True)
    print(f"\n✓ {len(tests)} testes OK")
