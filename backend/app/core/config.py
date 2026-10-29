"""Settings from environment variables (and backend/.env locally). See .env.example."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_DIR / ".env", extra="ignore")

    app_env: str = "local"  # local | dev | demo | prod
    log_level: str = "INFO"
    # Public HTTPS address of this API, used for OAuth redirects (locally: the tunnel URL).
    public_base_url: str = "http://localhost:8000"

    # postgresql://user:password@host:port/database (direct or session-pooler connection).
    database_url: str = ""
    # Run the job worker inside the API process (local development, small deployments).
    run_worker_in_process: bool = True

    # Comma-separated Fernet keys that encrypt channel access tokens; the first one encrypts.
    token_encryption_keys: str = ""
    # Signs OAuth `state` values.
    oauth_state_secret: str = ""
    # Signs the app's short-lived access tokens (keep it different from the other secrets).
    session_signing_key: str = ""
    # Where "Continue with Instagram" may send the merchant back to, comma-separated and
    # matched exactly: the mobile app's deep link and the web app's callback page.
    app_redirect_uris: str = "sellix://auth/callback"
    # Web origins allowed to call the API from a browser (the Flutter web app), comma-separated.
    web_app_origins: str = "http://localhost:8080"

    # Meta. Webhooks are signed with an app secret; apps that use Instagram login also have
    # a separate Instagram app secret, and either is accepted.
    meta_app_secret: str = ""
    instagram_app_id: str = ""
    instagram_app_secret: str = ""
    # Our own random string; Meta sends it back once when the webhook URL is registered.
    meta_verify_token: str = ""
    graph_api_version: str = "v23.0"
    # Meta must approve the app for the HUMAN_AGENT tag (a person's reply 24 hours to 7 days
    # after the customer's last message). Until then, late answers wait for the customer.
    instagram_human_agent_enabled: bool = False
    # Log full webhook payloads. Only for dev with test accounts:
    # payloads contain customer messages.
    log_webhook_payloads: bool = False

    # Any OpenAI-compatible chat completions API (xAI Grok, Google Gemini, OpenAI, Groq, ...).
    llm_base_url: str = ""
    llm_api_key: str = ""
    llm_model: str = ""
    # Models to try in order, e.g. "grok-4-fast,gemini-2.5-flash". Empty: just llm_model.
    llm_models: str = ""
    # "native": the provider's tool calling. "json": tool calls asked for as JSON (providers
    # without tool calling); the agent works the same either way.
    llm_tool_mode: Literal["native", "json"] = "native"
    # The model for images (stories, photos); empty: the chat model.
    llm_vision_model: str = ""
    # Per model call; a timeout is retried, then the next model is tried.
    llm_timeout_seconds: float = 20.0
    # For cost tracking, US dollars per million tokens: "model=input/output,...".
    llm_prices: str = ""
    # How to ask for JSON output: "json_object" (response_format) or "none" (prompt only).
    llm_json_mode: Literal["json_object", "none"] = "json_object"
    # For reasoning models (e.g. GPT-5 family): "minimal", "low", ... Empty: provider default.
    llm_reasoning_effort: str = ""

    # PayPal (Orders API v2). Payments are offered only when these are set.
    paypal_env: Literal["sandbox", "live"] = "sandbox"
    paypal_client_id: str = ""
    paypal_client_secret: str = ""
    # ID of the webhook registered in the PayPal app; needed to verify webhook signatures.
    paypal_webhook_id: str = ""
    # Unpaid orders give their held stock back after this many minutes.
    payment_hold_minutes: int = 15

    # Wait this long after a customer message before replying, so bursts get one reply.
    turn_batch_seconds: int = 3
    # v2 turn budgets (agent-phase-2.md section 6.2): beyond them, the holding message.
    agent_max_model_calls: int = 6
    agent_max_tool_calls: int = 10
    agent_turn_deadline_seconds: float = 30.0
    agent_repair_attempts: int = 1  # send_reply retries after failing the output checks
    agent_order_days_ahead: int = 14  # how far ahead customers can order (pre-orders)
    agent_max_images_per_turn: int = 3  # sent to the vision model; more: ask which one
    # Inbound protection (agent-phase-2.md section 12).
    inbound_max_message_chars: int = 1000  # per message, as the model sees it
    inbound_max_turn_chars: int = 2000  # a burst's messages together; oldest cut first
    inbound_too_long_chars: int = 4000  # beyond this: a template, no model call
    inbound_burst_messages: int = 20  # per customer per burst window ...
    inbound_burst_minutes: int = 5  # ... beyond which messages don't start turns
    agent_turns_per_hour: int = 30
    agent_turns_per_day: int = 150
    # Default daily AI budget per shop, US dollars (merchants.ai_daily_budget_usd overrides).
    agent_daily_budget_usd: float = 1.0
    # Messages of history the agent sees on each turn.
    history_messages: int = 20

    def missing_required(self) -> list[str]:
        """Settings the API can't work without."""
        required = {
            "DATABASE_URL": self.database_url,
            "TOKEN_ENCRYPTION_KEYS": self.token_encryption_keys,
            "OAUTH_STATE_SECRET": self.oauth_state_secret,
            "SESSION_SIGNING_KEY": self.session_signing_key,
            "META_VERIFY_TOKEN": self.meta_verify_token,
            "INSTAGRAM_APP_ID": self.instagram_app_id,
            "INSTAGRAM_APP_SECRET": self.instagram_app_secret,
            "LLM_BASE_URL": self.llm_base_url,
            "LLM_MODEL": self.llm_model,
        }
        return [name for name, value in required.items() if not value]


@lru_cache
def get_settings() -> Settings:
    return Settings()
