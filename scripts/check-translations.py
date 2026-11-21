"""Fails when a String Catalog lacks a translation, or a translation drops or adds a placeholder."""

import json
import re
import sys

LANGUAGES = ("de", "fr", "hr")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f)|%%|\$\{[a-zA-Z]+\}")

problems = []
for path in sys.argv[1:]:
    catalog = json.load(open(path, encoding="utf-8"))
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        source = localizations.get("en", {}).get("stringUnit", {}).get("value", key)
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit")
            if not unit or unit.get("state") != "translated":
                problems.append(f"{path}: no {language} for {key!r}")
            elif sorted(PLACEHOLDER.findall(unit["value"])) != sorted(PLACEHOLDER.findall(source)):
                problems.append(f"{path}: {language} placeholders differ for {key!r}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
