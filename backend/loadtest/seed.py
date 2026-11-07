"""Creates test shops for the load test: `uv run python -m loadtest.seed --shops 20`.

Each shop gets stock for today and a signed-in operator user. The access tokens go to
loadtest/tokens.txt (one per line) and last 15 minutes, so seed right before a run. Point
DATABASE_URL at a staging database, never production.
"""

import argparse
import asyncio
from pathlib import Path

from app.core.config import get_settings
from app.core.db import dispose_engine, session_scope
from app.core.runtime import new_event_loop
from app.modules.accounts import service as accounts
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants

TOKENS = Path(__file__).parent / "tokens.txt"


async def main(shops: int) -> None:
    if get_settings().app_env == "prod":
        raise SystemExit("Refusing to seed load-test shops into a prod environment")
    tokens: list[str] = []
    try:
        for number in range(shops):
            async with session_scope() as session:
                merchant = await merchants.create_merchant(session, name=f"Load shop {number}")
                await inventory.set_opening_stock(
                    session,
                    merchant_id=merchant.id,
                    business_date=merchants.business_date(merchant),
                    lines=[
                        OpeningStockLine("Brownie", None, 9000, 500),
                        OpeningStockLine("Cookie", "Chocolate", 6000, 500),
                    ],
                )
                tokens.append(await accounts.operator_token(session, merchant.id))
    finally:
        await dispose_engine()
    TOKENS.write_text("\n".join(tokens), encoding="utf-8")
    print(f"Created {shops} shops; tokens in {TOKENS}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--shops", type=int, default=20)
    asyncio.run(main(parser.parse_args().shops), loop_factory=new_event_loop)
