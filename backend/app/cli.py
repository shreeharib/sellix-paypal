"""Operator commands: `uv run python -m app.cli --help`.

Until the merchant app's onboarding is built, merchants are set up with these commands.
They stay afterwards as support tools.
"""

import argparse
import asyncio
import json
import secrets
import sys
import uuid
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet

from app.core.config import get_settings
from app.core.db import dispose_engine, session_scope
from app.core.logging import configure_logging
from app.core.runtime import new_event_loop
from app.modules.accounts import service as accounts
from app.modules.agent import service as agent
from app.modules.channels import service as channels
from app.modules.conversations import service as conversations
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.shop_profile import service as shop_profile


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.command == "generate-secrets":
        print(f"TOKEN_ENCRYPTION_KEYS={Fernet.generate_key().decode()}")
        print(f"OAUTH_STATE_SECRET={secrets.token_urlsafe(32)}")
        print(f"SESSION_SIGNING_KEY={secrets.token_urlsafe(48)}")
        print(f"META_VERIFY_TOKEN={secrets.token_urlsafe(24)}")
        return 0
    configure_logging(get_settings().log_level)
    return asyncio.run(_run(args), loop_factory=new_event_loop)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m app.cli", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("generate-secrets", help="print fresh values for the secret settings")

    command = commands.add_parser("create-merchant", help="create a merchant account")
    command.add_argument("--name", required=True)
    command.add_argument("--timezone", default="Asia/Kolkata")

    command = commands.add_parser(
        "connect-instagram", help="print the link a merchant opens to connect Instagram"
    )
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)

    command = commands.add_parser(
        "set-shop-profile", help="save a new version of the shop profile from a Markdown file"
    )
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)
    command.add_argument("--file", type=Path, required=True)

    command = commands.add_parser(
        "set-stock", help="set opening stock from a JSON file (see --help for the format)"
    )
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)
    command.add_argument(
        "--file",
        type=Path,
        required=True,
        help='JSON list: [{"product": "Scoop cookie", "variant": "Chocolate", '
        '"price": "60", "quantity": 10, "currency": "INR"}]; variant and currency are '
        "optional (currency defaults to INR; PayPal needs e.g. USD)",
    )
    command.add_argument(
        "--date", type=date.fromisoformat, help="business date (default: today for the merchant)"
    )
    command.add_argument(
        "--until",
        type=date.fromisoformat,
        help="also set the same stock for every day up to this date (pre-orders)",
    )

    command = commands.add_parser("set-agent", help="switch the agent on or off for a merchant")
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)
    command.add_argument("state", choices=["on", "off"])

    command = commands.add_parser(
        "resume-conversation", help="switch the agent back on for one paused chat"
    )
    command.add_argument("--conversation-id", type=uuid.UUID, required=True)

    command = commands.add_parser(
        "set-agent-engine", help="which agent answers a merchant's customers (v1 or v2)"
    )
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)
    command.add_argument("engine", choices=["v1", "v2", "shadow", "draft"])

    command = commands.add_parser(
        "shadow-report", help="v1 replies next to what v2 would have said (shadow mode)"
    )
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)
    command.add_argument("--days", type=int, default=1)

    command = commands.add_parser(
        "replay-turn", help="re-run a v2 turn's first model call with today's prompts and model"
    )
    command.add_argument("--turn-id", type=uuid.UUID, required=True)

    command = commands.add_parser(
        "issue-token", help="an access token for a merchant (simulator, evals); keep it secret"
    )
    command.add_argument("--merchant-id", type=uuid.UUID, required=True)
    return parser


async def _run(args: argparse.Namespace) -> int:
    try:
        async with session_scope() as session:
            match args.command:
                case "create-merchant":
                    merchant = await merchants.create_merchant(
                        session, name=args.name, timezone=args.timezone
                    )
                    print(f"Created merchant {merchant.id} ({merchant.name})")
                case "connect-instagram":
                    await merchants.get_merchant(session, args.merchant_id)
                    _require_public_https()
                    print(f"Redirect URI to register in Meta: {channels.instagram_redirect_uri()}")
                    print("Open this link and log in with the shop's Instagram account:")
                    print(channels.instagram_authorize_url(args.merchant_id))
                case "set-shop-profile":
                    version = await shop_profile.save_profile(
                        session, args.merchant_id, args.file.read_text(encoding="utf-8")
                    )
                    print(f"Saved shop profile version {version}")
                case "set-stock":
                    merchant = await merchants.get_merchant(session, args.merchant_id)
                    business_date = args.date or merchants.business_date(merchant)
                    lines = _stock_lines(json.loads(args.file.read_text(encoding="utf-8")))
                    last = args.until or business_date
                    day = business_date
                    while day <= last:
                        await inventory.set_opening_stock(
                            session, merchant_id=merchant.id, business_date=day, lines=lines
                        )
                        print(f"Set opening stock for {day}: {len(lines)} items")
                        day += timedelta(days=1)
                case "set-agent":
                    await merchants.set_agent_enabled(session, args.merchant_id, args.state == "on")
                    print(f"Agent switched {args.state}")
                case "resume-conversation":
                    await conversations.set_agent_active(session, args.conversation_id, True)
                    print("Agent switched back on for this chat")
                case "set-agent-engine":
                    await merchants.set_agent_engine(session, args.merchant_id, args.engine)
                    print(f"Agent engine set to {args.engine}")
                case "shadow-report":
                    report = await agent.shadow_report(args.merchant_id, days=args.days)
                    print(json.dumps(report, indent=2, ensure_ascii=False))
                case "replay-turn":
                    print(json.dumps(await agent.replay_turn(args.turn_id), indent=2))
                case "issue-token":
                    await merchants.get_merchant(session, args.merchant_id)
                    print(await accounts.operator_token(session, args.merchant_id))
                case _:
                    raise ValueError(f"Unknown command {args.command}")
    except (ValueError, LookupError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    finally:
        await dispose_engine()
    return 0


def _require_public_https() -> None:
    settings = get_settings()
    if not settings.instagram_app_id:
        raise ValueError("INSTAGRAM_APP_ID is not set")
    if not settings.public_base_url.startswith("https://"):
        raise ValueError("PUBLIC_BASE_URL must be the public https:// address of this API")


def _stock_lines(raw: Any) -> list[OpeningStockLine]:
    if not isinstance(raw, list):
        raise ValueError("The stock file must contain a JSON list")
    lines = []
    for index, item in enumerate(raw, start=1):
        if not isinstance(item, dict) or not str(item.get("product", "")).strip():
            raise ValueError(f"Item {index}: 'product' is required")
        try:
            price = Decimal(str(item["price"]))
            quantity = int(item["quantity"])
        except (KeyError, InvalidOperation, ValueError, TypeError) as exc:
            raise ValueError(f"Item {index}: 'price' and 'quantity' must be numbers") from exc
        price_minor = price * 100
        if price < 0 or price_minor != price_minor.to_integral_value():
            raise ValueError(
                f"Item {index}: price must be a positive amount with at most 2 decimals"
            )
        currency = str(item.get("currency") or "INR").upper()
        if len(currency) != 3 or not currency.isalpha():
            raise ValueError(f"Item {index}: currency must be a 3-letter code such as INR or USD")
        lines.append(
            OpeningStockLine(
                product=str(item["product"]),
                variant=item.get("variant") or None,
                price_minor=int(price_minor),
                quantity=quantity,
                currency=currency,
            )
        )
    return lines


if __name__ == "__main__":
    sys.exit(main())
