from pathlib import Path

import polars as pl


def write_guide_to_lua(
    name: str,
    guide: pl.DataFrame,
    path: Path,
    faction: str,
    next_guide: str | None = None,
    default_for: str | None = None,
):
    header = "local ZygorGuidesViewer=ZygorGuidesViewer\nif not ZygorGuidesViewer then return end\n"
    check_faction = f'if UnitFactionGroup("player")~="{faction}" then return end\n'

    head_guide = f'ZygorGuidesViewer:RegisterGuide("GENERATED\\\\{name}",[[\nauthor TUGs'
    if default_for:
        head_guide += "\ndefaultfor " + default_for

    start_level = name.split("-")[0]
    if next_guide:
        head_guide += f"\nnext GENERATED\\\\{next_guide}"

    head_guide += f"\nstartlevel {start_level}"

    Path.mkdir(path.parent, parents=True, exist_ok=True)

    with path.open("w") as f:
        f.writelines([header, check_faction, head_guide])
        step_id = 1
        for row in guide.iter_rows(named=True):
            step: str | None = row["formatted_text"]
            if step:
                f.write("\nstep\n")  # TODO : Do we need step id ?
                f.write(row["formatted_text"])
                step_id += 1
        f.write("\n]])")
