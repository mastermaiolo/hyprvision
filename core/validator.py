import os
from .models import Profile

class ProfileValidator:
    """Valida perfis TOML contra limites de segurança."""

    MIN_TEMP       = 2500
    MAX_TEMP       = 9000
    MIN_BRIGHTNESS = 0.05
    MAX_BRIGHTNESS = 1.5
    MIN_GAMMA      = 0.5
    MAX_GAMMA      = 2.0

    @classmethod
    def validate(cls, profile: Profile, shader_search_dirs: list[str]) -> bool:
        g = profile.gamma

        if not (cls.MIN_TEMP <= g.temperature <= cls.MAX_TEMP):
            raise ValueError(
                f"Temperatura {g.temperature}K fora dos limites "
                f"[{cls.MIN_TEMP}–{cls.MAX_TEMP}K]"
            )
        if not (cls.MIN_BRIGHTNESS <= g.brightness <= cls.MAX_BRIGHTNESS):
            raise ValueError(
                f"Brightness {g.brightness} fora dos limites "
                f"[{cls.MIN_BRIGHTNESS}–{cls.MAX_BRIGHTNESS}]"
            )
        if not (cls.MIN_GAMMA <= g.gamma <= cls.MAX_GAMMA):
            raise ValueError(
                f"Gamma {g.gamma} fora dos limites "
                f"[{cls.MIN_GAMMA}–{cls.MAX_GAMMA}]"
            )

        if profile.shader.enabled and profile.shader.file:
            found = any(
                os.path.isfile(os.path.join(d, profile.shader.file))
                for d in shader_search_dirs
            )
            if not found:
                raise ValueError(
                    f"Shader '{profile.shader.file}' não encontrado "
                    f"em nenhuma pasta de shaders."
                )

        return True
