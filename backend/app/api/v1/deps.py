"""Who is calling: the signed-in user and the shop they manage."""

import uuid
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header, HTTPException

from app.core.db import session_scope
from app.modules.accounts import service as accounts
from app.modules.accounts.schemas import Principal


@dataclass(frozen=True)
class ShopContext:
    user_id: uuid.UUID
    session_id: uuid.UUID
    merchant_id: uuid.UUID
    role: str


async def principal(authorization: Annotated[str | None, Header()] = None) -> Principal:
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Sign in required")
    try:
        return accounts.verify_access_token(token)
    except accounts.AuthFailed as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


async def shop(caller: Annotated[Principal, Depends(principal)]) -> ShopContext:
    async with session_scope() as session:
        member = await accounts.membership(session, caller.user_id)
    if member is None:
        raise HTTPException(status_code=403, detail="This account isn't linked to a shop")
    return ShopContext(
        user_id=caller.user_id,
        session_id=caller.session_id,
        merchant_id=member.merchant_id,
        role=member.role,
    )


Shop = Annotated[ShopContext, Depends(shop)]
