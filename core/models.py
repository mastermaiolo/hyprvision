from dataclasses import dataclass, field
from typing import List

@dataclass
class GammaSettings:
    temperature: int   = 6500
    brightness:  float = 1.0
    gamma:       float = 1.0

@dataclass
class ShaderSettings:
    enabled:    bool  = False
    file:       str   = ""
    parameters: dict  = field(default_factory=dict)

@dataclass
class IccSettings:
    """Perfil ICC/ICM opcional. Vazio = sem ICC."""
    file: str = ""   # path absoluto ou relativo a icc_dir

@dataclass
class Profile:
    id:          str
    name:        str   = "Unknown"
    icon:        str   = "✨"
    description: str   = ""
    intensity:   str   = "subtle"
    category:    str   = "experience"
    gamma:       GammaSettings  = field(default_factory=GammaSettings)
    shader:      ShaderSettings = field(default_factory=ShaderSettings)
    icc:         IccSettings    = field(default_factory=IccSettings)

@dataclass
class OverlayState:
    paper_texture: str = "off"   # off | light | medium | heavy
    dim_level:     int = 0       # 0, 10, 20, 30, 40, 50

@dataclass
class RuntimeState:
    active_profile: str         = "reset"
    active_layers:  List[str]   = field(default_factory=list)
    temperature:    int         = 6500
    brightness:     float       = 1.0
    gamma:          float       = 1.0
    shader:         str         = ""
    icc:            str         = ""
    # Shader "extra" (comunidade) activo por cima do perfil — path absoluto.
    extra_shader:   str         = ""
    overlay:        OverlayState = field(default_factory=OverlayState)
