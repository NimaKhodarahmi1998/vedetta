"""Turns a FieldVision session log into the numbers for the pitch.

Usage:  python3 analyze_log.py fieldvision-20261114-170000.jsonl

Get the log from the iPhone: Files > On My iPhone > FieldVision > share it to the Mac.
Marks (a triple-tap on the camera) are the ground truth: tap the moment something really happens
(lens covered, person steps behind the board, bike crosses). The script measures how long
the app took to react after each tap. A tap itself takes a person ~0.2 s, so delays are slight overestimates.

Without marks it also counts: how long guidance took to come back after each "unreliable" (recoveries),
whether a hidden person came back with the same number, the floor lines (steps, stairs, drops, floor ends),
and how long spoken lines waited for their turn, and which were dropped.
"""
import json
import re
import statistics
import sys
from collections import Counter

REACTIONS = ("unreliable", "hidden", "fast", "ahead", "obstacle", "wall", "back", "lost", "crowd", "torchOn", "torchOff",
             "floor", "floorFar", "floorEnds")
FLOOR = ("floor", "floorFar", "floorEnds")


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


def kind(event):
    return event.split("(")[0]


def spread(values):
    return f"median {statistics.median(values):.2f} s, max {max(values):.2f} s (n={len(values)})"


def recoveries(events):
    """Each 'unreliable' until the next 'reliable': how long guidance was off."""
    spans, start = [], None
    for e in events:
        k = kind(e["event"])
        if k == "unreliable" and start is None:
            start = e["t"]
        elif k == "reliable" and start is not None:
            spans.append(e["t"] - start)
            start = None
    return spans


def hides(tracks):
    """For each person who went hidden: back with the same number, lost, or out of the picture."""
    results = []
    for i, r in enumerate(tracks):
        if r.get("change") != "hidden":
            continue
        later = tracks[i + 1:]
        end = next((x for x in later if x["id"] == r["id"] and x.get("change") in ("back", "lost", "out")), None)
        new_numbers = {x["id"] for x in later
                       if x.get("change") == "sure" and x["id"] != r["id"] and 0 <= x["t"] - r["t"] <= 5}
        results.append({"end": end["change"] if end else "never", "took": end["t"] - r["t"] if end else None,
                        "new": new_numbers})
    return results


def floor_name(event):
    match = re.search(r"FloorKind\.(\w+)", event)
    return match.group(1) if match else kind(event)


def main(path):
    rows = load(path)
    states = [r for r in rows if r.get("type") == "state"]
    events = [r for r in rows if r.get("type") == "event"]
    says = [r for r in rows if r.get("type") == "say"]
    marks = [r for r in rows if r.get("type") == "mark"]
    tracks = [r for r in rows if r.get("type") == "track"]
    drops = [r for r in rows if r.get("type") == "drop"]
    covers = [r for r in rows if r.get("type") == "covered"]
    floor_ends = [r for r in rows if r.get("type") == "floorEnd"]
    if not states:
        print("No state rows: was guidance started?")
        return
    t0, t1 = states[0]["t"], states[-1]["t"]
    minutes = max(1e-6, (t1 - t0) / 60)
    version = next((r.get("version") for r in rows if r.get("type") == "start"), "?")
    print(f"Session ({version}): {t1 - t0:.0f} s, {len(states)} state samples, {len(events)} events, "
          f"{len(says)} spoken lines, {len(marks)} marks")

    reliable = sum(1 for s in states if s.get("reliable")) / len(states)
    fps = [s["fps"] for s in states if s.get("fps")]
    det = [s["detMs"] for s in states if s.get("detMs")]
    hz = [s["detHz"] for s in states if s.get("detHz")]
    print(f"Guidance reliable {reliable:.0%} of the time")
    if fps:
        print(f"Camera {statistics.median(fps):.0f} fps (min {min(fps):.0f}); detector {statistics.median(hz) if hz else 0:.1f} Hz, "
              f"{statistics.median(det) if det else 0:.0f} ms median inference (n={len(det)})")
        first = [s["fps"] for s in states if s.get("fps") and s["t"] - t0 <= 60]
        last = [s["fps"] for s in states if s.get("fps") and t1 - s["t"] <= 60]
        if first and last and minutes > 2:
            print(f"Camera fps in the first minute {statistics.median(first):.0f}, in the last minute {statistics.median(last):.0f}")

    counts = Counter(kind(e["event"]) for e in events)
    print("Events:", ", ".join(f"{k} {v}" for k, v in counts.most_common()))

    # false "unreliable": not within 3 s after a mark
    mark_t = [m["t"] for m in marks if "t" in m]
    unrel = [e["t"] for e in events if kind(e["event"]) == "unreliable"]
    false_unrel = [t for t in unrel if not any(0 <= t - m <= 3 for m in mark_t)]
    print(f"'Unreliable' warnings: {len(unrel)}; without a mark before them: {len(false_unrel)} "
          f"({len(false_unrel) / minutes:.2f} per minute over {minutes:.1f} min)")
    spans = recoveries(events)
    if spans:
        print(f"Recoveries (unreliable until back on): {spread(spans)}")
    if covers:
        print(f"Covered lens taken: {len(covers)} times ({', '.join(f'{k} {v}' for k, v in Counter(c.get('how') for c in covers).items())})")

    labels = next((r for r in rows if r.get("type") == "labels"), None)
    if labels:
        print(f"Vision place labels on this phone: {labels.get('found', '')}; missing: {labels.get('missing', '')} ({labels.get('system', '')})")
    scenes = [r for r in rows if r.get("type") == "scene"]
    if scenes:
        print(f"Place checks: {len(scenes)}; stairs likely in {sum(1 for r in scenes if r.get('stairsLikely'))}, "
              f"station likely in {sum(1 for r in scenes if r.get('stationLikely'))}")
    own = [r for r in rows if r.get("type") == "self"]
    if own:
        print(f"Own legs/feet ignored: {len(own)} times ({', '.join(f'{k} {v}' for k, v in Counter(r.get('rule') for r in own).items())})")

    step_lines = [r for r in rows if r.get("type") == "stepLine"]
    if step_lines:
        kinds = Counter(r.get("kind") for r in step_lines)
        print(f"Floor reader lines: {len(step_lines)} ({', '.join(f'{k} {v}' for k, v in kinds.items())}); "
              f"'up' lines silenced because the floor drops ahead: {sum(1 for r in step_lines if r.get('vetoed'))}")
    profiles = [r for r in rows if r.get("type") == "stairsProfile"]
    if profiles:
        print(f"Stairs going up read from the 3D map: {len(profiles)} times")

    marked = [r for r in rows if r.get("type") == "markObstacle"]
    if marked:
        actions = Counter(r.get("action") for r in marked)
        warned = sum(1 for r in rows if r.get("type") == "markAhead")
        print(f"Marked obstacles: {actions.get('added', 0)} added, {actions.get('removed', 0)} removed; warned on approach {warned} times")
    for r in rows:
        if r.get("type") == "placeLoad":
            print("Saved place " + (f"recognised, {r.get('marks')} marks back" if r.get("ok") else "not recognised within 10 s"))
    saves = [r for r in rows if r.get("type") == "placeSave"]
    if saves:
        print(f"Place saves: {sum(1 for r in saves if r.get('ok'))} ok, {sum(1 for r in saves if not r.get('ok'))} failed")

    found = hides(tracks)
    if found:
        same = [h["took"] for h in found if h["end"] == "back"]
        switched = sum(1 for h in found if h["end"] != "back" and h["new"])
        print(f"Hidden people: {len(found)}; back with the same number: {len(same)}"
              + (f" (hidden {spread(same)})" if same else "")
              + f"; lost: {sum(h['end'] == 'lost' for h in found)}; left the picture: {sum(h['end'] == 'out' for h in found)}"
              + f"; a new number within 5 s instead: {switched}")

    floor = [e for e in events if kind(e["event"]) in FLOOR]
    if floor:
        names = Counter(floor_name(e["event"]) for e in floor)
        print("Floor lines: " + ", ".join(f"{k} {v}" for k, v in names.most_common())
              + f" ({len(floor) / minutes:.2f} per minute)")
    if floor_ends:
        states_seen = Counter(r.get("state") for r in floor_ends)
        print(f"Floor ends seen: {states_seen.get('ends', 0)}; floor in view that couldn't be checked: {states_seen.get('unchecked', 0)}")

    waited = [s["waited"] for s in says if "waited" in s]
    if waited:
        print(f"Spoken lines waited {spread(waited)}; dropped: {len(drops)}")
        for d in drops:
            print(f"  dropped at {d['t'] - t0:7.1f} s (rank {d.get('rank', '?')}): {d.get('text', '')}")

    if mark_t:
        print("\nAfter each mark, the first reaction (within 5 s):")
        delays = {}
        for i, m in enumerate(mark_t, 1):
            nxt = [e for e in events if 0 <= e["t"] - m <= 5 and kind(e["event"]) in REACTIONS]
            if nxt:
                e = nxt[0]
                d = e["t"] - m
                delays.setdefault(kind(e["event"]), []).append(d)
                print(f"  mark {i}: {kind(e['event'])} after {d:.2f} s")
            else:
                print(f"  mark {i}: no reaction within 5 s")
        for k, ds in delays.items():
            print(f"Time to {k}: {spread(ds)}")

    print("\nSpoken lines:")
    for s in says:
        rank = f" r{s['rank']}" if "rank" in s else ""
        print(f"  {s['t'] - t0:7.1f} s  [{s.get('lang', '')}{rank}] {s['text']}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
