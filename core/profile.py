import os
import tomllib
from typing import List
from .models import Profile, GammaSettings, ShaderSettings, IccSettings


class ProfileLoader:
    def __init__(self, profiles_base_dir: str):
        self.profiles_base_dir = profiles_base_dir

    def load_profile(self, file_path: str) -> Profile:
        if not os.path.isfile(file_path):
            raise FileNotFoundError(f"Perfil não encontrado: {file_path}")

        with open(file_path, "rb") as f:
            data = tomllib.load(f)

        profile_id = os.path.splitext(os.path.basename(file_path))[0]

        gd = data.get("gamma",  {})
        sd = data.get("shader", {})
        id_ = data.get("icc",   {})

        gamma = GammaSettings(
            temperature = gd.get("temperature", 6500),
            brightness  = gd.get("brightness",  1.0),
            gamma       = gd.get("gamma",        1.0),
        )
        shader = ShaderSettings(
            enabled    = sd.get("enabled",    bool(sd.get("file", ""))),
            file       = sd.get("file",       ""),
            parameters = sd.get("parameters", {}),
        )
        icc = IccSettings(
            file = id_.get("file", "") if isinstance(id_, dict) else "",
        )

        return Profile(
            id          = profile_id,
            name        = data.get("name",        "Unknown"),
            icon        = data.get("icon",        "✨"),
            description = data.get("description", ""),
            intensity   = data.get("intensity",   "subtle"),
            category    = data.get("category",    "experience"),
            gamma       = gamma,
            shader      = shader,
            icc         = icc,
        )

    def load_all_profiles(self) -> List[Profile]:
        profiles = []
        for root, _, files in os.walk(self.profiles_base_dir):
            for fname in sorted(files):
                if fname.endswith(".toml"):
                    try:
                        p = self.load_profile(os.path.join(root, fname))
                        profiles.append(p)
                    except Exception as e:
                        print(f"[HyprVision] Aviso: falha ao carregar {fname}: {e}")
        return profiles

    def load_by_id(self, profile_id: str) -> Profile:
        for root, _, files in os.walk(self.profiles_base_dir):
            if f"{profile_id}.toml" in files:
                return self.load_profile(os.path.join(root, f"{profile_id}.toml"))
        raise FileNotFoundError(f"Perfil '{profile_id}' não encontrado.")
