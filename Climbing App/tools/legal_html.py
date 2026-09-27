#!/usr/bin/env python3
"""Turns the two legal documents in the app into two web pages.

App Store Connect requires a privacy policy at a URL, and Trace holds its
policy inside the app rather than fetching it, on the grounds that an app which
reaches the network for nothing should not need the network to show you its own
privacy policy. Both of those are true at once only if the hosted copy is
generated from the shipped one, which is what this does.

    python3 tools/legal_html.py

Reads Climbing App/Views/LegalScreen.swift, writes docs/privacy.html and
docs/terms.html. Run it whenever either document changes, and commit the result.
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Climbing App" / "Views" / "LegalScreen.swift"


def swift_strings(text):
    """Every double-quoted Swift literal in order, unescaped."""
    out = []
    for raw in re.findall(r'"((?:[^"\\]|\\.)*)"', text):
        out.append(raw.replace('\\"', '"').replace("\\\\", "\\"))
    return out


def document(source, func):
    """The one document's title, date, standfirst and sections."""
    start = source.index(f"static func {func}(")
    body = source[start:source.index("\n}", start)]

    title = re.search(r'title:\s*"([^"]*)"', body).group(1)
    updated = re.search(r'updated:\s*"([^"]*)"', body).group(1)
    standfirst = re.search(r'standfirst:\s*"((?:[^"\\]|\\.)*)"', body).group(1)
    version = re.search(r'static let version = "([^"]*)"', source).group(1)

    sections = []
    for chunk in re.finditer(
            r'Section\(heading:\s*"([^"]*)",\s*body:\s*\[(.*?)\]\)', body, re.S):
        heading = chunk.group(1)
        paragraphs = [p for p in swift_strings(chunk.group(2)) if p.strip()]
        sections.append((heading, paragraphs))
    return title, updated, version, standfirst, sections


STYLE = """
:root { color-scheme: light; --ink:#16213f; --ink2:#41506f; --ink3:#7b88a1;
        --paper:#f4f2ec; --rule:#ddd8cc; --blue:#1f3bd4; }
* { box-sizing: border-box; }
body { margin:0; background:var(--paper); color:var(--ink);
       font:17px/1.62 ui-serif, Georgia, "Times New Roman", serif;
       -webkit-text-size-adjust:100%; }
main { max-width:40rem; margin:0 auto; padding:4rem 1.35rem 6rem; }
h1 { font-size:2.1rem; line-height:1.15; margin:0 0 .5rem; letter-spacing:-.01em; }
.meta { color:var(--ink3); font:500 .84rem/1.4 ui-sans-serif, system-ui, sans-serif;
        margin:0 0 1.6rem; }
.standfirst { font-size:1.22rem; color:var(--ink2); line-height:1.5; margin:0 0 2.4rem; }
section { border-top:1px solid var(--rule); padding-top:1.4rem; margin-top:2rem; }
h2 { font:600 .78rem/1.3 ui-sans-serif, system-ui, sans-serif;
     text-transform:uppercase; letter-spacing:.09em; color:var(--ink3);
     margin:0 0 .9rem; }
p { margin:0 0 1.05rem; }
footer { margin-top:3.5rem; border-top:1px solid var(--rule); padding-top:1.2rem;
         color:var(--ink3); font:.84rem/1.6 ui-sans-serif, system-ui, sans-serif; }
a { color:var(--blue); }
@media (prefers-color-scheme: dark) {
  :root { --ink:#eceaf2; --ink2:#c2c7d6; --ink3:#8e97ad; --paper:#14182a;
          --rule:#2c3350; --blue:#93a6ff; }
}
"""


def page(title, updated, version, standfirst, sections):
    e = html.escape
    parts = [
        "<!doctype html>", '<html lang="en">', "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>Trace — {e(title)}</title>",
        f"<style>{STYLE}</style>", "</head>", "<body>", "<main>",
        f"<h1>{e(title)}</h1>",
        f'<p class="meta">Version {e(version)} · {e(updated)}</p>',
        f'<p class="standfirst">{e(standfirst)}</p>',
    ]
    for heading, paragraphs in sections:
        parts.append("<section>")
        parts.append(f"<h2>{e(heading)}</h2>")
        parts += [f"<p>{e(p)}</p>" for p in paragraphs]
        parts.append("</section>")
    parts += [
        "<footer>",
        "<p>This page is generated from the copy inside the Trace app, so the two "
        "always say the same thing. Questions: "
        '<a href="mailto:knrobinson1023@gmail.com">knrobinson1023@gmail.com</a>.</p>',
        "</footer>", "</main>", "</body>", "</html>", "",
    ]
    return "\n".join(parts)


def main():
    source = SOURCE.read_text()
    out = ROOT / "docs"
    out.mkdir(exist_ok=True)
    for func, name in (("privacy", "privacy.html"), ("terms", "terms.html")):
        title, updated, version, standfirst, sections = document(source, func)
        if not sections:
            sys.exit(f"no sections parsed out of {func}()")
        (out / name).write_text(page(title, updated, version, standfirst, sections))
        print(f"{name}: {len(sections)} sections, version {version}")


if __name__ == "__main__":
    main()
