"""Public endpoint Instagram's OAuth redirects to: app logins and operator connects."""

from html import escape
from typing import Annotated
from urllib.parse import urlencode

import structlog
from fastapi import APIRouter, Query
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from app.core.db import session_scope
from app.modules.accounts import service as accounts
from app.modules.channels import service
from app.modules.merchants.service import MerchantNotFound

router = APIRouter(prefix="/oauth", tags=["channels"])
log = structlog.get_logger()

CANCELLED_MESSAGE = "Instagram wasn't connected. Please try again."


@router.get("/instagram/callback", response_class=HTMLResponse)
async def instagram_callback(
    code: Annotated[str | None, Query()] = None,
    state: Annotated[str | None, Query()] = None,
    error: Annotated[str | None, Query()] = None,
    error_description: Annotated[str | None, Query()] = None,
) -> Response:
    app_redirect = service.login_redirect_for(state) if state else None
    if error or not code or not state:
        log.info("channels.instagram_oauth_cancelled", error=error, detail=error_description)
        return _fail(app_redirect, CANCELLED_MESSAGE)

    try:
        # Committed before redirecting: the app redeems the login code straight away.
        async with session_scope() as session:
            result = await service.complete_instagram_oauth(session, code=code, state=state)
            login_code = None
            if result.is_login and result.code_challenge:
                user_id = await accounts.sign_in(
                    session,
                    provider="instagram",
                    subject=result.account_id,
                    merchant_id=result.connection.merchant_id,
                    display_name=result.username,
                )
                login_code = await accounts.create_login_code(
                    session, user_id, result.code_challenge
                )
    except (service.ChannelConnectError, MerchantNotFound) as exc:
        return _fail(app_redirect, str(exc))

    if login_code is not None and result.app_redirect_uri:
        return RedirectResponse(
            f"{result.app_redirect_uri}?{urlencode({'code': login_code})}", status_code=303
        )
    return _page(
        "Instagram connected",
        f"@{result.username} is connected to sellix. You can close this page.",
        200,
    )


def _fail(app_redirect: str | None, message: str) -> Response:
    if app_redirect:
        return RedirectResponse(f"{app_redirect}?{urlencode({'error': message})}", status_code=303)
    return _page("Not connected", message, 400)


def _page(title: str, message: str, status_code: int) -> HTMLResponse:
    html = (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>{escape(title)} · sellix</title>"
        "<style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:4rem auto;"
        "padding:0 1rem;line-height:1.5}</style></head>"
        f"<body><h1>{escape(title)}</h1><p>{escape(message)}</p></body></html>"
    )
    return HTMLResponse(html, status_code=status_code)
