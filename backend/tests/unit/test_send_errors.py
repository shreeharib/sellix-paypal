"""Instagram send errors are classified so the outbox knows whether to retry."""

import pytest

from app.modules.channels import instagram
from app.modules.channels import service as channels
from app.modules.conversations import outbox

CREDENTIALS = channels.SendCredentials(channel="instagram", account_id="1", access_token="t")


@pytest.mark.parametrize(
    ("error", "reason"),
    [
        (instagram.InstagramAPIError(0, "network error: ReadTimeout"), "retryable"),
        (instagram.InstagramAPIError(500, "oops"), "retryable"),
        (instagram.InstagramAPIError(429, "slow down"), "retryable"),
        (instagram.InstagramAPIError(400, "too many", code=613), "retryable"),
        (
            instagram.InstagramAPIError(400, "outside window", code=10, subcode=2018278),
            "window_closed",
        ),
        (instagram.InstagramAPIError(400, "not available", code=551), "recipient_unavailable"),
        (instagram.InstagramAPIError(400, "token expired", code=190), "permanent"),
        (instagram.InstagramAPIError(400, "bad recipient", code=100), "permanent"),
    ],
)
@pytest.mark.anyio
async def test_instagram_errors_are_classified(
    monkeypatch: pytest.MonkeyPatch, error: instagram.InstagramAPIError, reason: str
) -> None:
    async def send_text(**_: str) -> str:
        raise error

    monkeypatch.setattr(instagram, "send_text", send_text)

    with pytest.raises(channels.SendFailed) as raised:
        await channels.send_text(CREDENTIALS, "2", "hi")

    assert raised.value.reason == reason
    assert raised.value.retryable is (reason == "retryable")


def test_instagram_error_codes_are_read_from_the_response_body() -> None:
    error = instagram.error_from_response(
        400, {"error": {"message": "outside window", "code": 10, "error_subcode": 2018278}}
    )

    assert (error.status, error.code, error.subcode) == (400, 10, 2018278)


def test_short_text_is_one_part() -> None:
    assert outbox.split_text("Vanakkam!") == ["Vanakkam!"]


def test_long_text_splits_at_a_sentence_into_parts_within_the_byte_limit() -> None:
    text = "Your cake is ready. " * 60 + "See you at six!"  # 1,215 bytes

    parts = outbox.split_text(text.strip())

    assert len(parts) == 2
    assert all(len(part.encode()) <= channels.MAX_TEXT_BYTES for part in parts)
    assert parts[0].endswith(".")
    assert " ".join(parts) == text.strip()


def test_text_too_long_for_two_parts_is_shortened_with_an_ellipsis() -> None:
    parts = outbox.split_text("cake " * 1000)

    assert len(parts) == 2
    assert all(len(part.encode()) <= channels.MAX_TEXT_BYTES for part in parts)
    assert parts[1].endswith("…")


def test_text_without_spaces_is_cut_on_a_character_boundary() -> None:
    parts = outbox.split_text("ஆ" * 400)  # 3 bytes each, 1,200 bytes

    assert all(len(part.encode()) <= channels.MAX_TEXT_BYTES for part in parts)
    assert "".join(parts) == "ஆ" * 400
