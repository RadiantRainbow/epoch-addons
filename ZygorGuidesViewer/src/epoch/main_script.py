import logging
from pathlib import Path

import polars as pl

from epoch.convert_to_lua import add_conditional, build_action_expression
from epoch.lua_writer import write_guide_to_lua
from epoch.utils import GuideSchema, convert_lists_to_strings

logger = logging.getLogger("Epoch")
logging.basicConfig(level=logging.DEBUG)


def convert_all_guides():
    data_path = Path(__file__).parent.parent / "data"
    df_set = {}

    for file_path in data_path.iterdir():
        if not file_path.name.endswith(".csv"):
            logger.warning(f"File not in CSV format : {file_path.name}. Skipping.")
            continue
        logger.info(f"Converting {file_path.name}")
        df = convert_guide(pl.read_csv(file_path).with_row_index("row_id"))
        df_set[file_path.name] = df
        df = convert_lists_to_strings(df).drop("Name")  # Name is the old column
        # Debug df to CSV file
        write_guide_to_csv(file_path.name, df, data_path.parent / "updated_guides" / "csv")

    guide_structure = pl.read_csv(data_path.parent / "guides_structure.csv").with_columns(
        pl.col("Name").alias("Name_raw"), pl.concat_str([pl.col("Name"), pl.lit(".csv")])
    )
    lua_path = data_path.parent / "updated_guides" / "lua"
    for row in guide_structure.iter_rows(named=True):
        write_guide_to_lua(
            row["Name_raw"],
            df_set[row["Name"]],
            Path(lua_path) / (row["Name_raw"] + ".lua"),
            row["Faction"],
            row["Next"],
        )


def parse_coords(df: pl.DataFrame):
    df = df.with_columns(pl.col("Coords").str.split(",").alias("coords_split"))
    df_coords_split = (
        df.filter(pl.col("coords_split").is_not_null()).with_columns(
            pl.col("coords_split").list.get(0).alias(GuideSchema.X),
            pl.col("coords_split").list.get(1).alias(GuideSchema.Y),
        )
    ).select("row_id", GuideSchema.X, GuideSchema.Y)

    df = (
        df.join(df_coords_split, how="left", on="row_id")
        # TODO : Add these columns to the CSV
        .with_columns(pl.lit("").alias(GuideSchema.NPC_NAME), pl.lit("").alias(GuideSchema.NPC_ID))
    )
    return df


def parse_class(df: pl.DataFrame):
    if "Class,Rep" in df.columns:
        return df.with_columns(pl.col("Class,Rep").alias(GuideSchema.CLASS)).drop("Class,Rep")
    return df


def sanitize_df(df: pl.DataFrame):
    if "ItemID" not in df.columns:
        df = df.with_columns(pl.lit(None).alias(GuideSchema.ITEM_ID))
    if GuideSchema.ITEM_NAME not in df.columns:
        df = df.with_columns(pl.lit(None).alias(GuideSchema.ITEM_NAME))
    if GuideSchema.ITEM_AMOUNT not in df.columns:
        df = df.with_columns(pl.lit(None).alias(GuideSchema.ITEM_AMOUNT))
    if GuideSchema.QUEST_NAME not in df.columns:
        # TODO : This only happens in the 6-9 Gnome guide which is missing Quest names
        df = df.with_columns(pl.lit("").alias(GuideSchema.QUEST_NAME))
    return df.pipe(parse_coords).pipe(parse_class)


def convert_guide(df: pl.DataFrame):
    df = df.pipe(sanitize_df)
    df = df.with_columns(build_action_expression())
    df = df.with_columns(add_conditional())

    return df


def write_guide_to_csv(name: str, df: pl.DataFrame, path: Path):
    Path.mkdir(path, parents=True, exist_ok=True)
    df.write_csv(path / name)
