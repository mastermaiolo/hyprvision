import shutil
import subprocess
import time
import threading
from abc import ABC, abstractmethod


class GammaBackend(ABC):
    @abstractmethod
    def set_temperature(self, temp: int)       -> None: ...
    @abstractmethod
    def set_brightness(self, brightness: float) -> None: ...
    @abstractmethod
    def set_gamma(self, gamma: float)           -> None: ...
    @abstractmethod
    def validate_available(self)               -> bool: ...
    @abstractmethod
    def commit(self)                           -> None: ...
    @abstractmethod
    def reset(self)                            -> None: ...


class WlGammaRelayBackend(GammaBackend):
    """
    wl-gammarelay-rs via D-Bus/busctl.
    Suporta temperatura, brightness E gamma com transições suaves.
    """
    _BUS  = "rs.wl-gammarelay"
    _PATH = "/"
    _IFACE = "rs.wl.gammarelay"

    def __init__(self):
        self._threads: list[threading.Thread] = []

    def _ping(self) -> bool:
        try:
            r = subprocess.run(
                ["busctl", "--user", "get-property",
                 self._BUS, self._PATH, self._IFACE, "Temperature"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            return r.returncode == 0
        except FileNotFoundError:
            return False

    def validate_available(self) -> bool:
        if self._ping():
            return True
        # O pacote não traz D-Bus activation nem unit systemd — se o binário
        # existe mas não está a correr, arranca-o aqui (on-demand, para todos
        # os chamadores: CLI, daemon, restore). Instâncias concorrentes são
        # inofensivas: só uma ganha o nome no bus, a outra sai sozinha.
        if not shutil.which("wl-gammarelay-rs"):
            return False
        subprocess.Popen(
            ["wl-gammarelay-rs"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        for _ in range(20):
            time.sleep(0.1)
            if self._ping():
                return True
        return False

    def _get(self, prop: str) -> float:
        r = subprocess.run(
            ["busctl", "--user", "get-property",
             self._BUS, self._PATH, self._IFACE, prop],
            capture_output=True, text=True
        )
        if r.returncode == 0:
            return float(r.stdout.strip().split()[-1])
        return 0.0

    def _set(self, prop: str, sig: str, val: float) -> None:
        v = str(int(val)) if sig == "q" else f"{val:.4f}"
        subprocess.run(
            ["busctl", "--user", "set-property",
             self._BUS, self._PATH, self._IFACE, prop, sig, v],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    def _smooth(self, prop: str, sig: str, target: float,
                steps: int = 18, delay: float = 0.035) -> None:
        try:
            current = self._get(prop)
        except Exception:
            self._set(prop, sig, target)
            return
        if abs(current - target) < (1 if sig == "q" else 0.001):
            return
        step = (target - current) / steps
        for i in range(1, steps + 1):
            self._set(prop, sig, current + step * i)
            time.sleep(delay)
        self._set(prop, sig, target)   # garante valor exacto no final

    def _start(self, prop: str, sig: str, target: float) -> None:
        t = threading.Thread(target=self._smooth, args=(prop, sig, target), daemon=True)
        self._threads.append(t)
        t.start()

    def set_temperature(self, temp: int)        -> None: self._start("Temperature", "q", float(temp))
    def set_brightness(self, brightness: float)  -> None: self._start("Brightness",  "d", brightness)
    def set_gamma(self, gamma: float)            -> None: self._start("Gamma",        "d", gamma)

    def commit(self) -> None:
        for t in self._threads:
            t.join()
        self._threads.clear()

    def reset(self) -> None:
        self._start("Temperature", "q", 6500.0)
        self._start("Brightness",  "d", 1.0)
        self._start("Gamma",       "d", 1.0)
        self.commit()


class HyprsunsetBackend(GammaBackend):
    """
    Fallback: hyprsunset / wlsunset.
    Suporta apenas temperatura (sem brightness/gamma via este backend).
    """
    def __init__(self):
        self._cmd = "hyprsunset" if self._which("hyprsunset") else "wlsunset"

    @staticmethod
    def _which(cmd: str) -> bool:
        r = subprocess.run(["which", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return r.returncode == 0

    def validate_available(self) -> bool:
        return self._which("hyprsunset") or self._which("wlsunset")

    def set_temperature(self, temp: int) -> None:
        subprocess.run(["pkill", "-x", "hyprsunset"], stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-x", "wlsunset"],  stderr=subprocess.DEVNULL)
        if temp == 6500:
            return
        if self._cmd == "hyprsunset":
            subprocess.Popen(["hyprsunset", "-t", str(temp)])
        else:
            subprocess.Popen(["wlsunset", "-t", str(temp), "-T", str(temp)])

    def set_brightness(self, brightness: float) -> None:
        pass   # não suportado neste backend

    def set_gamma(self, gamma: float) -> None:
        pass   # não suportado neste backend

    def commit(self) -> None:
        pass

    def reset(self) -> None:
        subprocess.run(["pkill", "-x", "hyprsunset"], stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-x", "wlsunset"],  stderr=subprocess.DEVNULL)


def get_best_gamma_backend() -> GammaBackend:
    """
    Selecciona o melhor backend disponível em runtime.
    Preferência: wl-gammarelay-rs > hyprsunset > wlsunset
    """
    relay = WlGammaRelayBackend()
    if relay.validate_available():
        return relay
    sun = HyprsunsetBackend()
    if sun.validate_available():
        return sun
    raise RuntimeError(
        "Nenhum backend de gamma encontrado.\n"
        "Instala wl-gammarelay-rs (recomendado) ou hyprsunset."
    )
