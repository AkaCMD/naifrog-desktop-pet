"""Independent optional user-supplied WAV player. Windows and Python 3.11+."""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib

BASE = Path(__file__).resolve().parent

def main():
    try:
        settings = json.loads((BASE / 'local.json').read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return 0
    arguments = sys.argv[1:]
    if arguments == ['--play']:
        wav = Path(settings.get('wavFile', ''))
        if os.name != 'nt' or not wav.is_file() or wav.suffix.lower() != '.wav':
            return 1
        return 0 if ctypes.windll.winmm.PlaySoundW(str(wav.resolve()), None, 0x20002) else 1
    try:
        event = json.loads(arguments[-1]) if arguments else {}
        codex = Path(settings.get('codexHome') or Path.home() / '.codex')
        config = tomllib.loads((codex / 'config.toml').read_text(encoding='utf-8-sig'))
        if (os.name == 'nt' and event.get('type') == 'agent-turn-complete'
                and config.get('desktop', {}).get('selected-avatar-id') == 'custom:naifrog'):
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--play'],
                creationflags=subprocess.CREATE_NO_WINDOW, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, ValueError, AttributeError):
        pass
    forward = settings.get('forwardNotify', [])
    if forward:
        try:
            return subprocess.run(forward + arguments, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0).returncode
        except OSError:
            return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
