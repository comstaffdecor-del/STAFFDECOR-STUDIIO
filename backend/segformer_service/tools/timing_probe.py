"""P12-bis - mesure du temps d'inference median hors demarrage a froid.

Fait 2 passes HTTP par photo sur /segment (do_resize=true, comportement
de production), ne garde que la 2e passe (la 1re inclut potentiellement
un demarrage a froid residuel / effets de cache CPU / JIT torch), puis
calcule la mediane sur les 4 scenes. Script de diagnostic, non
committe comme fonctionnalite (cf. brief P12-bis, script jetable).

Prerequis : service demarre SANS MEASURE_MODE=1 (sinon le cache LRU
renverrait la 2e passe instantanement et fausserait la mesure).
"""

from __future__ import annotations

import statistics
import time
from pathlib import Path

import requests

DEMO_SCENES_DIR = Path(__file__).resolve().parent.parent.parent.parent / "assets" / "demo_scenes"
SCENES = ["haussmann", "moderne", "provencal", "scandinave"]
ENDPOINT = "http://localhost:8000/segment"


def call(scene: str) -> float:
    img_path = DEMO_SCENES_DIR / f"{scene}.jpg"
    with open(img_path, "rb") as f:
        raw = f.read()
    t0 = time.monotonic()
    resp = requests.post(
        ENDPOINT,
        data={"width": "512", "height": "384"},
        files={"image": ("room.jpg", raw, "image/jpeg")},
        timeout=60,
    )
    elapsed_ms = (time.monotonic() - t0) * 1000
    resp.raise_for_status()
    return elapsed_ms


def main():
    seconds_passes = []
    for scene in SCENES:
        t_first = call(scene)
        t_second = call(scene)
        print(f"scene={scene} pass1={t_first:.0f}ms pass2={t_second:.0f}ms (garde: pass2)")
        seconds_passes.append(t_second)

    median = statistics.median(seconds_passes)
    print(f"\nmediane (2e passe uniquement, hors demarrage a froid) = {median:.0f}ms")
    print(f"valeurs retenues: {[round(v) for v in seconds_passes]}")


if __name__ == "__main__":
    main()
