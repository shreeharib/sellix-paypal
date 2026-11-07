"""Read tools for the shop's catalog: search_catalog, get_product_details."""

from datetime import date
from typing import Any

from pydantic import BaseModel, Field

from app.core.db import session_scope
from app.modules.agent import items
from app.modules.agent.tools.registry import Tool, ToolResult, TurnContext, register
from app.modules.catalog import service as catalog


def context_day(day: date) -> str:
    return f"{day:%a} {day.day} {day:%b}"


# Product attributes that answer health and diet questions (section 2, rule 6).
HEALTH_FIELDS = ("ingredients", "allergens", "dietary")


class SearchCatalogArgs(BaseModel):
    query: str = Field(min_length=1, max_length=200)
    limit: int = Field(default=5, ge=1, le=10)


class SearchCatalog(Tool):
    name = "search_catalog"
    Args = SearchCatalogArgs

    async def run(self, ctx: TurnContext, args: SearchCatalogArgs) -> ToolResult:
        in_stock = {item.variant_id: item for item in ctx.stock if item.variant_id}
        async with session_scope() as session:
            found = await catalog.search_catalog_fuzzy(
                session,
                merchant_id=ctx.merchant.id,
                query_text=args.query,
                limit=args.limit,
            )
        results: list[dict[str, Any]] = []
        for product in found:
            for variant in product["variants"]:
                stock = in_stock.get(variant.id)
                name = product["product_name"]
                if variant.name:
                    name = f"{name} ({variant.name})"
                item_id = items.ref(variant.id)
                coming = [
                    f"{context_day(day)}: {s.available} left"
                    for day, day_stock in sorted(ctx.upcoming.items())
                    for s in day_stock
                    if s.variant_id == variant.id and s.available
                ]
                results.append(
                    {
                        "id": item_id,
                        "name": name,
                        "available_today": stock.available if stock else 0,
                        "coming_days": coming or None,
                        "price": f"[[price:{item_id}]]" if stock or coming else None,
                        "matched": product["matched_alias"],
                    }
                )
        if not results:
            return ToolResult(
                True,
                {"items": []},
                hint="Nothing matched: ask what they mean, or check today's menu",
            )
        return ToolResult(True, {"items": results[: args.limit]})


class GetProductDetailsArgs(BaseModel):
    item_id: str = Field(min_length=2, max_length=20)


class GetProductDetails(Tool):
    name = "get_product_details"
    Args = GetProductDetailsArgs

    async def run(self, ctx: TurnContext, args: GetProductDetailsArgs) -> ToolResult:
        item = items.resolve(args.item_id, ctx.all_items())
        if item is None or item.variant_id is None:
            return ToolResult.fail(
                "unknown_item",
                f"No item {args.item_id} on the menu",
                "Use search_catalog to find the item's id",
            )
        async with session_scope() as session:
            [variant] = await catalog.list_variants_by_ids(
                session, ctx.merchant.id, [item.variant_id]
            )
            found = await catalog.get_product_with_variants(
                session, ctx.merchant.id, variant.product_id
            )
        if found is None:
            return ToolResult.fail("unknown_item", f"No item {args.item_id}")
        product, variants, _ = found
        attributes: dict[str, Any] = product.attributes or {}
        details = {field: attributes.get(field) or None for field in HEALTH_FIELDS}
        data = {
            "id": args.item_id,
            "name": item.label,
            "description": product.description or None,
            **details,
            "options": [v.name for v in variants if v.name] or None,
        }
        if all(value is None for value in details.values()):
            return ToolResult(
                True,
                data,
                hint="The shop hasn't listed ingredients or allergens: don't guess, "
                "use ask_shop_owner",
            )
        ctx.health_fields_seen = True
        return ToolResult(True, data, private={"health_fields_seen": True})

    def replay(self, ctx: TurnContext, result: ToolResult) -> None:
        if result.private.get("health_fields_seen"):
            ctx.health_fields_seen = True


register(SearchCatalog())
register(GetProductDetails())
