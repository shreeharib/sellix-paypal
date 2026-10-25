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
    # Log full webhook payloads. Only for dev with test accounts:
    # payloads contain customer messages.
    log_webhook_payloads: bool = False

    # Any OpenAI-compatible chat completions API (xAI Grok, Google Gemini, OpenAI, Groq, ...).
    llm_base_url: str = ""
    llm_api_key: str = ""
    llm_model: str = ""
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
