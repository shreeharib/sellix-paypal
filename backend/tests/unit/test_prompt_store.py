from pathlib import Path

import pytest

from app.modules.agent import prompt_store
from app.modules.agent.prompt_store import PromptError, PromptStore


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def test_every_prompt_file_in_the_repo_loads() -> None:
    store = PromptStore(prompt_store.PROMPTS_DIR)

    assert store.ref("v1.customer_agent").startswith("v1.customer_agent@")
    assert "en" in store.languages("v1.order_fallback")


def test_prompts_render_with_their_values(tmp_path: Path) -> None:
    write(tmp_path, "greeting.md", "---\nid: greeting\nversion: 3\n---\nHello {{ name }}!\n")
    store = PromptStore(tmp_path)

    assert store.render("greeting", name="Priya") == "Hello Priya!"
    assert store.ref("greeting") == "greeting@3"


def test_a_missing_value_is_an_error_not_an_empty_string(tmp_path: Path) -> None:
    write(tmp_path, "greeting.md", "---\nid: greeting\nversion: 1\n---\nHello {{ name }}!\n")
    store = PromptStore(tmp_path)

    with pytest.raises(PromptError, match="name"):
        store.render("greeting")


def test_templates_pick_the_customers_language_and_fall_back_to_english(tmp_path: Path) -> None:
    write(
        tmp_path,
        "templates/holding.yaml",
        "id: holding\nversion: 1\ntexts:\n  en: One moment, {{ name }}\n"
        "  ta-en: Konjam wait pannunga {{ name }}\n",
    )
    store = PromptStore(tmp_path)

    assert store.text("holding", "ta-en", name="Priya") == "Konjam wait pannunga Priya"
    assert store.text("holding", "hi", name="Priya") == "One moment, Priya"


@pytest.mark.parametrize(
    ("relative", "text", "problem"),
    [
        ("a.md", "Hello\n", "front matter"),
        ("a.md", "---\nid: a\n---\nHello\n", "version"),
        ("a.md", "---\nid: a\nversion: 1\nowner: me\n---\nHello\n", "owner"),
        ("a.md", "---\nid: a\nversion: 1\n---\nHello {{ name \n", "a.md"),
        ("t.yaml", "id: t\nversion: 1\ntexts:\n  ta: Vanakkam\n", "en"),
        ("t.yaml", "id: t\nversion: 1\ntexts:\n  en: Hi\n  fr: Salut\n", "fr"),
    ],
)
def test_a_broken_file_fails_loading(
    tmp_path: Path, relative: str, text: str, problem: str
) -> None:
    write(tmp_path, relative, text)

    with pytest.raises(PromptError, match=problem):
        PromptStore(tmp_path)


def test_two_files_with_the_same_id_fail_loading(tmp_path: Path) -> None:
    write(tmp_path, "a.md", "---\nid: same\nversion: 1\n---\nA\n")
    write(tmp_path, "b/a.md", "---\nid: same\nversion: 1\n---\nB\n")

    with pytest.raises(PromptError, match="same"):
        PromptStore(tmp_path)


def test_an_unknown_prompt_is_an_error(tmp_path: Path) -> None:
    store = PromptStore(tmp_path)

    with pytest.raises(PromptError, match="nope"):
        store.render("nope")
