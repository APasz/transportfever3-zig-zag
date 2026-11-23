"""Check storage and station plugin loading against the installed game's helpers."""

import argparse
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game_dir", type=Path)
    parser.add_argument("--tl", default="tl", help="Teal compiler executable")
    parser.add_argument("--sorting-modes-dir", type=Path, help="Also test the Sorting Modes renderer wrapper")
    parser.add_argument("--terminal-selector-dir", type=Path, help="Also load the Terminal Selector station plugin")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    with TemporaryDirectory(prefix="zigzag-storage-check-") as directory:
        native_dir = Path(directory)
        with ZipFile(args.game_dir / "base/content/warehouses.zip") as archive:
            for name in ("warehouse.script.lua", "modules.script.lua"):
                (native_dir / name).write_bytes(archive.read("warehouses/" + name))
        with ZipFile(args.game_dir / "base/content/scripts.zip") as archive:
            for name in ("metadata_util.tl", "util.tl"):
                (native_dir / name).write_bytes(archive.read("scripts/" + name))
        with ZipFile(args.game_dir / "base/content/gui.zip") as archive:
            (native_dir / "react.lua").write_bytes(archive.read("gui/main/react.lua"))
            (native_dir / "station_group_eow.script.tl").write_bytes(
                archive.read("gui/entity_window/station_group/station_group_eow.script.tl")
            )
            (native_dir / "entity_window_util.tl").write_bytes(
                archive.read("gui/entity_window/entity_window_util.tl")
            )
        if args.terminal_selector_dir is not None:
            content = args.terminal_selector_dir / "content"
            for name in ("station_terminals_plugin.script.tl", "station_terminals_plugin.res.lua"):
                (native_dir / name).write_bytes((content / name).read_bytes())
        for source in sorted(native_dir.glob("*.tl")):
            subprocess.run(
                [args.tl, "gen", "-o", str(source.with_suffix(".lua")), str(source)],
                cwd=repo, check=True,
            )
        subprocess.run(
            ["lua", "tests/cargo_storage_check.lua", str(native_dir)],
            cwd=repo, check=True,
        )
        command = ["lua", "tests/station_window_check.lua", str(native_dir)]
        subprocess.run(command, cwd=repo, check=True)
        if args.sorting_modes_dir is not None:
            for order in ("before-plugin", "after-plugin"):
                subprocess.run(
                    command + [str(args.sorting_modes_dir.resolve()), order],
                    cwd=repo, check=True,
                )


if __name__ == "__main__":
    main()
