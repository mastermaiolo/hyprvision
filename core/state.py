import json
import os
import tempfile
from dataclasses import asdict
from .models import RuntimeState, OverlayState


class StateManager:
    def __init__(self, state_file: str):
        self.state_file = state_file
        os.makedirs(os.path.dirname(self.state_file), exist_ok=True)

    def read_state(self) -> RuntimeState:
        if not os.path.isfile(self.state_file):
            return RuntimeState()
        try:
            with open(self.state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            overlay_data = data.pop("overlay", {})
            overlay = OverlayState(**overlay_data) if overlay_data else OverlayState()
            known = set(RuntimeState.__dataclass_fields__)
            data = {k: v for k, v in data.items() if k in known}
            return RuntimeState(overlay=overlay, **data)
        except (json.JSONDecodeError, TypeError, KeyError):
            return RuntimeState()

    def write_state(self, state: RuntimeState) -> None:
        state_dict = asdict(state)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(self.state_file), text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(state_dict, f, indent=4)
            os.rename(tmp, self.state_file)
        except Exception as e:
            if os.path.exists(tmp):
                os.remove(tmp)
            raise RuntimeError(f"Falha ao escrever estado: {e}")

    def clear_state(self) -> None:
        if os.path.isfile(self.state_file):
            os.remove(self.state_file)
