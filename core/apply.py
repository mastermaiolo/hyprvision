"""
HyprVision v4 · Pipeline de aplicação central
Orquestra: perfil TOML → validação → shader composto → gamma → ICC → state

Contrato: os métodos públicos devolvem True/False e NUNCA terminam o
processo — quem decide o exit code é o CLI; o daemon precisa de
sobreviver a qualquer falha de aplicação.
"""
import os
import sys
from .models import RuntimeState, OverlayState
from .profile import ProfileLoader
from .validator import ProfileValidator
from .gamma import get_best_gamma_backend, WlGammaRelayBackend
from .shader import HyprctlBackend, compose_shader
from .icc import apply_icc, reset_icc, resolve_icc_path
from .state import StateManager
from .notify import notify


class ApplyPipeline:
    """Orquestrador central: carrega → valida → aplica perfil + overlays + ICC."""

    def __init__(self, base_dir: str):
        self.base_dir     = base_dir
        self.profiles_dir = os.path.join(base_dir, "profiles")
        self.shaders_dir  = os.path.join(base_dir, "shaders")
        self.state_file   = os.path.join(base_dir, "state", "current_state.json")
        self.icc_dir      = os.path.join(base_dir, "icc")
        self.extras_dir   = os.path.join(self.shaders_dir, "extras")

        self.state_mgr    = StateManager(self.state_file)
        self.shader_be    = HyprctlBackend()
        self.loader       = ProfileLoader(self.profiles_dir)

        self._shader_search = [
            self.shaders_dir,
            os.path.join(self.shaders_dir, "correction"),
            os.path.join(self.shaders_dir, "experience"),
            self.extras_dir,
        ]

    # ── Utilitários ──────────────────────────────────────────────────

    def _find_shader(self, filename: str) -> str | None:
        if not filename:
            return None
        if os.path.isabs(filename):
            return filename if os.path.isfile(filename) else None
        for d in self._shader_search:
            p = os.path.join(d, filename)
            if os.path.isfile(p):
                return p
        return None

    def _get_gamma(self):
        try:
            return get_best_gamma_backend()
        except RuntimeError as e:
            notify("HyprVision", str(e), "critical")
            print(f"[HyprVision] {e}", file=sys.stderr)
            return None

    def _resolve_icc(self, icc_file: str) -> str | None:
        """Resolve ICC usando pasta do perfil, pasta global e locais padrão."""
        try:
            from .config import load as load_cfg
            cfg_icc_dir = load_cfg().icc_dir or self.icc_dir
        except Exception:
            cfg_icc_dir = self.icc_dir
        return resolve_icc_path(icc_file, cfg_icc_dir)

    # ── Acções principais ────────────────────────────────────────────

    def safe_reset(self) -> bool:
        """Reset de emergência — limpa shader, ICC, gamma E overlays no state."""
        try:
            self.shader_be.reset()
            reset_icc()
            g = self._get_gamma()
            if g:
                g.reset()
                g.commit()
            self.state_mgr.clear_state()
            notify("HyprVision: Reset", "Ecrã reposto ao estado neutro.")
            print("[HyprVision] Safe reset aplicado.")
            return True
        except Exception as e:
            notify("HyprVision", f"Erro no reset: {e}", "critical")
            print(f"[HyprVision] Erro no reset: {e}", file=sys.stderr)
            return False

    def apply_profile(self, profile_id: str, quiet: bool = False) -> bool:
        """Aplica um perfil, preservando os overlays activos."""
        try:
            profile = self.loader.load_by_id(profile_id)

            # Perfil "reset" — limpa tudo incluindo overlays
            if profile_id == "reset":
                return self.safe_reset()

            overlay = self.state_mgr.read_state().overlay
            ProfileValidator.validate(profile, self._shader_search)

            # ── Shader ───────────────────────────────────────────────
            shader_path = None
            if profile.shader.enabled and profile.shader.file:
                shader_path = self._find_shader(profile.shader.file)
                if not shader_path:
                    raise FileNotFoundError(
                        f"Shader '{profile.shader.file}' não encontrado."
                    )

            composed = compose_shader(
                profile_glsl  = shader_path,
                paper_texture = overlay.paper_texture,
                dim_level     = overlay.dim_level,
                params        = profile.shader.parameters,
            )
            if composed:
                self.shader_be.apply(composed)
            else:
                self.shader_be.reset()

            # ── ICC ───────────────────────────────────────────────────
            icc_applied = ""
            if profile.icc.file:
                resolved = self._resolve_icc(profile.icc.file)
                if resolved:
                    if apply_icc(resolved):
                        icc_applied = resolved
                        print(f"[HyprVision] ICC aplicado: {resolved}")
                    else:
                        print(f"[HyprVision] Aviso: falha ao aplicar ICC {resolved}",
                              file=sys.stderr)
                else:
                    print(f"[HyprVision] Aviso: ICC '{profile.icc.file}' não encontrado.",
                          file=sys.stderr)
            else:
                # Perfil sem ICC — remove qualquer ICC anterior
                reset_icc()

            # ── Gamma ─────────────────────────────────────────────────
            g = self._get_gamma()
            if g:
                if isinstance(g, WlGammaRelayBackend):
                    g.set_temperature(profile.gamma.temperature)
                    g.set_brightness(profile.gamma.brightness)
                    g.set_gamma(profile.gamma.gamma)
                else:
                    g.set_temperature(profile.gamma.temperature)
                g.commit()

            # ── State ─────────────────────────────────────────────────
            # Aplicar um perfil substitui qualquer shader "extra" activo.
            new_state = RuntimeState(
                active_profile = profile.id,
                active_layers  = [profile.id],
                temperature    = profile.gamma.temperature,
                brightness     = profile.gamma.brightness,
                gamma          = profile.gamma.gamma,
                shader         = profile.shader.file if profile.shader.enabled else "",
                icc            = icc_applied,
                extra_shader   = "",
                overlay        = overlay,
            )
            self.state_mgr.write_state(new_state)

            if not quiet:
                notify("HyprVision", f"{profile.icon} {profile.name}")
            print(f"[HyprVision] Perfil aplicado: {profile.name}")
            return True

        except Exception as e:
            notify("HyprVision", f"Erro: {e}", "critical")
            print(f"[HyprVision] Erro ao aplicar '{profile_id}': {e}", file=sys.stderr)
            return False

    def apply_extra(self, shader_file: str) -> bool:
        """
        Aplica um shader "extra" (comunidade) por cima do estado actual,
        composto com os overlays e registado no state — fica visível no
        --status e sobrevive a um --restore.
        """
        try:
            path = shader_file
            if not os.path.isabs(path):
                path = os.path.join(self.extras_dir, shader_file)
            if not os.path.isfile(path):
                raise FileNotFoundError(f"Extra não encontrado: {shader_file}")

            state = self.state_mgr.read_state()
            composed = compose_shader(
                profile_glsl  = path,
                paper_texture = state.overlay.paper_texture,
                dim_level     = state.overlay.dim_level,
            )
            self.shader_be.apply(composed)

            state.extra_shader = path
            self.state_mgr.write_state(state)

            notify("HyprVision", f"🌐 Extra: {os.path.basename(path)}")
            print(f"[HyprVision] Extra aplicado: {path}")
            return True

        except Exception as e:
            notify("HyprVision", f"Erro extra: {e}", "critical")
            print(f"[HyprVision] Erro ao aplicar extra '{shader_file}': {e}",
                  file=sys.stderr)
            return False

    def set_overlay(self, paper_texture: str | None, dim_level: int | None) -> bool:
        """Actualiza overlays sem mudar o perfil base (nem o extra activo)."""
        try:
            state   = self.state_mgr.read_state()
            overlay = state.overlay

            if paper_texture is not None:
                overlay.paper_texture = paper_texture
            if dim_level is not None:
                overlay.dim_level = dim_level

            # O shader base é o extra activo, ou o shader do perfil
            shader_path = state.extra_shader or self._find_shader(state.shader)

            params = {}
            if not state.extra_shader:
                try:
                    p = self.loader.load_by_id(state.active_profile)
                    params = p.shader.parameters
                except Exception:
                    pass

            composed = compose_shader(
                profile_glsl  = shader_path,
                paper_texture = overlay.paper_texture,
                dim_level     = overlay.dim_level,
                params        = params,
            )
            if composed:
                self.shader_be.apply(composed)
            else:
                self.shader_be.reset()

            state.overlay = overlay
            self.state_mgr.write_state(state)

            parts = []
            if overlay.paper_texture != "off":
                parts.append(f"Paper Tex: {overlay.paper_texture}")
            if overlay.dim_level > 0:
                parts.append(f"Dim: {overlay.dim_level}%")
            label = "  ·  ".join(parts) if parts else "Overlays desligados"
            notify("HyprVision", label)
            print(f"[HyprVision] Overlay → {label}")
            return True

        except Exception as e:
            notify("HyprVision", f"Erro overlay: {e}", "critical")
            print(f"[HyprVision] Erro overlay: {e}", file=sys.stderr)
            return False

    def reapply_visuals(self) -> bool:
        """
        Reaplica shader + ICC após um config reload do Hyprland — o reload
        limpa todos os keywords (screen_shader, monitor/icc), apagando o
        efeito visual dos perfis. Não toca no gamma (sobrevive ao reload)
        e não notifica: é manutenção silenciosa, não uma acção do utilizador.
        """
        try:
            state = self.state_mgr.read_state()
            shader_path = state.extra_shader or self._find_shader(state.shader)

            params = {}
            if not state.extra_shader and state.active_profile:
                try:
                    params = self.loader.load_by_id(
                        state.active_profile).shader.parameters
                except Exception:
                    pass

            composed = compose_shader(
                profile_glsl  = shader_path,
                paper_texture = state.overlay.paper_texture,
                dim_level     = state.overlay.dim_level,
                params        = params,
            )
            if composed:
                self.shader_be.apply(composed)
            if state.icc:
                apply_icc(state.icc)
            return True
        except Exception as e:
            print(f"[HyprVision] Erro ao reaplicar visuais: {e}", file=sys.stderr)
            return False

    def restore(self) -> bool:
        """Restaura o último estado após reinício do Hyprland."""
        state = self.state_mgr.read_state()
        if not state.active_profile or state.active_profile == "reset":
            print("[HyprVision] Nenhum estado para restaurar.")
            return True

        print(f"[HyprVision] Restaurar: {state.active_profile}")
        extra = state.extra_shader   # apply_profile limpa o extra do state
        ok = self.apply_profile(state.active_profile, quiet=True)
        if ok and extra:
            ok = self.apply_extra(extra)
        return ok
