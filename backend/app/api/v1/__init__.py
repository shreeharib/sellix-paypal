"""REST API for the merchant app. Routers stay thin: they call module services."""

from fastapi import APIRouter

from app.api.v1 import (
    auth,
    catalog,
    chats,
    onboarding,
    orders,
    questions,
    shop,
    simulator,
    stock,
    stories,
    today,
)

router = APIRouter(prefix="/v1")
router.include_router(auth.router)
router.include_router(shop.router)
router.include_router(onboarding.router)
router.include_router(today.router)
router.include_router(catalog.router)
router.include_router(orders.router)
router.include_router(questions.router)
router.include_router(chats.router)
router.include_router(stories.router)
router.include_router(simulator.router)
router.include_router(stock.router)
