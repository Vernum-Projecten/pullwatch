"""scripts/dev/catalog-tidy.py <catalog.xcstrings> <file.stringsdata>...

Called by sync-strings.sh after `xcstringstool sync`. Removes every entry the
compiler did not extract in this build (so text that left the code leaves the
catalog), keeps entries marked "shouldTranslate": false, and writes the
catalog with sorted keys in this repository's JSON style.
"""
import json
import os
import sys

# Only files inside this repository (sync-strings.sh builds into
# build/DerivedData here), with the expected extension, are read or written.
ROOT = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def confined(path, suffix):
    resolved = os.path.realpath(path)
    if os.path.commonpath([ROOT, resolved]) != ROOT or not resolved.endswith(suffix):
        sys.exit(f"catalog-tidy: {path} is not a {suffix} file inside {ROOT}")
    return resolved


catalog, *data = sys.argv[1:]
catalog = confined(catalog, ".xcstrings")
data = [confined(path, ".stringsdata") for path in data]
used = set()
for path in data:
    with open(path, encoding="utf-8") as f:
        for entries in json.load(f).get("tables", {}).values():
            used.update(entry["key"] for entry in entries)

with open(catalog, encoding="utf-8") as f:
    d = json.load(f)
strings = d["strings"]
unused = sorted(k for k, v in strings.items() if k not in used and v.get("shouldTranslate") is not False)
# A build that extracted nothing (or far less than before) means the input is
# wrong, not that the text is gone: change nothing.
if not used or len(unused) > len(strings) / 4:
    sys.exit(f"catalog-tidy: {len(unused)} of {len(strings)} entries look unused in {catalog}; refusing to remove them")
for key in unused:
    del strings[key]
    print(f"removed: {key}")
d["strings"] = dict(sorted(strings.items()))
with open(catalog, "w", encoding="utf-8") as f:
    f.write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
