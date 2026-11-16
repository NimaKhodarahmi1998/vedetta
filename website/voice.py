"""Records every spoken line in src/sim-core.js, in each language, with a natural neural voice, into src/voice/<lang>/.
Only new lines are recorded, clips for lines that no longer exist are removed, and changing a language's voice or
rate records that language again. Run python3 build.py afterwards to embed them in the page.
Usage: pip install edge-tts && python3 voice.py"""
import asyncio
import json
import pathlib
import re
import subprocess
import unicodedata

import edge_tts

VOICES = {
    "it": {"voice": "it-IT-IsabellaNeural", "rate": "+5%"},
    "en": {"voice": "en-US-AvaNeural", "rate": "+5%"},
}

root = pathlib.Path(__file__).parent
out = root / "src/voice"
manifest_path = out / "lines.json"

# Every line VOICE can produce, per language, for every object and side, so no line falls back to the browser's
# voice. A line that doesn't take an object throws on null and is simply skipped for it.
LIST_LINES = """
require('./src/sim-core.js');
const F = globalThis.FVSim, all = {};
for (const [lang, V] of Object.entries(F.VOICE)) {
  const lines = new Set();
  for (const say of Object.values(V)) for (const a of [null, ...F.AGENTS]) for (const side of ['left', 'right']) {
    try { lines.add(say(a, side)); } catch (e) { /* this line needs an object */ }
  }
  all[lang] = [...lines];
}
console.log(JSON.stringify(all));
"""


def slug(text):
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", plain.lower()).strip("-")


async def main():
    every = json.loads(subprocess.run(["node", "-e", LIST_LINES], cwd=root, capture_output=True, text=True, check=True).stdout)
    old = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    manifest = {}
    for lang, lines in every.items():
        settings = VOICES[lang]
        same_voice = {k: old.get(lang, {}).get(k) for k in settings} == settings
        folder = out / lang
        folder.mkdir(parents=True, exist_ok=True)
        files = {}
        for text in lines:
            path = folder / (slug(text) + ".mp3")
            if not (same_voice and path.exists()):
                await edge_tts.Communicate(text, settings["voice"], rate=settings["rate"]).save(str(path))
                print("recorded", lang, path.name)
            files[text] = f"{lang}/{path.name}"
        for path in folder.glob("*.mp3"):
            if f"{lang}/{path.name}" not in files.values():
                path.unlink()
                print("removed", lang, path.name)
        manifest[lang] = {**settings, "lines": files}
        print(f"{len(files)} {lang} lines")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


asyncio.run(main())
