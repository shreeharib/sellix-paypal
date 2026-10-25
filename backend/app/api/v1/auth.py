"""Sign in with Instagram (PKCE), refresh and sign out."""

from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Response

from app.api.v1 import schemas
from app.api.v1.deps import principal
from app.core.db import session_scope
from app.modules.accounts import service as accounts
from app.modules.accounts.schemas import Principal, TokenPair
from app.modules.channels import service as channels

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/instagram/start")
async def start_instagram_login(body: schemas.InstagramLoginStart) -> schemas.InstagramLoginUrl:
    """Step 1: the app opens the returned URL in a browser."""
    try:
        url = channels.instagram_login_url(
            code_challenge=body.code_challenge, app_redirect_uri=body.redirect_uri
        )
    except channels.ChannelConnectError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return schemas.InstagramLoginUrl(authorize_url=url)


@router.post("/token")
async def exchange_login_code(
    body: schemas.TokenRequest, user_agent: Annotated[str | None, Header()] = None
) -> schemas.Tokens:
    """Step 2: the app trades the one-time code from the redirect, with its PKCE verifier."""
    try:
        async with session_scope() as session:
            pair = await accounts.redeem_login_code(
                session, code=body.code, code_verifier=body.code_verifier, user_agent=user_agent
            )
    except accounts.AuthFailed as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    return _tokens(pair)


@router.post("/refresh")
async def refresh_tokens(
    body: schemas.RefreshRequest, user_agent: Annotated[str | None, Header()] = None
) -> schemas.Tokens:
    async with session_scope() as session:  # commits even when refused (reuse revocation)
        pair = await accounts.refresh(
            session, refresh_token=body.refresh_token, user_agent=user_agent
        )
    if pair is None:
        raise HTTPException(status_code=401, detail="Please sign in again.")
    return _tokens(pair)


@router.post("/logout", status_code=204)
async def logout(caller: Annotated[Principal, Depends(principal)]) -> Response:
    async with session_scope() as session:
        await accounts.revoke_session(session, caller.session_id)
    return Response(status_code=204)


def _tokens(pair: TokenPair) -> schemas.Tokens:
    return schemas.Tokens(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
    )
