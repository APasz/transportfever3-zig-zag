"""Run Zigzag's regression harness with resources and modifiers from installed mods."""

import argparse
import json
import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mods_dir", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    templates: list[str] = []
    categories: list[str] = []
    mods: list[str] = []
    for manifest in sorted(args.mods_dir.resolve().glob("*/mod.json")):
        mod_id = json.loads(manifest.read_text(encoding="utf-8-sig"))["modId"]
        content = manifest.parent / "content"
        mods.append(f"[{lua_string(mod_id)}] = {lua_string(str(content))}")
        for source in sorted(content.rglob("*.lua")):
            if source.name.endswith(".street_template.lua"):
                name = mod_id + "::/" + source.relative_to(content).as_posix()[:-4]
                templates.append(f"{{ name = {lua_string(name)}, path = {lua_string(str(source))} }}")
            elif source.name.endswith(".res.lua") and re.search(r"['\"]menu_category['\"]", source.read_text(encoding="utf-8-sig")):
                categories.append(lua_string(str(source)))
    if not templates:
        parser.error("no installed street templates found")
    with TemporaryDirectory(prefix="zigzag-compatibility-") as directory:
        fixture = Path(directory) / "mods.lua"
        fixture.write_text(
            "return {\ntemplates = {\n" + ",\n".join(templates)
            + "\n},\ncategories = {\n" + ",\n".join(categories)
            + "\n},\nmods = {\n" + ",\n".join(mods) + "\n}\n}\n"
        )
        subprocess.run(["lua", "tests/zigzag_check.lua", "", str(fixture)], cwd=repo, check=True)


if __name__ == "__main__":
    main()
