import warnings
from enum import Enum

import polars as pl


class AutoStrEnum(str, Enum):
    def __str__(self):
        return self.value

    def __repr__(self):
        return self.value


class ActionType(AutoStrEnum):
    ACCEPT = "Accept"
    ACCEPT_OPTIONAL = "AcceptOptional"
    DO = "Do"
    DO_OPTIONAL = "DoOptional"
    DO_OPTIONAL_ELITE = "DoOptionalElite"
    TURN_IN = "TurnIn"
    TURN_IN_OPTIONAL = "TurnInOptional"
    BUY = "Buy"
    LEARN = "Learn"
    COLLECT = "Collect"
    FLY = "Fly"
    GRIND = "Grind"
    GRIND_OPTIONAL = "GrindOptional"
    HEARTHSTONE = "Hearthstone"
    USE_HEARTHSTONE = "UseHearthstone"
    RUN = "Run"
    FLIGHTPATH = "Flightpath"
    TEXT = "Text"


class GuideSchema(AutoStrEnum):
    ACTION = "Action"
    QUEST_ID = "ID"
    ITEM_ID = "ItemID"
    ITEM_AMOUNT = "ItemAmount"
    ITEM_NAME = "ItemName"
    TEXT = "Text"
    LEVEL = "Level"
    LOCATION = "Location"
    CLASS = "Class"
    COORDS = "Coords"
    NPC_NAME = "NpcName"
    NPC_ID = "NpcId"
    QUEST_NAME = "QuestName"
    # NOTE : These are not present in the current files and are generated
    X = "X"
    Y = "Y"


warnings.filterwarnings("ignore", category=pl.exceptions.PolarsInefficientMapWarning)


def convert_lists_to_strings(df: pl.DataFrame):
    list_cols = [col for col in df.columns if df.schema[col] in [pl.List]]

    if not list_cols:
        return df

    return df.with_columns(
        [
            pl.col(col)
            .map_elements(lambda x: str(x) if not None else None, return_dtype=pl.String)
            .alias(col)
            for col in list_cols
        ]
    )
