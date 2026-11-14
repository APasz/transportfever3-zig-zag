"""Run GUI regression checks against the installed game's archived UI helpers."""

import argparse
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("--tl", default="tl", help="Teal compiler executable")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    with TemporaryDirectory(prefix="zigzag-gui-check-") as directory:
        source = Path(directory) / "script_param_util.tl"
        runtime = source.with_suffix(".lua")
        stylesheet_util = Path(directory) / "stylesheetutil.lua"
        string_util = Path(directory) / "stringutil.lua"
        with ZipFile(args.game_dir / "base/content/gui.zip") as archive:
            source.write_bytes(archive.read("gui/main/script_param_util.tl"))
            stylesheet_util.write_bytes(archive.read("gui/main/stylesheetutil.lua"))
        with ZipFile(args.game_dir / "base/content/scripts.zip") as archive:
            string_util.write_bytes(archive.read("scripts/stringutil.lua"))
        subprocess.run(
            [args.tl, "gen", "-o", str(runtime), str(source)], cwd=repo, check=True
        )
        subprocess.run(
            [
                "lua", "tests/track_icons_check.lua", str(runtime),
                str(stylesheet_util), str(string_util),
            ],
            cwd=repo, check=True,
        )


if __name__ == "__main__":
    main()
