#!/usr/bin/env python3
"""Textes de l'app en anglais et en français (Resources/en.lproj, Resources/fr.lproj).

Les clés sont les textes français tels que le compilateur les voit (« Écoute %lld sur %lld ») ; la langue du Mac
choisit le fichier, l'anglais sert pour toute langue autre que le français (Info.plist, CFBundleDevelopmentRegion).

  localisation.py extraire DOSSIER SORTIE.json
      Lit les fichiers .stringsdata écrits par le compilateur (swiftc -emit-localized-strings) : la liste des clés,
      avec le fichier Swift de chacune.
  localisation.py verifier CLES.json [--strict]
      Compare ces clés à en.lproj et fr.lproj : clés sans anglais, clés qui ne servent plus, fr.lproj à jour.
      --strict : code de sortie 1 s'il manque une traduction (un Mac en anglais verrait du français).
  localisation.py generer TRADUCTIONS.json [...]
      Ajoute ou remplace des traductions ({ "clé française": "English" }) dans en.lproj, puis réécrit fr.lproj
      (chaque clé traduite par elle-même, pour qu'un Mac en français ne prenne jamais l'anglais).
  localisation.py nettoyer CLES.json
      Retire de en.lproj et fr.lproj les traductions que l'app n'utilise plus.
"""
import json
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN = os.path.join(ROOT, "Resources", "en.lproj", "Localizable.strings")
FR = os.path.join(ROOT, "Resources", "fr.lproj", "Localizable.strings")
HEADER = {
    "en": "/* FL Shortcuts en anglais. Clés : les textes français. Écrit par scripts/localisation.py generer. */\n",
    "fr": "/* FL Shortcuts en français : chaque clé est son propre texte. Écrit par scripts/localisation.py generer. */\n",
}


def escape(s):
    return (s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
            .replace("\r", "\\r"))


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "n":
                out.append("\n")
            elif n == "t":
                out.append("\t")
            elif n == "r":
                out.append("\r")
            elif n in "U" and re.match(r"[0-9a-fA-F]{4}", s[i + 2:i + 6]):
                out.append(chr(int(s[i + 2:i + 6], 16)))
                i += 6
                continue
            else:
                out.append(n)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


STRING = r'"((?:[^"\\]|\\.)*)"'
ENTRY = re.compile(r"\s*" + STRING + r"\s*=\s*" + STRING + r"\s*;")


def read_strings(path):
    if not os.path.exists(path):
        return {}
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = {}
    pos = 0
    while True:
        m = ENTRY.match(text, pos)
        if not m:
            if text[pos:].strip():
                raise SystemExit(f"{path} : ligne illisible près de « {text[pos:pos + 60].strip()} »")
            return out
        out[unescape(m.group(1))] = unescape(m.group(2))
        pos = m.end()


def write_strings(path, table, header):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(header)
        for key in sorted(table):
            f.write(f'"{escape(key)}" = "{escape(table[key])}";\n')


def load_stringsdata(path):
    raw = open(path, "rb").read()
    try:
        return json.loads(raw)
    except ValueError:
        return plistlib.loads(raw)


def extraire(folder, output):
    keys = {}
    tables = set()
    files = 0
    for dirpath, _, names in os.walk(folder):
        for name in names:
            if not name.endswith(".stringsdata"):
                continue
            files += 1
            data = load_stringsdata(os.path.join(dirpath, name))
            source = os.path.basename(str(data.get("source", name)))
            for table, entries in (data.get("tables") or {}).items():
                tables.add(table)
                for entry in entries:
                    key = entry.get("key")
                    if key is not None:
                        keys.setdefault(key, set()).add(source)
    result = [{"key": k, "files": sorted(v)} for k, v in sorted(keys.items())]
    with open(output, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print(f"{files} fichiers .stringsdata, {len(result)} clés, tables : {', '.join(sorted(tables)) or 'aucune'}")
    return 0 if files else 1


def verifier(keys_path, strict):
    keys = [e["key"] for e in json.load(open(keys_path, encoding="utf-8"))]
    en = read_strings(EN)
    fr = read_strings(FR)
    missing = [k for k in keys if k not in en]
    unused = sorted(set(en) - set(keys))
    fr_wrong = sorted(k for k in en if fr.get(k) != k) + sorted(set(fr) - set(en))
    print(f"### Textes en anglais\n\n{len(keys)} textes dans l'app · {len(keys) - len(missing)} traduits · "
          f"**{len(missing)} sans anglais** · {len(unused)} traductions qui ne servent plus · "
          f"{len(fr_wrong)} écarts dans fr.lproj\n")
    if missing:
        print("<details><summary>Sans anglais</summary>\n\n```")
        for k in missing[:400]:
            print(k.replace("\n", "\\n"))
        if len(missing) > 400:
            print(f"… et {len(missing) - 400} de plus")
        print("```\n</details>\n")
    if strict and (missing or fr_wrong):
        return 1
    return 0


def generer(paths):
    en = read_strings(EN)
    for p in paths:
        en.update(json.load(open(p, encoding="utf-8")))
    write_strings(EN, en, HEADER["en"])
    write_strings(FR, {k: k for k in en}, HEADER["fr"])
    print(f"{len(en)} traductions")
    return 0


def nettoyer(keys_path):
    keys = {e["key"] for e in json.load(open(keys_path, encoding="utf-8"))}
    en = read_strings(EN)
    kept = {k: v for k, v in en.items() if k in keys}
    write_strings(EN, kept, HEADER["en"])
    write_strings(FR, {k: k for k in kept}, HEADER["fr"])
    print(f"{len(en) - len(kept)} traductions retirées, {len(kept)} gardées")
    return 0


def main(argv):
    if len(argv) >= 3 and argv[0] == "extraire":
        return extraire(argv[1], argv[2])
    if len(argv) >= 2 and argv[0] == "verifier":
        return verifier(argv[1], "--strict" in argv[2:])
    if len(argv) >= 1 and argv[0] == "generer":
        return generer(argv[1:])
    if len(argv) >= 2 and argv[0] == "nettoyer":
        return nettoyer(argv[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
