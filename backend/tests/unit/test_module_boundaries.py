"""Verify ADR-0001 modular monolith boundaries across backend/app."""

import ast
from pathlib import Path

from app.core.config import BACKEND_DIR

APP_DIR = BACKEND_DIR / "app"
PUBLIC_SUBMODULES = {"service", "schemas"}


def _module_owner(file_path: Path) -> str | None:
    rel = file_path.relative_to(APP_DIR)
    if len(rel.parts) >= 2 and rel.parts[0] == "modules":
        return rel.parts[1]
    return None


def test_modules_only_expose_service_and_schemas_to_other_modules() -> None:
    violations: list[str] = []

    for py_file in sorted(APP_DIR.rglob("*.py")):
        rel_path = py_file.relative_to(APP_DIR)
        caller_module = _module_owner(py_file)
        is_main = rel_path == Path("main.py")

        tree = ast.parse(py_file.read_text(encoding="utf-8"), filename=str(py_file))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                parts = node.module.split(".")
                if len(parts) >= 3 and parts[0] == "app" and parts[1] == "modules":
                    target_module = parts[2]
                    if target_module == caller_module:
                        continue
                    allowed = PUBLIC_SUBMODULES | ({"router"} if is_main else set())
                    if len(parts) == 3:
                        for alias in node.names:
                            if alias.name not in allowed:
                                violations.append(
                                    f"{rel_path}:{node.lineno} imports internal "
                                    f"'{alias.name}' from app.modules.{target_module}"
                                )
                    else:
                        submodule = parts[3]
                        if submodule not in allowed:
                            violations.append(
                                f"{rel_path}:{node.lineno} imports internal '{node.module}'"
                            )

    assert not violations, "Modular monolith boundary violations:\n" + "\n".join(violations)
