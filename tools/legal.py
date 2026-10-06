#!/usr/bin/env python3
"""Publish the in-app legal documents to the web.

App Store Connect needs a Privacy Policy at a URL, and an EULA either at a
URL or pasted in. Both already exist inside the app, in LegalScreen.swift,
so they are generated from it rather than retyped: the web copy cannot
drift from the copy a person reads on their phone.

    python3 tools/legal.py
"""
import html, pathlib, re

SRC = pathlib.Path("Climbing App/Climbing App/Views/LegalScreen.swift")
OUT = pathlib.Path("docs")

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} &middot; Trace</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Newsreader:opsz,wght@6..72,600&display=swap">
<style>
:root{{--ground:#FAF9F4;--ink:#0F2C5C;--ink2:#4A6183;--ink3:#8C9CB0;--line:#EAE7DD;--accent:#0128A1}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--ground);color:var(--ink);
  font:16px/1.6 'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
  -webkit-font-smoothing:antialiased}}
.wrap{{max-width:680px;margin:0 auto;padding:48px 22px 90px}}
h1{{font-family:'Newsreader',Georgia,serif;font-weight:600;font-size:38px;margin:0;letter-spacing:-.01em}}
h2{{font-family:'Newsreader',Georgia,serif;font-weight:600;font-size:23px;margin:38px 0 10px}}
p{{margin:0 0 14px;color:var(--ink2)}}
.v{{font:500 12px/1 ui-monospace,Menlo,monospace;letter-spacing:.1em;text-transform:uppercase;color:var(--ink3);margin:10px 0 26px}}
.stand{{font-size:18px;color:var(--ink);margin-bottom:8px}}
a{{color:var(--accent)}}
footer{{margin-top:54px;padding-top:20px;border-top:1px solid var(--line);font-size:14px;color:var(--ink3)}}
@media (prefers-color-scheme:dark){{
  :root{{--ground:#101722;--ink:#EDF1F7;--ink2:#A9B6C9;--ink3:#73829A;--line:#26303F;--accent:#8FB6E0}}
}}
</style>
</head>
<body>
<div class="wrap">
<h1>{title}</h1>
<div class="v">Trace &middot; version {version} &middot; updated {updated}</div>
<p class="stand">{standfirst}</p>
{sections}
<footer>This is the same document that ships inside Trace, under {where}.
<a href="../">Trace</a> &middot; <a href="{other_href}">{other}</a></footer>
</div>
</body>
</html>
"""


def swift_strings(block: str) -> list[str]:
    """The Swift string literals in a body array, in order."""
    out, buf, inside, escape = [], [], False, False
    for ch in block:
        if escape:
            buf.append(ch); escape = False; continue
        if ch == "\\" and inside:
            escape = True; continue
        if ch == '"':
            if inside:
                out.append("".join(buf)); buf = []
            inside = not inside
            continue
        if inside:
            buf.append(ch)
    return out


def parse(doc: str, src: str) -> dict:
    start = src.index(f"static func {doc}(")
    end = src.index("insideApp: insideApp)", start)
    body = src[start:end]
    head = body[: body.index("sections:")]
    title = re.search(r'title:\s*"([^"]*)"', head).group(1)
    updated = re.search(r'updated:\s*"([^"]*)"', head).group(1)
    stand = re.search(r'standfirst:\s*"((?:[^"\\]|\\.)*)"', head).group(1).replace('\\"', '"')

    sections = []
    for m in re.finditer(r'Section\(heading:\s*"([^"]*)",\s*body:\s*\[(.*?)\]\s*\)', body, re.S):
        sections.append((m.group(1), swift_strings(m.group(2))))
    return {"title": title, "updated": updated, "standfirst": stand, "sections": sections}


def render(doc: str, meta: dict, version: str, other: str, other_href: str, where: str) -> str:
    parts = []
    for heading, paras in meta["sections"]:
        parts.append(f"<h2>{html.escape(heading)}</h2>")
        parts += [f"<p>{html.escape(p)}</p>" for p in paras]
    return PAGE.format(
        title=html.escape(meta["title"]), version=version,
        updated=html.escape(meta["updated"]),
        standfirst=html.escape(meta["standfirst"]),
        sections="\n".join(parts), other=other, other_href=other_href, where=where)


def main() -> None:
    src = SRC.read_text()
    version = re.search(r'static let version\s*=\s*"([^"]*)"', src)
    version = version.group(1) if version else "1.0"
    pages = {
        "privacy": ("Terms of Use", "../terms/", "Profile, then Privacy &amp; AI"),
        "terms": ("Privacy Policy", "../privacy/", "the sign-in screen and the paywall"),
    }
    for doc, (other, href, where) in pages.items():
        meta = parse(doc, src)
        out = OUT / doc / "index.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render(doc, meta, version, other, href, where))
        print(f"{out}  {len(meta['sections'])} sections")


if __name__ == "__main__":
    main()
