"""
HyprVision v4 · Leitor de daemon_config.toml
Carregado pelo daemon, pelo CLI e pelo apply pipeline.
Suporta valores omissos com defaults seguros.

Convenção: o valor de perfil "none" (ou vazio) significa "não fazer nada"
nesse evento — permite desactivar uma acção sem desligar a secção inteira.
"""
import os
import re
import tomllib
from dataclasses import dataclass, field


CONFIG_PATH = os.path.expanduser("~/.config/hypr/hyprvision/daemon_config.toml")

# ── Estruturas de configuração ────────────────────────────────────────

@dataclass
class ScheduleSlot:
    name:    str
    enabled: bool
    hour:    int
    minute:  int
    profile: str

    @property
    def minutes_of_day(self) -> int:
        return self.hour * 60 + self.minute


@dataclass
class BatteryConfig:
    enabled:           bool = True
    threshold:         int  = 20
    plugged:           str  = "none"
    unplugged:         str  = "none"
    low:               str  = "eink"
    # Ao sair do estado "low" (carregador ligado / bateria recuperou),
    # volta automaticamente ao perfil que estava activo antes.
    restore_after_low: bool = True


@dataclass
class ScheduleConfig:
    enabled: bool = True
    # Se True, aplica o slot actual logo que o daemon arranca
    # (por omissão respeita o último perfil escolhido manualmente).
    apply_on_start: bool = False
    slots: list[ScheduleSlot] = field(default_factory=list)


@dataclass
class KeybindEntry:
    mods: str
    key:  str


@dataclass
class DaemonConfig:
    enabled:  bool           = True
    battery:  BatteryConfig  = field(default_factory=BatteryConfig)
    schedule: ScheduleConfig = field(default_factory=ScheduleConfig)
    keybinds: dict[str, KeybindEntry] = field(default_factory=dict)
    # ICC: caminho base onde o utilizador guarda os seus .icc/.icm
    icc_dir:  str = ""


def profile_action(name: str) -> str | None:
    """Normaliza um valor de perfil de config: 'none'/'' → None."""
    name = (name or "").strip()
    if not name or name.lower() == "none":
        return None
    return name


# ── Defaults de horário quando não há TOML ───────────────────────────
_DEFAULT_SCHEDULE = [
    ScheduleSlot(name="dawn",  enabled=True, hour=6,  minute=0, profile="reset"),
    ScheduleSlot(name="night", enabled=True, hour=21, minute=0, profile="night"),
]

_SLOT_KEYS = ["dawn", "morning", "noon", "evening", "night"]


# ── Loader ────────────────────────────────────────────────────────────

def load(path: str = CONFIG_PATH) -> DaemonConfig:
    """
    Lê o daemon_config.toml. Se o ficheiro não existir ou for inválido,
    devolve os defaults — o daemon nunca falha por falta de config.
    """
    if not os.path.isfile(path):
        cfg = DaemonConfig()
        cfg.schedule.slots = list(_DEFAULT_SCHEDULE)
        return cfg

    try:
        with open(path, "rb") as f:
            raw = tomllib.load(f)
    except Exception as e:
        print(f"[HyprVision] Aviso: não foi possível ler {path}: {e}")
        cfg = DaemonConfig()
        cfg.schedule.slots = list(_DEFAULT_SCHEDULE)
        return cfg

    # [daemon]
    daemon_sect = raw.get("daemon", {})
    enabled = daemon_sect.get("enabled", True)

    # [battery]
    bat = raw.get("battery", {})
    battery = BatteryConfig(
        enabled           = bat.get("enabled",           True),
        threshold         = int(bat.get("threshold",     20)),
        plugged           = bat.get("plugged",           "none"),
        unplugged         = bat.get("unplugged",         "none"),
        low               = bat.get("low",               "eink"),
        restore_after_low = bat.get("restore_after_low", True),
    )

    # [schedule]
    sched_sect = raw.get("schedule", {})
    sched_enabled  = sched_sect.get("enabled", True)
    apply_on_start = sched_sect.get("apply_on_start", False)
    slots = []
    for key in _SLOT_KEYS:
        if key in sched_sect and isinstance(sched_sect[key], dict):
            s = sched_sect[key]
            slots.append(ScheduleSlot(
                name    = key,
                enabled = s.get("enabled", True),
                hour    = int(s.get("hour",   0)),
                minute  = int(s.get("minute", 0)),
                profile = s.get("profile", "none"),
            ))
    # Se não houver nenhum slot definido, usa defaults
    if not slots:
        slots = list(_DEFAULT_SCHEDULE)
    schedule = ScheduleConfig(
        enabled        = sched_enabled,
        apply_on_start = apply_on_start,
        slots          = slots,
    )

    # [keybinds]
    kb_sect = raw.get("keybinds", {})
    keybinds = {}
    for action_id, val in kb_sect.items():
        if isinstance(val, dict):
            keybinds[action_id] = KeybindEntry(
                mods = val.get("mods", "SUPER"),
                key  = val.get("key",  "F9"),
            )

    # icc_dir (raiz, opcional)
    icc_dir = os.path.expanduser(raw.get("icc_dir", ""))

    return DaemonConfig(
        enabled  = enabled,
        battery  = battery,
        schedule = schedule,
        keybinds = keybinds,
        icc_dir  = icc_dir,
    )


# ── Template completo ─────────────────────────────────────────────────
# Tudo o que o daemon faz está aqui, explícito — sem defaults invisíveis.

DEFAULT_TOML = """\
# HyprVision · Configuração do daemon
# Editar e correr `hyprvision --reload-daemon` para aplicar sem reiniciar.
#
# Em qualquer campo "profile": usa o id de um perfil (reset, night, focus,
# eink, paper, paper_soft, cinema_desktop, cinema_film, tn_recovery)
# ou "none" para não fazer nada nesse evento.

[daemon]
enabled = true

[battery]
enabled   = true
threshold = 20        # % abaixo da qual entra em modo "low"
plugged   = "none"    # carregador ligado          ("none" = manter perfil)
unplugged = "none"    # desconectado, bateria ok   ("none" = manter perfil)
low       = "eink"    # bateria abaixo do threshold
restore_after_low = true   # ao recuperar, volta ao perfil anterior

[schedule]
enabled        = true
apply_on_start = false   # true = aplica o slot actual logo no arranque
dawn    = { enabled = true,  hour = 6,  profile = "reset"          }
morning = { enabled = false, hour = 9,  profile = "cinema_desktop" }
noon    = { enabled = false, hour = 14, profile = "focus"          }
evening = { enabled = false, hour = 19, profile = "paper_soft"     }
night   = { enabled = true,  hour = 21, profile = "night"          }

# Pasta onde guardas os teus perfis ICC (.icc/.icm) — opcional
# icc_dir = "~/.config/hypr/hyprvision/icc"
"""

_KEYBINDS_RE = re.compile(r"^\[keybinds\]\n(?:[^\[]*)", re.MULTILINE)


def ensure_full_config(path: str = CONFIG_PATH) -> bool:
    """
    Garante que o daemon_config.toml existe e contém todas as secções.
    Preserva a secção [keybinds] existente (gerida pelo hyprvision-setup).
    Devolve True se o ficheiro foi criado/completado.
    """
    existing = ""
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            existing = f.read()

    # Já tem as secções principais → nada a fazer
    if all(f"[{s}]" in existing for s in ("daemon", "battery", "schedule")):
        return False

    # Recupera o bloco [keybinds] actual, se existir
    kb_block = ""
    m = _KEYBINDS_RE.search(existing)
    if m:
        kb_block = m.group(0).rstrip() + "\n"
    else:
        kb_block = "[keybinds]\n# Gerido pelo hyprvision-setup. Não editar manualmente.\n"

    content = DEFAULT_TOML + "\n" + kb_block
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return True
