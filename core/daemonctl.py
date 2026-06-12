"""
HyprVision v4 · Controlo do daemon (PID file + liveness)
Usado pelo CLI e pelo próprio daemon. Um PID só é considerado válido
se o processo existir E for mesmo o hyprvision-daemon (evita PID reuse).
"""
import os
import signal
import subprocess
import time


def pid_file(base_dir: str) -> str:
    return os.path.join(base_dir, "state", "daemon.pid")


def _read_pid(base_dir: str) -> int | None:
    try:
        with open(pid_file(base_dir)) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None


def _is_our_daemon(pid: int) -> bool:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().decode("utf-8", "replace")
        return "hyprvision-daemon" in cmdline
    except OSError:
        return False


def running_pid(base_dir: str) -> int | None:
    """PID do daemon se estiver vivo; limpa PID files obsoletos."""
    pid = _read_pid(base_dir)
    if pid is None:
        return None
    if _is_our_daemon(pid):
        return pid
    # PID obsoleto (processo morreu sem limpar) — remove o ficheiro
    try:
        os.remove(pid_file(base_dir))
    except OSError:
        pass
    return None


def write_pid(base_dir: str) -> None:
    path = pid_file(base_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(str(os.getpid()))


def clear_pid(base_dir: str) -> None:
    try:
        os.remove(pid_file(base_dir))
    except OSError:
        pass


def stop(base_dir: str, timeout: float = 3.0) -> bool:
    """Pára o daemon via SIGTERM e espera pela saída. True se parou."""
    pid = running_pid(base_dir)
    if pid is None:
        return True
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        clear_pid(base_dir)
        return True
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not _is_our_daemon(pid):
            return True
        time.sleep(0.1)
    return False


def start(base_dir: str) -> int | None:
    """Arranca o daemon em background. Devolve o PID, ou None se falhou."""
    if (pid := running_pid(base_dir)) is not None:
        return pid   # já está a correr
    daemon_bin = os.path.join(base_dir, "bin", "hyprvision-daemon")
    proc = subprocess.Popen(
        [daemon_bin],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    # Dá-lhe um instante para escrever o PID file
    for _ in range(20):
        time.sleep(0.1)
        if (pid := running_pid(base_dir)) is not None:
            return pid
    return proc.pid if proc.poll() is None else None


def reload(base_dir: str) -> bool:
    """Envia SIGHUP para reler a config. True se o sinal foi entregue."""
    pid = running_pid(base_dir)
    if pid is None:
        return False
    try:
        os.kill(pid, signal.SIGHUP)
        return True
    except ProcessLookupError:
        clear_pid(base_dir)
        return False
