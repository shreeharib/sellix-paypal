"""What the add-product form asks this shop, from its shop-type template (shop_types.yaml)."""

from fastapi import APIRouter
from pydantic import BaseModel

from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.shop_profile import service as shop_profile
from app.modules.shop_profile.schemas import ProductSchema

router = APIRouter(tags=["product-schema"])


class ShopTypeChoice(BaseModel):
    id: str
    label: str


@router.get("/product-schema")
async def get_product_schema(shop: Shop) -> ProductSchema:
    """The stock choices and detail fields for this shop's type (or its category's best match)."""
    async with session_scope() as session:
        onboarding = await shop_profile.get_onboarding(session, shop.merchant_id)
    return shop_profile.product_schema(onboarding.answers if onboarding else None)


@router.get("/shop-types")
async def list_shop_types(shop: Shop) -> list[ShopTypeChoice]:
    """Every shop type a shop can pick, for the chooser in onboarding and settings."""
    return [
        ShopTypeChoice(id=type_id, label=label)
        for type_id, label in shop_profile.shop_type_choices()
    ]
