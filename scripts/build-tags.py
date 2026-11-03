#!/usr/bin/env python3
"""Regenerate Sigil/Resources/tags.json from the icon packs' published metadata.

Run after updating the bundled icons:  python3 scripts/build-tags.py
"""
import json
import pathlib
import re
import urllib.request

OUT = pathlib.Path(__file__).resolve().parent.parent / "Sigil" / "Resources" / "tags.json"


def fetch(url: str) -> str:
    with urllib.request.urlopen(url) as response:
        return response.read().decode("utf-8")


def lucide() -> dict:
    return json.loads(fetch("https://unpkg.com/lucide-static@latest/tags.json"))


def tabler() -> dict:
    icons = json.loads(fetch("https://unpkg.com/@tabler/icons@latest/icons.json"))
    return {name: icon.get("tags", []) + [icon.get("category", "")] for name, icon in icons.items()}


def phosphor() -> dict:
    # The package ships its catalog as JS object literals, not JSON
    source = fetch("https://unpkg.com/@phosphor-icons/core@latest/dist/index.mjs")
    entries = re.findall(r'name: "([^"]+)",\s*pascal_name: "[^"]+",.*?tags: \[([^\]]*)\]', source, re.S)
    return {name: [t for t in re.findall(r'"([^"]*)"', tags) if not t.startswith("*")] for name, tags in entries}


def clean(tags: list) -> list:
    words = {w for tag in tags for w in re.split(r"[^a-z0-9]+", str(tag).lower()) if len(w) > 1}
    return sorted(words)


packs = {"lucide": lucide(), "tabler": tabler(), "phosphor": phosphor()}
result = {pack: {name: clean(tags) for name, tags in icons.items()} for pack, icons in packs.items()}
OUT.write_text(json.dumps(result, separators=(",", ":"), sort_keys=True))
print({pack: len(icons) for pack, icons in result.items()}, f"{OUT.stat().st_size // 1024} KB")
