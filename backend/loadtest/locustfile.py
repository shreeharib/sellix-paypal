"""Merchant-app traffic against a running API.

    uv run python -m loadtest.seed --shops 20
    uv run --group load locust -f loadtest/locustfile.py --host http://localhost:8000 \
        --users 100 --spawn-rate 10 --run-time 2m --headless

Each simulated user is one shop owner using the app (open Today, check orders and chats,
update stock, switch the assistant). Rate limits apply as in production, so use at least
as many shops as users / 3 or you will measure the limiter, not the API (429s show as failures).
"""

import itertools
import random
from pathlib import Path

from locust import HttpUser, between, task

TOKENS = [
    line
    for line in (Path(__file__).parent / "tokens.txt").read_text(encoding="utf-8").splitlines()
    if line
]
_next_token = itertools.count()


class ShopOwner(HttpUser):
    wait_time = between(1, 4)

    def on_start(self) -> None:
        token = TOKENS[next(_next_token) % len(TOKENS)]
        self.client.headers["Authorization"] = f"Bearer {token}"
        stock = self.client.get("/v1/today", name="GET /v1/today").json()["stock"]
        self.variant_ids = [row["variant_id"] for row in stock]

    @task(5)
    def open_today(self) -> None:
        self.client.get("/v1/today", name="GET /v1/today")

    @task(4)
    def check_orders(self) -> None:
        self.client.get("/v1/orders", name="GET /v1/orders")

    @task(3)
    def check_chats(self) -> None:
        self.client.get("/v1/conversations", name="GET /v1/conversations")

    @task(2)
    def open_catalog(self) -> None:
        self.client.get("/v1/products", name="GET /v1/products")
        self.client.get("/v1/stock/upcoming", name="GET /v1/stock/upcoming")

    @task(2)
    def check_questions(self) -> None:
        self.client.get("/v1/questions", name="GET /v1/questions")

    @task(1)
    def counter_sale(self) -> None:
        # The write path that touches the stock ledger.
        self.client.post(
            "/v1/today/restock",
            json={"variant_id": random.choice(self.variant_ids), "quantity": random.randint(1, 3)},
            name="POST /v1/today/restock",
        )
