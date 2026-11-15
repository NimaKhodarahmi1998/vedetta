"""Builds index.html (a full page you can open locally) and dist/artifact.html (the claude.ai artifact version).
Usage: python3 build.py"""
import pathlib

root = pathlib.Path(__file__).parent
shell = (root / "src/shell.html").read_text()
sim = (root / "src/sim-core.js").read_text()
app = (root / "src/app.js").read_text()
scripts = ("<script>\n" + sim + "\n</script>\n"
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
print("built index.html and dist/artifact.html")
