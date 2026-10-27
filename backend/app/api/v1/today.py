"""The Today screen: stock, today's numbers, and the morning stock update."""

import uuid

from fastapi import APIRouter, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import schemas
from app.api.v1.deps import Shop
from app.core.db import session_scope
from app.modules.escalations import service as escalations
from app.modules.inventory import service as inventory
from app.modules.inventory.schemas import OpeningStockLine
from app.modules.merchants import service as merchants
from app.modules.orders import service as orders

router = APIRouter(prefix="/today", tags=["today"])


@router.get("")
async def today(shop: Shop) -> schemas.Today:
    async with session_scope() as session:
        return await _today(session, shop.merchant_id)


@router.put("/stock")
async def set_opening_stock(shop: Shop, body: schemas.OpeningStock) -> schemas.Today:
    """The morning stock update; a later update the same day replaces the opening counts."""
    try:
        async with session_scope() as session:
            merchant = await merchants.get_merchant(session, shop.merchant_id)
            await inventory.set_opening_stock(
                session,
                merchant_id=merchant.id,
                business_date=merchants.business_date(merchant),
                lines=[
                    OpeningStockLine(
                        product=line.product,
                        variant=line.variant,
                        price_minor=line.price_minor,
                        quantity=line.quantity,
                        currency=line.currency,
                    )
                    for line in body.lines
                ],
            )
    except ValueError as exc:  # includes StockConflict
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    async with session_scope() as session:
        return await _today(session, shop.merchant_id)


@router.post("/restock")
async def restock(shop: Shop, body: schemas.RestockRequest) -> schemas.Today:
    """Add extra inventory for an item during the day (e.g. fresh afternoon batch)."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        day = merchants.business_date(merchant)
        try:
            await inventory.restock(
                session,
                variant_id=body.variant_id,
                business_date=day,
                quantity=body.quantity,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    async with session_scope() as session:
        return await _today(session, shop.merchant_id)


@router.post("/sold-out")
async def mark_sold_out(shop: Shop, body: schemas.SoldOutRequest) -> schemas.Today:
    """Mark an item as sold out for the day (zeroes remaining available stock)."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        day = merchants.business_date(merchant)
        try:
            await inventory.mark_sold_out(
                session,
                variant_id=body.variant_id,
                business_date=day,
            )
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    async with session_scope() as session:
        return await _today(session, shop.merchant_id)


@router.post("/counter-sale")
async def record_counter_sale(
    shop: Shop, body: schemas.CounterSaleRequest
) -> schemas.CounterSaleResponse:
    """Record an in-store counter sale, deducting units from available online stock."""
    async with session_scope() as session:
        merchant = await merchants.get_merchant(session, shop.merchant_id)
        day = merchants.business_date(merchant)
        try:
            remaining = await inventory.record_counter_sale(
                session,
                variant_id=body.variant_id,
                business_date=day,
                quantity=body.quantity,
            )
        except inventory.StockConflict as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except LookupError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    async with session_scope() as session:
        current_today = await _today(session, shop.merchant_id)

    return schemas.CounterSaleResponse(
        variant_id=body.variant_id,
        business_date=day,
        quantity_sold=body.quantity,
        remaining_available=remaining,
        today=current_today,
    )


@router.post("/parse-stock-text")
async def parse_stock_text(body: schemas.ParseStockTextRequest) -> schemas.OpeningStock:
    """Parse free-form merchant text into structured stock lines for morning setup."""
    try:
        lines = inventory.parse_stock_text(body.text, default_currency=body.default_currency)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return schemas.OpeningStock(
        lines=[
            schemas.StockLine(
                product=line.product,
                variant=line.variant,
                price_minor=line.price_minor,
                currency=line.currency,
                quantity=line.quantity,
            )
            for line in lines
        ]
    )


async def _today(session: AsyncSession, merchant_id: uuid.UUID) -> schemas.Today:
    merchant = await merchants.get_merchant(session, merchant_id)
    day = merchants.business_date(merchant)
    ledger = await inventory.day_ledger(session, merchant_id, day)
    summary = await orders.day_summary(session, merchant_id, day)
    open_questions = await escalations.list_escalations(session, merchant_id, status="open")
    return schemas.Today(
        business_date=day,
        agent_enabled=merchant.agent_enabled,
        stock=[schemas.StockRow(**vars(row)) for row in ledger],
        open_questions=len(open_questions),
        orders_awaiting_payment=summary.awaiting_payment,
        orders_paid=summary.paid,
        revenue_minor_by_currency=summary.revenue_minor_by_currency,
    )
