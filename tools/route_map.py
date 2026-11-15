"""Draws the walked route from a FieldVision log: where guidance could see, and where it could not.

Usage:  python3 route_map.py fieldvision-20261115-093000.jsonl [route.svg]

For the inspection slide: «"nessun difetto" non è "non visto"». Writes an SVG with no extra packages: the route
seen from above, green where guidance was reliable, yellow where it was not, the start, the end and the marked
obstacles, with a 1 m scale bar. Needs a log from the version that writes the walker's position (x, z in the
state rows). Gaps (a pause, a restart, the place being recognised) are left out rather than drawn across.
"""
import json
import math
import sys

BACKGROUND = "#15171C"
INK = "#F6F3EC"
SOFT = "#C3C9D2"
SEEN = "#3DBE84"
UNSEEN = "#F0E442"
MARK = "#FF7A59"
FONT = "Helvetica, Arial, sans-serif"
WIDTH, HEIGHT, PAD, LEGEND = 1600, 1000, 90, 170


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return rows


def main(path, out=None):
    rows = load(path)
    states = [r for r in rows if r.get("type") == "state" and "x" in r and "z" in r and "t" in r]
    if len(states) < 2:
        sys.exit("No positions in this log: it needs the version that writes x and z in the state rows.")
    marks = [r for r in rows if r.get("type") == "markObstacle" and r.get("action") == "added" and "x" in r]

    xs = [r["x"] for r in states] + [m["x"] for m in marks]
    zs = [r["z"] for r in states] + [m["z"] for m in marks]
    xmin, xmax, zmin, zmax = min(xs), max(xs), min(zs), max(zs)
    room_w, room_h = WIDTH - 2 * PAD, HEIGHT - 2 * PAD - LEGEND
    scale = min(room_w / max(xmax - xmin, 1.0), room_h / max(zmax - zmin, 1.0))
    left = PAD + (room_w - (xmax - xmin) * scale) / 2
    top = PAD + (room_h - (zmax - zmin) * scale) / 2

    def screen(x, z):
        # Seen from above; ARKit's first forward direction (-z) points up the page.
        return left + (x - xmin) * scale, top + (z - zmin) * scale

    runs, current = [], None
    seen_m = unseen_m = 0.0
    for a, b in zip(states, states[1:]):
        step = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        if b["t"] - a["t"] > 1.5 or step > 2.0:
            current = None
            continue
        reliable = bool(a.get("reliable"))
        if reliable:
            seen_m += step
        else:
            unseen_m += step
        if current is None or current[0] != reliable:
            current = (reliable, [screen(a["x"], a["z"])])
            runs.append(current)
        current[1].append(screen(b["x"], b["z"]))

    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
           f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{BACKGROUND}"/>']
    for reliable, points in runs:
        coords = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
        svg.append(f'<polyline points="{coords}" fill="none" stroke="{SEEN if reliable else UNSEEN}" '
                   f'stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>')
    sx, sy = screen(states[0]["x"], states[0]["z"])
    ex, ey = screen(states[-1]["x"], states[-1]["z"])
    svg.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="16" fill="{INK}"/>')
    svg.append(f'<rect x="{ex - 14:.1f}" y="{ey - 14:.1f}" width="28" height="28" fill="none" stroke="{INK}" stroke-width="6"/>')
    for m in marks:
        mx, my = screen(m["x"], m["z"])
        svg.append(f'<path d="M{mx - 16:.1f} {my - 16:.1f} L{mx + 16:.1f} {my + 16:.1f} M{mx + 16:.1f} {my - 16:.1f} '
                   f'L{mx - 16:.1f} {my + 16:.1f}" stroke="{MARK}" stroke-width="8" stroke-linecap="round"/>')

    # Legend and totals, with the scale bar on the totals line, right.
    total = seen_m + unseen_m
    legend_y = HEIGHT - PAD - 20
    for x, color, label in [(PAD, SEEN, "visto: guida affidabile"), (600, UNSEEN, "non visto: guida non affidabile")]:
        svg.append(f'<line x1="{x}" y1="{legend_y - 10}" x2="{x + 56}" y2="{legend_y - 10}" stroke="{color}" stroke-width="12" stroke-linecap="round"/>')
        svg.append(f'<text x="{x + 76}" y="{legend_y}" fill="{INK}" font-family="{FONT}" font-size="30">{label}</text>')
    if marks:
        svg.append(f'<text x="1180" y="{legend_y}" fill="{MARK}" font-family="{FONT}" font-size="30">✕ ostacolo segnato</text>')
    bar_m = 1.0 if scale <= 400 else 0.5
    bar_y = legend_y - 74
    bar_left = WIDTH - PAD - scale * bar_m
    svg.append(f'<line x1="{bar_left:.1f}" y1="{bar_y}" x2="{WIDTH - PAD}" y2="{bar_y}" stroke="{SOFT}" stroke-width="6"/>')
    svg.append(f'<text x="{bar_left - 16:.1f}" y="{bar_y + 10}" fill="{SOFT}" font-family="{FONT}" font-size="28" text-anchor="end">'
               f'{"1 m" if bar_m == 1.0 else "0,5 m"}</text>')
    if total > 0:
        summary = (f"Percorso {total:.0f} m · visto {seen_m / total:.0%} · non visto {unseen_m / total:.0%}"
                   f" · ● inizio  □ fine")
        svg.append(f'<text x="{PAD}" y="{legend_y - 64}" fill="{SOFT}" font-family="{FONT}" font-size="30">{summary}</text>')
    svg.append("</svg>")

    out = out or path.rsplit(".", 1)[0] + ".route.svg"
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(svg))
    if total > 0:
        print(f"Route {total:.1f} m: seen {seen_m / total:.0%}, not seen {unseen_m / total:.0%}; "
              f"{len(marks)} marked obstacle{'' if len(marks) == 1 else 's'}. Map: {out}")
    else:
        print(f"No movement to draw. Map: {out}")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)
