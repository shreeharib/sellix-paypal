"""Public pages and callbacks, no sign-in: the privacy policy, how to delete your data, and
Meta's data-deletion callback (register its URL in the Meta app's settings)."""

from html import escape
from typing import Annotated
from urllib.parse import parse_qs, urlencode

import structlog
from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from app.core.config import get_settings
from app.core.db import session_scope
from app.modules.channels import service as channels
from app.modules.merchants import service as merchants

router = APIRouter(tags=["public"])
log = structlog.get_logger()

# Shown on both pages until the operator fills it in (docs/HANDOFF.md, open items).
CONTACT_PLACEHOLDER = "[CONTACT EMAIL: the sellix operator must fill this in before launch]"


class DataDeletionAnswer(BaseModel):
    url: str  # where the person can check their request
    confirmation_code: str


_PRIVACY = f"""
<p>sellix is an assistant for small shops on Instagram. It answers the messages customers send
to a shop's Instagram account, takes their orders, and shows the shop owner their chats and
orders in the sellix app. This page says what sellix stores and how to delete it. sellix is run
by the sellix operator; contact: {escape(CONTACT_PLACEHOLDER)}.</p>

<h2>What sellix stores about a shop</h2>
<ul>
<li>The shop's Instagram professional account id and username, and the access token Instagram
gives sellix to read and answer the shop's messages (stored encrypted).</li>
<li>The shop's name, time zone, settings, set-up answers and shop description; its products,
prices and stock; and the answers the owner saved for the assistant to give.</li>
<li>If the shop connects Razorpay: its Razorpay key id and key secret (the secret encrypted),
and the payment links, payments and refunds of its orders.</li>
<li>Sign-in sessions of the people who use the sellix app for the shop.</li>
</ul>

<h2>What sellix stores about a shop's customers</h2>
<ul>
<li>Their Instagram id for that shop, and the name and username on their Instagram profile.</li>
<li>The messages they exchange with the shop on Instagram, including replies to the shop's
stories. For photos and shared posts sellix keeps only Instagram's link; it doesn't copy the
media.</li>
<li>Details they give for an order (such as name, phone number, delivery address and notes),
and a few facts the assistant remembers to serve them better (their name, preferred language,
address, usual order, a dietary note or an occasion).</li>
<li>Their orders and payment status. Card, UPI and bank details are handled by Razorpay and
never reach sellix.</li>
</ul>

<h2>How it is used</h2>
<p>Only to run the shop's assistant and app: answering customers on the shop's behalf, taking
and tracking orders, and showing the shop owner what happened. To write a reply, sellix sends
the recent messages of that chat and the shop's details to the AI model provider the operator
has configured. sellix doesn't sell this data or use it for advertising. Copies of the raw
notifications Instagram sends sellix (which include message text) are kept for
troubleshooting; they aren't linked to a shop record and aren't removed when a shop is
deleted.</p>

<h2>Deleting data</h2>
<p>The shop owner can delete the shop and everything sellix stores about it and its customers
in the sellix app (Settings, Delete shop). Removing sellix in the Instagram account's settings
(Apps and websites) and asking Instagram to delete your data there does the same. See
<a href="/data-deletion">how to delete your data</a>. A customer who wants their messages
deleted can ask the shop, or write to {escape(CONTACT_PLACEHOLDER)}.</p>
"""

_DELETION_HOWTO = f"""
<p><strong>Shop owners:</strong> in the sellix app open Settings, then Delete shop, and type
the shop's name. Or, in Instagram's settings (Apps and websites), remove sellix and ask for
your data to be deleted: Instagram tells sellix. Either way sellix deletes the shop and
everything it stores about it: its Instagram connection, products, stock, chats and messages,
customers, orders, payment records and saved answers, and signs everyone out of the app.</p>
<p><strong>Customers of a shop:</strong> ask the shop to delete your chat, or write to
{escape(CONTACT_PLACEHOLDER)} with the shop's Instagram name and yours.</p>
<p>See the <a href="/privacy">privacy policy</a> for what sellix stores.</p>
"""


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
async def privacy() -> HTMLResponse:
    return _page("Privacy policy", _PRIVACY)


@router.get("/data-deletion", response_class=HTMLResponse, include_in_schema=False)
async def data_deletion(code: Annotated[str | None, Query(max_length=64)] = None) -> HTMLResponse:
    if not code:
        return _page("Delete your data", _DELETION_HOWTO)
    async with session_scope() as session:
        request = await merchants.deletion_request(session, code)
    if request is None:
        return _page(
            "Deletion request not found",
            f"<p>There is no deletion request with the code {escape(code)}.</p>" + _DELETION_HOWTO,
            status_code=404,
        )
    when = request.requested_at.strftime("%d %b %Y")
    outcome = (
        "The shop and all the data sellix stored about it were deleted."
        if request.status == "deleted"
        else "sellix had no shop data for this Instagram account, so there was nothing to delete."
    )
    return _page(
        "Deletion request",
        f"<p>Request {escape(request.code)}, received on {escape(when)}.</p>"
        f"<p>{escape(outcome)}</p>",
    )


@router.post("/auth/instagram/data-deletion")
@router.post("/v1/auth/instagram/data-deletion", include_in_schema=False)
async def instagram_data_deletion(request: Request) -> DataDeletionAnswer:
    """Meta's data-deletion callback: a person removed sellix from their Instagram account and
    asked for their data to be deleted. The `signed_request` form field is checked with the
    Instagram app secret; the shop connected to that account is deleted."""
    form = parse_qs((await request.body()).decode("utf-8", errors="replace"))
    signed_request = (form.get("signed_request") or [""])[0]
    try:
        user_id = channels.data_deletion_user_id(signed_request)
    except channels.InvalidSignedRequest as exc:
        log.warning("public.data_deletion_refused", reason=str(exc))
        raise HTTPException(status_code=400, detail="Invalid signed_request") from exc
    async with session_scope() as session:
        merchant_id = await channels.merchant_for_instagram_account(session, user_id)
        if merchant_id is not None:
            code = await merchants.delete_shop(session, merchant_id, source="meta")
        else:
            code = await merchants.record_deletion(session, source="meta", status="no_data")
    log.info("public.data_deletion", code=code, found=merchant_id is not None)
    base = get_settings().public_base_url.rstrip("/")
    return DataDeletionAnswer(
        url=f"{base}/data-deletion?{urlencode({'code': code})}", confirmation_code=code
    )


def _page(title: str, body_html: str, *, status_code: int = 200) -> HTMLResponse:
    html = (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        f"<title>{escape(title)} · sellix</title>"
        "<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:3rem auto;"
        "padding:0 1rem;line-height:1.55;color:#1a1a1a}h1{font-size:1.5rem}"
        "h2{font-size:1.1rem;margin-top:1.75rem}a{color:inherit}"
        "@media (prefers-color-scheme:dark){body{background:#111;color:#eee}}</style></head>"
        f"<body><h1>{escape(title)}</h1>{body_html}</body></html>"
    )
    return HTMLResponse(html, status_code=status_code)
