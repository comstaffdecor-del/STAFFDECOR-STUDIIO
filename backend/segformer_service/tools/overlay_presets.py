"""P12-bis - overlay presets + mesure des bandes de transition.
Diagnostic jetable. Ne modifie aucun fichier lib/.
"""
import json, io, requests
from PIL import Image, ImageDraw
import numpy as np

SCENES = ["haussmann", "moderne", "provencal", "scandinave"]
ENDPOINT = "http://localhost:8000/segment"
W, H = 512, 384
CEIL, WALL, FLOOR = 1, 2, 3

# Copies telles quelles depuis lib/models/persp_calib.dart (demoPresets),
# lu directement dans ce fichier avant de remplir ce dict -- rien
# n'est invente.
# ordre: ceilL, ceilR, floorL, floorR, wallTL, wallTR, wallBL, wallBR
PRESETS = {
    "haussmann": dict(
        ceilL=(0.120, 0.090), ceilR=(0.880, 0.085),
        floorL=(0.120, 0.870), floorR=(0.880, 0.860),
        wallTL=(0.000, 0.100), wallTR=(1.000, 0.095),
        wallBL=(0.000, 0.900), wallBR=(1.000, 0.890),
    ),
    "moderne": dict(
        ceilL=(0.100, 0.095), ceilR=(0.900, 0.095),
        floorL=(0.100, 0.720), floorR=(0.900, 0.720),
        wallTL=(0.000, 0.105), wallTR=(1.000, 0.105),
        wallBL=(0.000, 0.740), wallBR=(1.000, 0.740),
    ),
    "provencal": dict(
        ceilL=(0.100, 0.140), ceilR=(0.900, 0.140),
        floorL=(0.100, 0.830), floorR=(0.900, 0.830),
        wallTL=(0.000, 0.150), wallTR=(1.000, 0.150),
        wallBL=(0.000, 0.850), wallBR=(1.000, 0.850),
    ),
    "scandinave": dict(
        ceilL=(0.100, 0.075), ceilR=(0.900, 0.075),
        floorL=(0.100, 0.810), floorR=(0.900, 0.810),
        wallTL=(0.000, 0.085), wallTR=(1.000, 0.085),
        wallBL=(0.000, 0.830), wallBR=(1.000, 0.830),
    ),
}

def seg(path):
    with open(path, "rb") as f:
        r = requests.post(ENDPOINT, data={"width": W, "height": H},
                          files={"image": ("room.jpg", f, "image/jpeg")})
    r.raise_for_status()
    body = r.json()
    assert body["labels"] == ["unknown", "ceiling", "wall", "floor"]
    flat = np.empty(W * H, dtype=np.int32)
    i = 0
    for cls, run in body["rle"]:
        flat[i:i + run] = cls
        i += run
    assert i == W * H
    return flat.reshape(H, W)

def preset_y_at(p, x_pct, which):
    """Reference yPct a l'abscisse x_pct, sur la polyligne du preset.
    which='ceil' -> wallTL/ceilL/ceilR/wallTR, 'floor' -> wallBL/floorL/floorR/wallBR
    Retourne None hors segment central si l'extrapolation serait douteuse."""
    if which == "ceil":
        a, b, c, d = p["wallTL"], p["ceilL"], p["ceilR"], p["wallTR"]
    else:
        a, b, c, d = p["wallBL"], p["floorL"], p["floorR"], p["wallBR"]
    for (x0, y0), (x1, y1) in ((a, b), (b, c), (c, d)):
        if x0 <= x_pct <= x1 and x1 > x0:
            t = (x_pct - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return None

def band(mask, upper, lower):
    """Pour chaque colonne: dernier pixel de `upper`, premier pixel de
    `lower` situe SOUS lui. Retourne les listes par colonne."""
    rows = []
    for x in range(W):
        col = mask[:, x]
        up = np.flatnonzero(col == upper)
        if up.size == 0:
            rows.append(None); continue
        last_up = int(up.max())
        lo = np.flatnonzero(col[last_up + 1:] == lower)
        if lo.size == 0:
            rows.append(None); continue
        first_lo = last_up + 1 + int(lo.min())
        rows.append((x, last_up, first_lo, first_lo - last_up - 1))
    return [r for r in rows if r is not None]

def stats(vals):
    a = np.array(vals, dtype=float)
    if a.size == 0:
        return {}
    return dict(n=int(a.size), median=float(np.median(a)),
                mean=float(a.mean()), p25=float(np.percentile(a, 25)),
                p75=float(np.percentile(a, 75)), max=float(a.max()))

summary = []
for s in SCENES:
    photo = f"assets/demo_scenes/{s}.jpg"
    mask = seg(photo)
    p = PRESETS[s]

    # --- overlay ---
    img = Image.open(photo).convert("RGB")
    pw, ph = img.size
    d = ImageDraw.Draw(img)
    def px(pt): return (pt[0] * pw, pt[1] * ph)
    for a, b in (("wallTL","ceilL"), ("ceilL","ceilR"), ("ceilR","wallTR")):
        d.line([px(p[a]), px(p[b])], fill=(255,0,0), width=4)
    for a, b in (("wallBL","floorL"), ("floorL","floorR"), ("floorR","wallBR")):
        d.line([px(p[a]), px(p[b])], fill=(0,80,255), width=4)
    d.line([px(p["ceilL"]), px(p["floorL"])], fill=(0,200,0), width=3)
    d.line([px(p["ceilR"]), px(p["floorR"])], fill=(0,200,0), width=3)
    for k in ("ceilL","ceilR","floorL","floorR"):
        x, y = px(p[k]); r = 7
        d.ellipse([x-r, y-r, x+r, y+r], outline=(255,255,0), width=3)
    img.save(f"/tmp/p12_overlay_{s}.png")

    # --- bandes ---
    cw = band(mask, CEIL, WALL)
    wf = band(mask, WALL, FLOOR)
    rec = {
        "scene": s, "photo_size": [pw, ph], "mask_size": [W, H],
        "ceiling_to_wall": stats([g for _,_,_,g in cw]),
        "wall_to_floor":   stats([g for _,_,_,g in wf]),
    }
    for key, data in (("ceiling_to_wall", cw), ("wall_to_floor", wf)):
        if data:
            rec[key]["medianGapYPct"] = rec[key]["median"] / H
            # comparaison aux presets, colonne par colonne
            which = "ceil" if key == "ceiling_to_wall" else "floor"
            diffs_up, diffs_lo, diffs_mid = [], [], []
            for x, last_up, first_lo, _ in data:
                ref = preset_y_at(p, x / W, which)
                if ref is None: continue
                diffs_up.append(last_up / H - ref)
                diffs_lo.append(first_lo / H - ref)
                diffs_mid.append(((last_up + first_lo) / 2) / H - ref)
            rec[key]["vs_preset_lastUpper"] = stats(diffs_up)
            rec[key]["vs_preset_firstLower"] = stats(diffs_lo)
            rec[key]["vs_preset_midBand"] = stats(diffs_mid)
    with open(f"/tmp/p12_dead_band_{s}.json", "w") as f:
        json.dump(rec, f, indent=2)
    summary.append(rec)

with open("/tmp/p12_overlay_presets.txt", "w") as f:
    f.write("P12-bis overlay + bandes de transition\n")
    f.write("verdict visuel a remplir A LA MAIN apres inspection des PNG\n\n")
    for r in summary:
        f.write(f"{r['scene']}: photo={r['photo_size']} mask={r['mask_size']}\n")
        for k in ("ceiling_to_wall", "wall_to_floor"):
            st = r[k]
            if not st: f.write(f"  {k}: aucune colonne valide\n"); continue
            f.write(f"  {k}: n={st['n']} median={st['median']:.1f}px "
                    f"({st.get('medianGapYPct', 0):.4f}) mean={st['mean']:.1f} "
                    f"p25={st['p25']:.1f} p75={st['p75']:.1f} max={st['max']:.0f}\n")
            for v in ("vs_preset_lastUpper", "vs_preset_midBand", "vs_preset_firstLower"):
                if v in st and st[v]:
                    f.write(f"    {v}: median={st[v]['median']:+.4f} n={st[v]['n']}\n")
        f.write("  ceiling_verdict = TODO\n  floor_verdict = TODO\n\n")
print(open("/tmp/p12_overlay_presets.txt").read())
