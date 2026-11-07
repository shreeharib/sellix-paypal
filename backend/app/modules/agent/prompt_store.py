"""Prompts and fixed customer messages live in files under prompts/; this loads and fills them.

- `*.md` files are prompts for the model: a front-matter header (`id`, `version`) and a body.
- `*.yaml` files are fixed customer-facing texts sent by code, one per language.

Everything is loaded and checked at startup, so a broken file stops the app instead of a
customer's turn. Rendering uses StrictUndefined: a missing value is an error, never an empty
string. Only code-produced values go into these files; customer text is always a separate
message, never rendered into a prompt.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from jinja2 import Environment, StrictUndefined, Template, TemplateError

PROMPTS_DIR = Path(__file__).parent / "prompts"
LANGUAGES = ("en", "ta", "ta-en", "hi", "hi-en")
FALLBACK_LANGUAGE = "en"
_PROMPT_KEYS = {"id", "version", "applies_when", "description"}
_TEMPLATE_KEYS = {"id", "version", "texts", "description"}


class PromptError(RuntimeError):
    """A prompt file is broken, or a prompt was used wrongly."""


@dataclass(frozen=True)
class _Entry:
    id: str
    version: int
    path: Path
    # One template for a prompt; one per language for a customer-facing text.
    templates: Mapping[str, Template]


class PromptStore:
    def __init__(self, root: Path) -> None:
        self._environment = Environment(
            undefined=StrictUndefined, autoescape=False, keep_trailing_newline=False
        )
        self._entries: dict[str, _Entry] = {}
        for path in sorted(root.rglob("*")):
            if path.suffix == ".md" and path.name != "CHANGELOG.md":
                self._add(self._load_prompt(path))
            elif path.suffix == ".yaml":
                self._add(self._load_template(path))

    def render(self, prompt_id: str, **values: Any) -> str:
        """A prompt for the model, filled with code-produced values."""
        return self._fill(self._entry(prompt_id), "", values)

    def text(self, template_id: str, language: str, **values: Any) -> str:
        """A fixed customer-facing text in the customer's language (English if missing)."""
        entry = self._entry(template_id)
        return self._fill(
            entry, language if language in entry.templates else FALLBACK_LANGUAGE, values
        )

    def ref(self, prompt_id: str) -> str:
        """`id@version`, recorded with every turn that used the prompt."""
        entry = self._entry(prompt_id)
        return f"{entry.id}@{entry.version}"

    def languages(self, template_id: str) -> tuple[str, ...]:
        return tuple(self._entry(template_id).templates)

    def _entry(self, prompt_id: str) -> _Entry:
        entry = self._entries.get(prompt_id)
        if entry is None:
            raise PromptError(f"No prompt {prompt_id!r}")
        return entry

    def _fill(self, entry: _Entry, key: str, values: Mapping[str, Any]) -> str:
        try:
            return entry.templates[key].render(**values).strip()
        except TemplateError as exc:
            raise PromptError(f"{entry.id}: {exc}") from exc

    def _add(self, entry: _Entry) -> None:
        existing = self._entries.get(entry.id)
        if existing is not None:
            raise PromptError(f"Prompt id {entry.id!r} is in {existing.path} and {entry.path}")
        self._entries[entry.id] = entry

    def _load_prompt(self, path: Path) -> _Entry:
        text = path.read_text(encoding="utf-8")
        parts = text.split("---\n", 2)
        if len(parts) != 3 or parts[0].strip():
            raise PromptError(f"{path}: missing the front matter header (--- id, version ---)")
        header = self._header(path, parts[1], _PROMPT_KEYS)
        body = parts[2]
        return _Entry(header["id"], header["version"], path, {"": self._compile(path, body)})

    def _load_template(self, path: Path) -> _Entry:
        header = self._header(path, path.read_text(encoding="utf-8"), _TEMPLATE_KEYS)
        texts = header.get("texts")
        if not isinstance(texts, dict) or FALLBACK_LANGUAGE not in texts:
            raise PromptError(f"{path}: `texts` must have at least an `{FALLBACK_LANGUAGE}` text")
        unknown = set(texts) - set(LANGUAGES)
        if unknown:
            raise PromptError(f"{path}: unknown languages {sorted(unknown)}")
        templates = {
            str(language): self._compile(path, str(value)) for language, value in texts.items()
        }
        return _Entry(header["id"], header["version"], path, templates)

    def _header(self, path: Path, source: str, allowed: set[str]) -> dict[str, Any]:
        try:
            header = yaml.safe_load(source)
        except yaml.YAMLError as exc:
            raise PromptError(f"{path}: invalid YAML: {exc}") from exc
        if not isinstance(header, dict):
            raise PromptError(f"{path}: the header must be a mapping")
        unknown = set(header) - allowed
        if unknown:
            raise PromptError(f"{path}: unknown header keys {sorted(unknown)}")
        if not isinstance(header.get("id"), str) or not header["id"]:
            raise PromptError(f"{path}: `id` is required")
        version = header.get("version")
        if not isinstance(version, int) or isinstance(version, bool) or version < 1:
            raise PromptError(f"{path}: `version` must be a whole number from 1")
        return header

    def _compile(self, path: Path, source: str) -> Template:
        try:
            return self._environment.from_string(source)
        except TemplateError as exc:
            raise PromptError(f"{path}: {exc}") from exc


@lru_cache
def store() -> PromptStore:
    return PromptStore(PROMPTS_DIR)


def load() -> None:
    """Load and check every prompt file; call at startup so a broken file fails fast."""
    store()


def render(prompt_id: str, **values: Any) -> str:
    return store().render(prompt_id, **values)


def text(template_id: str, language: str, **values: Any) -> str:
    return store().text(template_id, language, **values)


def ref(prompt_id: str) -> str:
    return store().ref(prompt_id)
