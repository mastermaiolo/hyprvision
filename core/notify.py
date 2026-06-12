import subprocess

def notify(title: str, body: str = "", urgency: str = "normal") -> None:
    try:
        subprocess.run(
            ["notify-send", "-a", "HyprVision", "-u", urgency, title, body],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except FileNotFoundError:
        pass  # libnotify não instalado — ignora silenciosamente
