import logging

import polars as pl
from polars import col, lit

from epoch.utils import ActionType, GuideSchema

logger = logging.getLogger("convert")
EB = lit("]")


def accept_case():
    return (
        col(GuideSchema.ACTION) == ActionType.ACCEPT,
        pl.concat_str(
            # TODO : Currently no NPC set, only quests
            # lit("talk "),
            # col(GuideSchema.NPC_NAME),
            # lit("##"),
            # col(GuideSchema.NPC_ID),
            # lit("\n"),
            lit("accept "),
            col(GuideSchema.QUEST_NAME),
            lit("##"),
            col(GuideSchema.QUEST_ID),
            # TODO : Location not set for the quest giver
            # lit(" |goto "),
            # col(GuideSchema.LOCATION),
            # lit(" "),
            # col(GuideSchema.X),
            # lit(","),
            # col(GuideSchema.Y),
        ),
    )


def accept_optional_case():
    return (
        col(GuideSchema.ACTION) == ActionType.ACCEPT_OPTIONAL,
        pl.concat_str(
            # TODO : Currently no NPC set, only quests
            # lit("talk "),
            # col(GuideSchema.NPC_NAME),
            # lit("##"),
            # col(GuideSchema.NPC_ID),
            # lit("\n"),
            lit("accept "),
            col(GuideSchema.QUEST_NAME),
            lit("##"),
            col(GuideSchema.QUEST_ID),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
            lit(" |optional"),
        ),
    )


def do_case():
    return (
        col(GuideSchema.ACTION) == ActionType.DO,
        # TODO : Improve this by specifying what we need to do
        pl.concat_str(lit("Do: "), col(GuideSchema.QUEST_NAME), lit(" |q "), col(GuideSchema.QUEST_ID)),
    )


def do_optional_case():
    return (
        col(GuideSchema.ACTION) == ActionType.DO_OPTIONAL,
        pl.concat_str(lit("Do (Optional): "), col(GuideSchema.QUEST_NAME)),
    )


def do_optional_elite_case():
    return (
        col(GuideSchema.ACTION) == ActionType.DO_OPTIONAL_ELITE,
        pl.concat_str(lit("Do (Elite - Optional, group recommended): "), col(GuideSchema.TEXT)),
    )


def turn_in_case():
    return (
        col(GuideSchema.ACTION) == ActionType.TURN_IN,
        pl.concat_str(
            # TODO : Currently no NPC set, only quests
            # lit("talk "),
            # col(GuideSchema.NPC_NAME),
            # lit("##"),
            # col(GuideSchema.NPC_ID),
            # lit("\n"),
            lit("turnin "),
            col(GuideSchema.QUEST_NAME),
            lit("##"),
            col(GuideSchema.QUEST_ID),
            # TODO : Currently no location for quest givers
            # lit(" |goto "),
            # col(GuideSchema.LOCATION),
            # lit(" "),
            # col(GuideSchema.X),
            # lit(","),
            # col(GuideSchema.Y),
        ),
    )


def turn_in_optional_case():
    return (
        col(GuideSchema.ACTION) == ActionType.TURN_IN_OPTIONAL,
        pl.concat_str(
            # TODO : Currently no NPC set, only quests
            # lit("talk "),
            # col(GuideSchema.NPC_NAME),
            # lit("##"),
            # col(GuideSchema.NPC_ID),
            # lit("\n"),
            lit("turnin "),
            col(GuideSchema.QUEST_NAME),
            lit("##"),
            col(GuideSchema.QUEST_ID),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
            lit(" |optional"),
        ),
    )


def buy_case():
    return (
        col(GuideSchema.ACTION) == ActionType.BUY,
        pl.concat_str(
            lit("talk "),
            col(GuideSchema.NPC_NAME),
            lit("##"),
            col(GuideSchema.NPC_ID),
            lit("\n"),
            lit("buy "),
            col(GuideSchema.ITEM_NAME),
            lit("##"),
            col(GuideSchema.ITEM_ID),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
        ),
    )


def learn_case():
    return (
        col(GuideSchema.ACTION) == ActionType.LEARN,
        pl.concat_str(
            lit("Get your level "),
            col(GuideSchema.LEVEL),
            lit(" spells at your trainer"),
        ),
    )


# TODO : This is not currently used
def collect_case():
    return (
        col(GuideSchema.ACTION) == ActionType.COLLECT,
        pl.concat_str(
            lit("collect "),
            col(GuideSchema.ITEM_AMOUNT),
            lit(" "),
            col(GuideSchema.ITEM_NAME),
            lit("##"),
            col(GuideSchema.ITEM_ID),
            lit(" |q "),
            col(GuideSchema.QUEST_ID),
            lit("/"),
            # TODO : Implement this
            # col(GuideSchema.OBJECTIVE_NUM),
            lit("1"),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
        ),
    )


def fly_case():
    return (
        col(GuideSchema.ACTION) == ActionType.FLY,
        pl.concat_str(
            lit("fpath "),
            col(GuideSchema.LOCATION),
            # TODO : LOCATION is used for the destination, there are no coords for the flight master
            #     lit(" |goto "),
            #     col(GuideSchema.LOCATION),
            #     lit(" "),
            #     col(GuideSchema.X),
            #     lit(","),
            #     col(GuideSchema.Y),
        ),
    )


def grind_case():
    return (
        col(GuideSchema.ACTION) == ActionType.GRIND,
        pl.concat_str(
            lit("Grind until level"),
            col(GuideSchema.LEVEL),
            lit("\n|ding "),
            col(GuideSchema.LEVEL),
        ),
    )


def grind_optional_case():
    return (
        col(GuideSchema.ACTION) == ActionType.GRIND_OPTIONAL,
        pl.concat_str(
            lit("Kill enemies around this area\n"),
            lit("ding "),
            col(GuideSchema.LEVEL),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
            lit(" |optional"),
        ),
    )


def hearthstone_case():
    return (
        col(GuideSchema.ACTION) == ActionType.HEARTHSTONE,
        pl.concat_str(
            lit("home "),
            col(GuideSchema.LOCATION),
            # TODO : Currently no location for the hearthstone setter in the CSV
            # lit(" |goto "),
            # col(GuideSchema.LOCATION),
            # lit(" "),
            # col(GuideSchema.X),
            # lit(","),
            # col(GuideSchema.Y),
        ),
    )


def use_hearthstone_case():
    return (col(GuideSchema.ACTION) == ActionType.USE_HEARTHSTONE, pl.lit("use Hearthstone##6948"))


def run_case():
    return (
        col(GuideSchema.ACTION) == ActionType.RUN,
        pl.concat_str(
            lit("Run to "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
        ),
    )


def flightpath_case():
    return (
        col(GuideSchema.ACTION) == ActionType.FLIGHTPATH,
        pl.concat_str(
            # TODO : Check what to do for the flightpath
            lit("fpath "),
            col(GuideSchema.LOCATION),
            lit(" |goto "),
            col(GuideSchema.LOCATION),
            lit(" "),
            col(GuideSchema.X),
            lit(","),
            col(GuideSchema.Y),
        ),
    )


def text_case():
    return (
        col(GuideSchema.ACTION) == ActionType.TEXT,
        col(GuideSchema.TEXT),
    )


def build_action_expression():
    cases = [
        accept_case(),
        accept_optional_case(),
        do_case(),
        do_optional_case(),
        do_optional_elite_case(),
        turn_in_case(),
        turn_in_optional_case(),
        buy_case(),
        learn_case(),
        collect_case(),
        fly_case(),
        grind_case(),
        grind_optional_case(),
        hearthstone_case(),
        use_hearthstone_case(),
        run_case(),
        flightpath_case(),
        text_case(),
    ]

    expr: pl.Expr = pl.when(cases[0][0]).then(cases[0][1])

    for condition, then_expr in cases[1:]:
        expr = expr.when(condition).then(then_expr)

    return expr.otherwise(lit("")).alias("formatted_text")


def add_conditional():
    return (
        pl.when(col(GuideSchema.CLASS).is_not_null())
        .then(pl.concat_str(col("formatted_text"), lit("\n|only if "), col(GuideSchema.CLASS)))
        .otherwise("formatted_text")
    )
