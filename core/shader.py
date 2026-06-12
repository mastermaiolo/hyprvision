"""
HyprVision · Compositor de Shaders (GLSL ES 3.00)

Formato oficial Hyprland (ver Hyprland/example/screenShader.frag):
    #version 300 es
    precision mediump float;
    in vec2 v_texcoord;
    layout(location = 0) out vec4 fragColor;
    uniform sampler2D tex;

    void main() {
        vec4 pixColor = texture(tex, v_texcoord);
        ...
        fragColor = pixColor;
    }

Os shaders compostos (merge perfil + overlays) são escritos em
$XDG_RUNTIME_DIR/hyprvision (tmpfs por-utilizador), nunca em /tmp
partilhado — evita colisões com ficheiros de outras aplicações.
"""
import os
import re
import subprocess
import tempfile
from abc import ABC, abstractmethod


# ── Backend abstracto ────────────────────────────────────────────────
class ShaderBackend(ABC):
    @abstractmethod
    def apply(self, path: str) -> None: ...
    @abstractmethod
    def reset(self)            -> None: ...


# Declaração real do uniform `time` — uma menção em comentário não conta
_TIME_UNIFORM_RE = re.compile(
    r"^\s*uniform\s+(?:highp\s+|mediump\s+|lowp\s+)?float\s+time\s*;",
    re.MULTILINE
)


def shader_is_animated(path: str) -> bool:
    """Shaders que declaram `uniform float time` precisam de redraw contínuo."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return bool(_TIME_UNIFORM_RE.search(f.read()))
    except OSError:
        return False


class HyprctlBackend(ShaderBackend):
    """Aplica shaders via hyprctl keyword decoration:screen_shader."""

    @staticmethod
    def _set_tracking(value: str) -> None:
        subprocess.run(
            ["hyprctl", "keyword", "debug:damage_tracking", value],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    @staticmethod
    def _set_shader(path: str) -> None:
        r = subprocess.run(
            ["hyprctl", "keyword", "decoration:screen_shader", path],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            raise RuntimeError(f"hyprctl falhou: {r.stderr.strip()}")

    def apply(self, path: str) -> None:
        if not os.path.isfile(path):
            raise FileNotFoundError(f"Shader não encontrado: {path}")

        # A ordem importa: o Hyprland valida o shader ACTIVO sempre que o
        # damage_tracking muda. Shader animado → desligar tracking antes de
        # o carregar; shader estático → carregá-lo primeiro e só depois
        # subir o tracking (senão o aviso "uniform 'time'" dispara com o
        # shader animado anterior ainda activo).
        if shader_is_animated(path):
            self._set_tracking("0")   # 0 = sem damage tracking (mais GPU)
            self._set_shader(path)
        else:
            self._set_shader(path)
            self._set_tracking("2")   # 2 = tracking completo (normal)

    def reset(self) -> None:
        subprocess.run(
            ["hyprctl", "keyword", "decoration:screen_shader", ""],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        self._set_tracking("2")


# ── Compositor de 3 camadas ──────────────────────────────────────────
PAPER_INTENSITY = {
    "off":    0.0,
    "light":  0.028,
    "medium": 0.052,
    "heavy":  0.085,
}

# Declarações globais a remover dos shaders antes de embutir no wrapper
_GLOBAL_RE = re.compile(
    r"^\s*("
    r"#version[^\n]*"
    r"|precision\s"
    r"|in\s+vec2\s+v_texcoord"
    r"|varying\s+vec2\s+v_texcoord"
    r"|layout\s*\([^)]+\)\s+out\s+vec4\s+fragColor"
    r"|out\s+vec4\s+fragColor"
    r"|uniform\s+sampler2D\s+tex\b"
    r")",
    re.MULTILINE
)

_MERGED_PREFIX = "merged-"


def merged_dir() -> str:
    """Pasta por-utilizador para shaders compostos (tmpfs quando possível)."""
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/hyprvision-{os.getuid()}"
    d = os.path.join(base, "hyprvision")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def _strip_globals(src: str) -> str:
    """Remove declarações globais que o wrapper vai re-declarar."""
    lines = [l for l in src.splitlines() if not _GLOBAL_RE.match(l)]
    return "\n".join(lines)


def _render_template(src: str, params: dict) -> str:
    """Substitui {{key}} e {{ key }} pelos valores do dict."""
    for k, v in params.items():
        src = src.replace(f"{{{{ {k} }}}}", str(v))
        src = src.replace(f"{{{{{k}}}}}",   str(v))
    return src


def _write_merged(src: str) -> str:
    d = merged_dir()
    fd, tmp = tempfile.mkstemp(prefix=_MERGED_PREFIX, suffix=".glsl", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(src)
    _cleanup_old_merged(tmp)
    return tmp


def compose_shader(
    profile_glsl:  str | None,
    paper_texture: str = "off",
    dim_level:     int = 0,
    params:        dict = None,
) -> str | None:
    """
    Constrói shader merged ou devolve o shader base directamente.
    Retorna o path do .glsl, ou None se nada está activo (reset).
    """
    params = params or {}
    has_profile = bool(profile_glsl)
    has_paper   = paper_texture != "off"
    has_dim     = dim_level > 0
    pi = PAPER_INTENSITY.get(paper_texture, 0.0)
    da = dim_level / 100.0

    # Nada activo → reset
    if not has_profile and not has_paper and not has_dim:
        return None

    # Só perfil base sem overlays → devolve directamente (ou render template)
    if has_profile and not has_paper and not has_dim:
        if params:
            src = open(profile_glsl, "r", encoding="utf-8").read()
            return _write_merged(_render_template(src, params))
        return profile_glsl

    # Caso composto — constrói wrapper ES 3.00
    profile_body = ""
    profile_call = ""
    if has_profile:
        raw = open(profile_glsl, "r", encoding="utf-8").read()
        if params:
            raw = _render_template(raw, params)
        body = _strip_globals(raw)
        # Renomeia fragColor (saída do perfil) → _fc para o merge
        # Também trata gl_FragColor de shaders antigos
        body = re.sub(r'\bfragColor\b', '_fc', body)
        body = re.sub(r'\bgl_FragColor\b', '_fc', body)
        body = re.sub(r'\btexture2D\b', 'texture', body)
        body = body.replace("void main()", "void _profile_main()")
        profile_body = body
        profile_call = "    _profile_main();"

    merged = f"""\
#version 300 es
// HyprVision · Shader Composto (gerado automaticamente)
// perfil={os.path.basename(profile_glsl or 'none')}
// paper_texture={paper_texture}  dim={dim_level}%
// highp obrigatório: o ruído fract(sin(x*43758)) excede o alcance de
// fp16 (mediump em Mesa/AMD) e produz NaN → ecrã preto.
precision highp float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

float _paperNoise(vec2 p) {{
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp);
    float a = fract(sin(dot(ip,                  vec2(127.1, 311.7))) * 43758.5);
    float b = fract(sin(dot(ip + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5);
    float c = fract(sin(dot(ip + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5);
    float d = fract(sin(dot(ip + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5);
    return mix(mix(a, b, fp.x), mix(c, d, fp.x), fp.y);
}}

vec4 _fc;

{profile_body}

void main() {{
    _fc = texture(tex, v_texcoord);

    // Camada 1: Perfil base
{profile_call}

    // Camada 2: Paper Texture (superfície e-ink: fibras + grão + mottling)
    float _pi = {pi:.4f};
    if (_pi > 0.001) {{
        // Grão fino em duas oitavas
        float _g1 = _paperNoise(v_texcoord * 700.0);
        float _g2 = _paperNoise(v_texcoord * 1400.0 + vec2(0.37, 0.63));
        // Mottling de baixa frequência — manchas da polpa do papel
        float _m  = _paperNoise(v_texcoord * 90.0 + vec2(7.13, 3.71));
        // Fibras horizontais subtis (anisotropia do papel)
        float _fib = _paperNoise(vec2(v_texcoord.x * 110.0, v_texcoord.y * 900.0));
        float _tex = (_g1 * 0.55 + _g2 * 0.25 + _m * 0.45 + _fib * 0.35) - 0.80;

        // Visível em claros E escuros — papel e-ink é superfície
        // reflectiva, a textura não desaparece nas sombras
        float _lum  = dot(_fc.rgb, vec3(0.2126, 0.7152, 0.0722));
        float _mask = 0.55 + _lum * 0.45;
        // Ganho 3.5 calibrado visualmente: ~7/255 rms no nível heavy
        // em fundo escuro — visível sem estorvar a leitura.
        _fc.rgb += _tex * _pi * 3.5 * _mask;

        // Papel nunca é preto puro: lift quente das sombras,
        // proporcional à intensidade do overlay
        vec3  _paperTint = vec3(1.0, 0.97, 0.90) * (0.045 + _m * 0.025);
        float _shadow    = 1.0 - smoothstep(0.0, 0.18, _lum);
        _fc.rgb = mix(_fc.rgb, _paperTint, min(_pi * 4.0, 0.4) * _shadow);

        // Tom: grão ligeiramente quente (fibra de celulose)
        _fc.r += _g1 * _pi * 0.10;
        _fc.b -= _g1 * _pi * 0.18;
    }}

    // Camada 3: Extra Dim
    _fc.rgb *= (1.0 - {da:.4f});

    fragColor = vec4(clamp(_fc.rgb, 0.0, 1.0), _fc.a);
}}
"""
    return _write_merged(merged)


def _cleanup_old_merged(keep: str) -> None:
    """Apaga shaders compostos antigos — apenas os nossos, na nossa pasta."""
    import glob
    for old in glob.glob(os.path.join(merged_dir(), f"{_MERGED_PREFIX}*.glsl")):
        if old != keep:
            try:
                os.remove(old)
            except OSError:
                pass
