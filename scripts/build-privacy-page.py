#!/usr/bin/env python3
"""
Generates docs/privacy.html from PRIVACY.md.

The policy has to exist in two places: PRIVACY.md, which GitHub renders and
which is versioned next to the code it describes, and a hosted page, which
App Store Connect requires a URL for. Keeping both by hand invites drift, so
the Markdown is the source and the page is built from it.

Page chrome (head, nav, footer, hover script) is lifted from an existing
published page rather than duplicated here, so the privacy page picks up any
change to the rest of the site automatically.

    ./scripts/build-privacy-page.py            # write docs/privacy.html
    ./scripts/build-privacy-page.py --check    # fail if it is out of date (CI)

Only the Markdown this file actually uses is supported — headings, paragraphs,
bullet lists, bold, links, autolinks, and inline code. It is deliberately not
a general Markdown implementation; if the policy grows syntax beyond that, add
it here rather than hand-editing the HTML.
"""

import html as html_mod
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PRIVACY.md"
TEMPLATE = ROOT / "docs" / "contact.html"     # any published page would do
OUTPUT = ROOT / "docs" / "privacy.html"
REPO_BLOB = "https://github.com/sahilramani/Tabs/blob/main/"
CANONICAL = "https://www.sahilramani.com/Tabs/privacy.html"

DESCRIPTION = ("Tabs collects nothing. All statement scanning and storage happens on your "
               "device, and the app has no networking layer at all.")

CARD = ("background: linear-gradient(180deg, rgba(255,255,255,0.045), rgba(255,255,255,0.015)); "
        "border: 1px solid rgba(255,255,255,0.08); border-radius: 22px; padding: 26px 28px;")
H2 = "margin: 0 0 12px; font-size: clamp(20px, 3vw, 25px); letter-spacing: -0.02em; font-weight: 800; color: #F3F6F4;"
PARA = "margin: 0 0 12px; color: #9AA8A0; font-size: 15.5px; line-height: 1.7;"
PARA_LAST = "margin: 0; color: #9AA8A0; font-size: 15.5px; line-height: 1.7;"
ITEM = "margin: 0 0 9px; color: #9AA8A0; font-size: 15px; line-height: 1.65;"
ITEM_LAST = "margin: 0; color: #9AA8A0; font-size: 15px; line-height: 1.65;"
STRONG = "color: #F3F6F4; font-weight: 600;"
LINK = "color: #30D158;"
CODE = ("font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 13.5px; "
        "color: #9FE8B4; background: rgba(48,209,88,0.10); padding: 1px 5px; border-radius: 5px;")

INLINE = re.compile(r"`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)|<(https?://[^>]+)>|\*\*([^*]+)\*\*")


def resolve(href: str) -> str:
    """Repo-relative links have to become absolute once the text is on the web."""
    if href.startswith(("http://", "https://", "mailto:", "#")):
        return href
    return REPO_BLOB + href.lstrip("./")


def inline(text: str) -> str:
    """Render the inline subset, escaping everything that isn't markup."""
    out, pos = [], 0
    for m in INLINE.finditer(text):
        out.append(html_mod.escape(text[pos:m.start()]))
        code, label, href, auto, bold = m.groups()
        if code is not None:
            out.append(f'<code style="{CODE}">{html_mod.escape(code)}</code>')
        elif label is not None:
            out.append(f'<a href="{html_mod.escape(resolve(href))}" style="{LINK}">{html_mod.escape(label)}</a>')
        elif auto is not None:
            out.append(f'<a href="{html_mod.escape(auto)}" style="{LINK}">{html_mod.escape(auto)}</a>')
        else:
            out.append(f'<span style="{STRONG}">{html_mod.escape(bold)}</span>')
        pos = m.end()
    out.append(html_mod.escape(text[pos:]))
    return "".join(out)


def parse(md: str):
    """Markdown -> (title, lead blocks, [(heading, blocks)]). A block is a
    paragraph string or a list of bullet strings."""
    title, lead, sections = None, [], []
    para, bullets = [], []

    def flush(target):
        nonlocal para, bullets
        if para:
            target.append(" ".join(para)); para = []
        if bullets:
            target.append(list(bullets)); bullets = []

    for raw in md.splitlines():
        line = raw.rstrip()
        target = sections[-1][1] if sections else lead
        if line.startswith("# "):
            flush(target); title = line[2:].strip()
        elif line.startswith("## "):
            flush(target); sections.append((line[3:].strip(), []))
        elif line.startswith("- "):
            if para:
                target.append(" ".join(para)); para = []
            bullets.append(line[2:].strip())
        elif not line:
            flush(target)
        elif bullets:
            bullets[-1] += " " + line.strip()      # continuation of a bullet
        else:
            para.append(line.strip())
    flush(sections[-1][1] if sections else lead)

    assert title, "PRIVACY.md needs an H1"
    assert sections, "PRIVACY.md needs at least one H2 section"
    return title, lead, sections


def render_blocks(blocks) -> str:
    out = []
    for i, block in enumerate(blocks):
        last = i == len(blocks) - 1
        if isinstance(block, list):
            items = "\n".join(
                f'          <li style="{ITEM_LAST if last and j == len(block) - 1 else ITEM}">{inline(b)}</li>'
                for j, b in enumerate(block))
            out.append(f'        <ul style="margin: 0; padding-left: 20px;">\n{items}\n        </ul>')
        else:
            out.append(f'        <p style="{PARA_LAST if last else PARA}">{inline(block)}</p>')
    return "\n".join(out)


def build() -> str:
    title, lead, sections = parse(SOURCE.read_text())
    chrome = TEMPLATE.read_text()

    main = re.search(r"  <main .*?</main>\n", chrome, re.S)
    assert main, f"no <main> block in {TEMPLATE.name}; the template moved"

    lead_html = "\n".join(
        f'      <p style="margin: 0 0 12px; color: #9AA8A0; font-size: 17px; line-height: 1.65;">{inline(b)}</p>'
        for b in lead if not isinstance(b, list))

    body = [
        '  <main style="max-width: 1080px; margin: 0 auto; padding: 0 28px; position: relative; z-index: 1;">\n',
        '    <section style="padding: 72px 0 34px; max-width: 720px;">\n',
        "      <div style=\"font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 12px; "
        'letter-spacing: 0.1em; color: #30D158; text-transform: uppercase; margin-bottom: 16px;">// Privacy</div>\n',
        '      <h1 style="margin: 0 0 18px; font-size: clamp(34px, 6vw, 54px); line-height: 1.04; '
        f'letter-spacing: -0.035em; font-weight: 800; color: #F3F6F4;">{inline(title)}</h1>\n',
        lead_html + "\n",
        "    </section>\n",
    ]
    for heading, blocks in sections:
        body += [
            '\n    <section style="padding: 0 0 22px; max-width: 720px;">\n',
            f'      <div style="{CARD}">\n',
            f'        <h2 style="{H2}">{inline(heading)}</h2>\n',
            render_blocks(blocks) + "\n",
            "      </div>\n    </section>\n",
        ]
    body.append('\n    <div style="height: 26px;"></div>\n  </main>\n')

    page = chrome.replace(main.group(0), "".join(body))

    # Retitle, and point the social metadata at this page.
    page = re.sub(r"<title>.*?</title>", "<title>Privacy — Tabs</title>", page)
    page = re.sub(r'<meta name="description" content="[^"]*" />',
                  f'<meta name="description" content="{DESCRIPTION}" />', page)
    page = re.sub(r'<meta property="og:title" content="[^"]*" />',
                  '<meta property="og:title" content="Privacy — Tabs" />', page)
    page = re.sub(r'<meta property="og:description" content="[^"]*" />',
                  f'<meta property="og:description" content="{DESCRIPTION}" />', page)
    page = re.sub(r'<meta property="og:url" content="[^"]*" />',
                  f'<meta property="og:url" content="{CANONICAL}" />', page)

    # Move the nav's active styling onto Privacy.
    active = re.compile(r'<a href="(\w[\w-]*\.html)" style="color: #F3F6F4; font-size: 14px; '
                        r'font-weight: 600; padding: 8px 12px; border-radius: 9px;">([^<]+)</a>')
    m = active.search(page)
    assert m, "no active nav item found; the nav markup moved"
    page = page.replace(m.group(0),
                        f'<a href="{m.group(1)}" style="color: #9AA8A0; font-size: 14px; font-weight: 500; '
                        'padding: 8px 12px; border-radius: 9px;" style-hover="color: #F3F6F4; '
                        f'background: rgba(255,255,255,0.05);">{m.group(2)}</a>')
    inactive_privacy = ('<a href="privacy.html" style="color: #9AA8A0; font-size: 14px; font-weight: 500; '
                        'padding: 8px 12px; border-radius: 9px;" style-hover="color: #F3F6F4; '
                        'background: rgba(255,255,255,0.05);">Privacy</a>')
    assert inactive_privacy in page, "Privacy nav link missing from the template page"
    page = page.replace(inactive_privacy,
                        '<a href="privacy.html" style="color: #F3F6F4; font-size: 14px; font-weight: 600; '
                        'padding: 8px 12px; border-radius: 9px;">Privacy</a>', 1)
    return page


def main() -> int:
    page = build()
    if "--check" in sys.argv:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if current != page:
            print(f"error: {OUTPUT.relative_to(ROOT)} is out of date with PRIVACY.md.\n"
                  f"       run ./scripts/build-privacy-page.py and commit the result.")
            return 1
        print(f"{OUTPUT.relative_to(ROOT)} is up to date")
        return 0
    OUTPUT.write_text(page)
    print(f"wrote {OUTPUT.relative_to(ROOT)} from {SOURCE.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
