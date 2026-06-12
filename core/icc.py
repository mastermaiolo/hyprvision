"""
HyprVision v4 · Backend de ICC profiles
Aplica perfis ICC por output via hyprctl (Hyprland ≥ 0.55).

Uso:
  apply_icc("/path/to/profile.icc")     → aplica a todos os monitores
  reset_icc()                            → remove ICC de todos os monitores
"""
import subprocess
import os


def _get_monitors() -> list[dict]:
    """Devolve dados dos monitores activos via hyprctl monitors -j."""
    try:
        import json
        r = subprocess.run(
            ["hyprctl", "monitors", "-j"],
            capture_output=True, text=True, timeout=3
        )
        if r.returncode == 0:
            return json.loads(r.stdout)
    except Exception:
        pass
    return []


def apply_icc(icc_path: str) -> bool:
    """
    Aplica um ICC profile a todos os monitores activos.
    Devolve True se aplicou em pelo menos um monitor.
    """
    if not icc_path or not os.path.isfile(icc_path):
        return False

    monitors = _get_monitors()
    if not monitors:
        # Fallback: tenta aplicar sem especificar monitor
        try:
            r = subprocess.run(
                ["hyprctl", "keyword", "monitor", f",icc,{icc_path}"],
                capture_output=True, text=True
            )
            return r.returncode == 0
        except Exception:
            return False

    ok = False
    for m in monitors:
        name = m.get("name")
        if not name:
            continue
        width = m.get("width", 1920)
        height = m.get("height", 1080)
        refresh = m.get("refreshRate", 60.0)
        x = m.get("x", 0)
        y = m.get("y", 0)
        scale = m.get("scale", 1.0)
        try:
            r = subprocess.run(
                ["hyprctl", "keyword", "monitor",
                 f"{name},{width}x{height}@{refresh},{x}x{y},{scale},icc,{icc_path}"],
                capture_output=True, text=True
            )
            if r.returncode == 0:
                ok = True
        except Exception:
            pass
    return ok


def reset_icc() -> None:
    """Remove ICC de todos os monitores (volta ao perfil sRGB do compositor)."""
    monitors = _get_monitors()
    if not monitors:
        try:
            subprocess.run(
                ["hyprctl", "keyword", "monitor", ",icc,"],
                capture_output=True, text=True
            )
        except Exception:
            pass
        return

    for m in monitors:
        name = m.get("name")
        if not name:
            continue
        width = m.get("width", 1920)
        height = m.get("height", 1080)
        refresh = m.get("refreshRate", 60.0)
        x = m.get("x", 0)
        y = m.get("y", 0)
        scale = m.get("scale", 1.0)
        try:
            subprocess.run(
                ["hyprctl", "keyword", "monitor",
                 f"{name},{width}x{height}@{refresh},{x}x{y},{scale},icc,"],
                capture_output=True, text=True
            )
        except Exception:
            pass


def resolve_icc_path(icc_file: str, icc_dir: str = "") -> str | None:
    """
    Resolve o path do ICC:
      1. Path absoluto → usa directamente
      2. Nome de ficheiro → procura em icc_dir, depois em locais padrão
    """
    if not icc_file:
        return None

    if os.path.isabs(icc_file) and os.path.isfile(icc_file):
        return icc_file

    # Locais de busca
    search = []
    if icc_dir:
        search.append(icc_dir)
    search += [
        os.path.expanduser("~/.config/hypr/hyprvision/icc"),
        os.path.expanduser("~/.local/share/icc"),
        "/usr/share/color/icc",
        "/usr/share/icc",
    ]

    for d in search:
        candidate = os.path.join(d, icc_file)
        if os.path.isfile(candidate):
            return candidate

    return None
