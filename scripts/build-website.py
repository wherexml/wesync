#!/usr/bin/env python3
"""Render the three static we-sync Pages entries and archive only public assets."""

from html import escape
from pathlib import Path
from shutil import copyfile
from string import Template
from zipfile import ZIP_DEFLATED, ZipFile
import json
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "website"
OUTPUT = ROOT / ".build" / "website"
REPO = "https://github.com/wherexml/wesync"
LOCALES = (
    ("zh-Hans", "index.html", "简", "简体中文"),
    ("zh-Hant", "zh-hant.html", "繁", "繁體中文"),
    ("en", "en.html", "EN", "English"),
)
ASSETS = ("_headers", "assets/icon.svg", "assets/site.css", "assets/site.js")
ICONS = (
    '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
    '<path d="M5 3h10l4 4v14H5zM14 3v5h5M8 12h8M8 16h6"/>',
    '<circle cx="9" cy="8" r="3"/><path d="M3 20v-3a6 6 0 0 1 12 0v3m2-15a3 3 0 0 1 0 6m2 3a5 5 0 0 1 2 4v2"/>',
    '<path d="M3 12a9 9 0 1 1 4 8M3 5v7h7m2-5v5l3 2"/>',
    '<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v2"/>',
    '<path d="m4 7 5 5-5 5m7 0h8"/>',
)
APPLE = '<svg class="btn-glyph" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M17.05 12.54c.03 3.03 2.66 4.04 2.69 4.05-.02.07-.42 1.44-1.38 2.85-.84 1.22-1.71 2.43-3.08 2.46-1.34.02-1.77-.8-3.31-.8s-2.02.78-3.29.82c-1.32.05-2.33-1.32-3.17-2.53-1.72-2.48-3.03-7.02-1.27-10.07.87-1.52 2.44-2.48 4.14-2.51 1.3-.02 2.52.88 3.32.88.8 0 2.3-1.09 3.88-.93.66.03 2.51.27 3.7 2.02-.1.06-2.21 1.29-2.23 3.76ZM14.61 5.09c.7-.86 1.18-2.05 1.05-3.24-1.02.04-2.26.68-2.99 1.53-.65.75-1.21 1.95-1.06 3.1 1.13.09 2.29-.57 3-1.39Z"/></svg>'
LIGHTS = '<span class="lights" aria-hidden="true"><i></i><i></i><i></i></span>'


def icon(path):
    return f'<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6">{path}</svg>'


def split_text(text, css_class, english):
    units = re.findall(r"\S+\s*|\s+", text) if english else text
    return "".join(f'<span class="{css_class}">{escape(unit)}</span>' for unit in units)


def conversation_markup(data, scene, interactive=True):
    rows = []
    chats = []
    for index, (name, time, *messages) in enumerate(data):
        color = ("", "blue", "rose")[index]
        avatar = f'<span class="avatar {color}" aria-hidden="true">{escape(name[0])}</span>'
        active = " active" if index == 0 else ""
        rows.append(f'<div class="demo-row{active}">{avatar}<span><b>{escape(name)}</b><small>{escape(messages[-1])}</small></span></div>')
        if not interactive and index != 0:
            continue
        bubbles = "".join(
            f'<p class="bubble{" sent" if idx == 1 else ""}">{escape(message)}</p>'
            for idx, message in enumerate(messages)
        )
        if index == 0:
            bubbles += f'<div class="bubble sample-file"><span class="file-icon" aria-hidden="true">PDF</span><span><b>{escape(scene[7])}.pdf</b><small>{escape(scene[8])}</small></span></div>'
        hidden = " hidden" if index else ""
        chats.append(f'<article class="demo-chat"{hidden}><h3>{escape(name)}</h3><div class="demo-messages"><div class="demo-time">{escape(time)}</div>{bubbles}</div></article>')
    return "".join(rows), "".join(chats)


def feature_panels(data, search_icon):
    scene = list(map(escape, data["scene"]))
    rows, chat = conversation_markup(data["conversations"], data["scene"], interactive=False)
    scenes = (
        f'<div class="scene-content"><h4>{scene[0]}</h4><div class="scene-choice"><div class="scene-card"><span class="scene-icon">◉</span><strong>{scene[1]}</strong><small>{scene[2]}</small></div><div class="scene-card"><span class="scene-icon">◎</span><strong>{scene[3]}</strong><small>{scene[4]}</small></div></div><div class="scene-strip"><span>{scene[5]}</span><b>{scene[6]}</b></div></div>',
        f'<div class="scene-content search-scene"><h4>{escape(data["search"])}</h4><div class="scene-strip">{search_icon}<span>{scene[7]}</span></div><div class="scene-card"><strong>{scene[9]}</strong><small>{escape(data["conversations"][0][-1])}</small></div></div>',
        f'<div class="scene-content"><div class="document-paper"><p>{scene[7]}.pdf</p><small>{scene[8]}</small><i></i><i></i><i></i></div></div>',
        f'<div class="demo-workspace history-scene"><aside class="demo-sidebar">{rows}</aside><div>{chat}</div></div>',
    )
    return "\n".join(
        f'<article class="feature-panel"><div class="feature-copy"><h3>{escape(title)}</h3><p>{escape(body)}</p></div><figure class="shot"><div class="shot-frame"><div class="scene-window"><div class="editor-bar">{LIGHTS}<span>we-sync</span><small>{escape(data["sample"])}</small></div>{content}</div></div></figure></article>'
        for (title, body), content in zip(data["panels"], scenes)
    )


def render(template, copy, index):
    lang, _, _, _ = LOCALES[index]
    data = {name: variants[index] for name, variants in copy.items()}
    values = {name: escape(value) for name, value in data.items() if isinstance(value, str)}
    values["lang"] = lang
    values["repo"] = REPO
    values["alternates"] = "\n  ".join(
        f'<link rel="alternate" hreflang="{code}" href="{file}">' for code, file, _, _ in LOCALES
    ) + '\n  <link rel="alternate" hreflang="x-default" href="index.html">'
    links = []
    for code, file, label, name in (LOCALES[2], LOCALES[0], LOCALES[1]):
        current = ' aria-current="page"' if code == lang else ""
        links.append(f'<a href="{file}" lang="{code}" hreflang="{code}" aria-label="{name}"{current}>{label}</a>')
    values["language_links"] = f'<nav class="lang" aria-label="{values["language"]}">{"".join(links)}</nav>'
    values["nav_links"] = "".join(f'<a href="#{key}">{values[key]}</a>' for key in ("features", "privacy", "faq"))
    values["requirements"] = f'{values["chip"]} · {values["system"]}'
    values["build_button"] = f'<a class="btn btn-glow" href="{REPO}#从源码构建">{APPLE}{values["build"]}</a>'
    first, second, accent = data["hero"]
    values["hero_label"] = escape(f"{first} {second}{accent}")
    values["hero_text"] = (
        f'<span class="hero-line" aria-hidden="true">{split_text(first, "hero-ch", lang == "en")}</span>'
        f'<span class="hero-line" aria-hidden="true">{split_text(second, "hero-ch", lang == "en")}'
        f'<span class="hero-accent">{split_text(accent, "hero-ch", lang == "en")}</span>'
        '<span class="hero-caret"></span></span>'
    )
    values["tagline_label"] = escape(" ".join(data["tagline"]))
    values["tagline_text"] = "".join(
        f'<span class="tag-line" aria-hidden="true">{split_text(line, "t-ch", lang == "en")}</span>'
        for line in data["tagline"]
    )
    values["demo_headline"] = "".join(f"<span>{escape(line)}</span>" for line in data["demo"])
    values["lights"] = LIGHTS
    values["search_icon"] = icon(ICONS[0])
    values["rows"], values["chats"] = conversation_markup(data["conversations"], data["scene"])
    values["panels"] = feature_panels(data, values["search_icon"])
    values["cards"] = "\n".join(
        f'<article class="bento-card"><span class="bento-icon">{icon(path)}</span><h3>{escape(title)}</h3><p>{escape(body)}</p><div class="mini mini-{kind}" aria-hidden="true">{icon(path)}<span>{escape(hint)}</span><i></i></div></article>'
        for kind, path, (title, body, hint) in zip(
            ("search", "file", "filter", "cache", "policy", "cli"), ICONS, data["cards"]
        )
    )
    values["stats"] = "\n".join(
        f'<div class="stat"><p class="stat-value">{escape(value)}</p><p class="stat-label">{escape(label)}</p></div>'
        for value, label in data["stats"]
    )
    values["questions"] = "\n".join(
        f'<details class="faq-item"><summary>{escape(question)}</summary><div class="faq-body"><div class="faq-body-inner"><p>{escape(answer)}</p></div></div></details>'
        for question, answer in data["questions"]
    )
    return template.substitute(values)


def main():
    copy = json.loads((SOURCE / "copy.json").read_text())
    template = Template((SOURCE / "layout.html").read_text())
    (OUTPUT / "assets").mkdir(parents=True, exist_ok=True)
    for index, (_, name, _, _) in enumerate(LOCALES):
        (OUTPUT / name).write_text(render(template, copy, index))
    for name in ASSETS:
        copyfile(SOURCE / name, OUTPUT / name)
    archive_path = OUTPUT.with_suffix(".zip")
    with ZipFile(archive_path, "w", ZIP_DEFLATED) as archive:
        for name in (*[locale[1] for locale in LOCALES], *ASSETS):
            archive.write(OUTPUT / name, name)
    print(archive_path)


if __name__ == "__main__":
    main()
