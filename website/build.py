"""Builds index.html (a full page you can open locally) and dist/artifact.html (the claude.ai artifact version).
Usage: python3 build.py"""
import base64
import json
import pathlib

root = pathlib.Path(__file__).parent
shell = (root / "src/shell.html").read_text()
text = (root / "src/text.js").read_text()
sim = (root / "src/sim-core.js").read_text()
app = (root / "src/app.js").read_text()

# the recorded voice in each language (made by voice.py), embedded so both pages stay single files
voice_dir = root / "src/voice"
manifest = json.loads((voice_dir / "lines.json").read_text()) if (voice_dir / "lines.json").exists() else {}
clips = {lang: {line: base64.b64encode((voice_dir / name).read_bytes()).decode() for line, name in m["lines"].items()}
         for lang, m in manifest.items()}

# text.js first, so the page shows the right language before anything heavy loads
scripts = ("<script>\n" + text + "\n</script>\n"
           "<script>\n" + sim + "\n</script>\n"
           "<script>window.FVVoice = " + json.dumps(clips, ensure_ascii=False) + ";</script>\n"
           '<script type="importmap">{"imports":{"three":"https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js"}}</script>\n'
           '<script type="module">\n' + app + "\n</script>\n")

# claude.ai artifact: page content only (the host adds doctype/head/body)
(root / "dist").mkdir(exist_ok=True)
(root / "dist/artifact.html").write_text(shell + "\n" + scripts)

# full standalone page
head, body = shell.split('<header class="top">', 1)
page = ('<!doctype html>\n<html lang="it">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        + head + '</head>\n<body>\n<header class="top">' + body + "\n" + scripts + "</body>\n</html>\n")
(root / "index.html").write_text(page)
print("built index.html and dist/artifact.html, with voice lines: " + ", ".join(f"{len(c)} {lang}" for lang, c in clips.items()))
