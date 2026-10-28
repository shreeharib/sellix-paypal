"""Verify ADR-0001 modular monolith boundaries across backend/app."""

import ast
import importlib
import sys
from pathlib import Path

from app.core.config import BACKEND_DIR

APP_DIR = BACKEND_DIR / "app"
API_DIR = APP_DIR / "api"
MODULES_DIR = APP_DIR / "modules"
PUBLIC_SUBMODULES = {"service", "schemas"}
SQLALCHEMY_QUERY_BUILDERS = {"select", "insert", "update", "delete", "pg_insert"}


def _module_owner(file_path: Path) -> str | None:
    rel = file_path.relative_to(APP_DIR)
    if len(rel.parts) >= 2 and rel.parts[0] == "modules":
        return rel.parts[1]
    return None


def test_modules_only_expose_service_and_schemas_to_other_modules() -> None:
    """Problem 4 & 5: No module or router may import another module's internal submodules."""
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


def test_payment_writes_only_happen_inside_payments_module() -> None:
    """Problem 1: Payment ORM model is never imported or instantiated outside payments module."""
    violations: list[str] = []

    for py_file in sorted(APP_DIR.rglob("*.py")):
        if _module_owner(py_file) == "payments":
            continue
        rel_path = py_file.relative_to(APP_DIR)
        tree = ast.parse(py_file.read_text(encoding="utf-8"), filename=str(py_file))
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Name)
                and node.func.id == "Payment"
            ):
                violations.append(
                    f"{rel_path}:{node.lineno} instantiates Payment() outside payments module"
                )

    assert not violations, "Duplicate Payment creation outside payments module:\n" + "\n".join(
        violations
    )


def test_api_routers_do_not_build_raw_sqlalchemy_queries() -> None:
    """Problem 2: HTTP routers in app/api must delegate DB queries to module services."""
    violations: list[str] = []

    for py_file in sorted(API_DIR.rglob("*.py")):
        rel_path = py_file.relative_to(APP_DIR)
        tree = ast.parse(py_file.read_text(encoding="utf-8"), filename=str(py_file))
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.ImportFrom)
                and node.module
                and node.module.startswith("sqlalchemy")
            ):
                for alias in node.names:
                    imported_names = {alias.name, alias.asname}
                    if imported_names & SQLALCHEMY_QUERY_BUILDERS:
                        violations.append(
                            f"{rel_path}:{node.lineno} imports SQL query builder "
                            f"'{alias.name}' in API router"
                        )

    assert not violations, "API routers executing direct SQLAlchemy queries:\n" + "\n".join(
        violations
    )


def test_orders_and_payments_services_import_cleanly_in_both_directions() -> None:
    """Problem 3: Importing orders.service then payments.service (or vice versa) must not fail."""
    for first, second in (
        ("app.modules.orders.service", "app.modules.payments.service"),
        ("app.modules.payments.service", "app.modules.orders.service"),
    ):
        sys.modules.pop(first, None)
        sys.modules.pop(second, None)
        mod_first = importlib.import_module(first)
        mod_second = importlib.import_module(second)
        assert mod_first is not None
        assert mod_second is not None


def test_no_top_level_circular_imports_between_module_services() -> None:
    """Problem 3 (ER Diagram Alignment): Top-level imports between module services form a DAG."""
    graph: dict[str, set[str]] = {}

    for py_file in sorted(MODULES_DIR.rglob("service.py")):
        caller = _module_owner(py_file)
        if caller is None:
            continue
        graph.setdefault(caller, set())
        tree = ast.parse(py_file.read_text(encoding="utf-8"), filename=str(py_file))
        for node in tree.body:
            if isinstance(node, ast.ImportFrom) and node.module:
                parts = node.module.split(".")
                if len(parts) >= 3 and parts[0] == "app" and parts[1] == "modules":
                    target = parts[2]
                    if target != caller:
                        graph[caller].add(target)

    cycles: list[str] = []
    for mod_a, targets_a in sorted(graph.items()):
        for mod_b in sorted(targets_a):
            if mod_a < mod_b and mod_a in graph.get(mod_b, set()):
                cycles.append(f"{mod_a} <-> {mod_b}")

    assert not cycles, "Top-level circular module service imports detected:\n" + "\n".join(cycles)


def test_module_services_do_not_reexport_orm_models_or_sql_selects() -> None:
    """Problem 5: Module services must not re-export ORM model classes or SQL Select builders."""
    violations: list[str] = []

    for py_file in sorted(MODULES_DIR.rglob("service.py")):
        rel_path = py_file.relative_to(APP_DIR)
        tree = ast.parse(py_file.read_text(encoding="utf-8"), filename=str(py_file))
        model_names: set[str] = set()

        for node in tree.body:
            if isinstance(node, ast.ImportFrom) and node.module and node.module.endswith(".models"):
                for alias in node.names:
                    model_names.add(alias.asname or alias.name)
                    if alias.asname and alias.asname == alias.name:
                        violations.append(
                            f"{rel_path}:{node.lineno} re-exports ORM model '{alias.name}'"
                        )

        for node in tree.body:
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    if (
                        isinstance(target, ast.Name)
                        and target.id == "__all__"
                        and isinstance(node.value, (ast.List, ast.Tuple))
                    ):
                        for elt in node.value.elts:
                            if (
                                isinstance(elt, ast.Constant)
                                and isinstance(elt.value, str)
                                and elt.value in model_names
                            ):
                                violations.append(
                                    f"{rel_path}:{node.lineno} exposes ORM model "
                                    f"'{elt.value}' in __all__"
                                )
            if isinstance(node, ast.FunctionDef) and node.returns:
                ret_src = ast.unparse(node.returns)
                if "Select[" in ret_src or ret_src == "Select":
                    violations.append(
                        f"{rel_path}:{node.lineno} function '{node.name}' leaks SQLAlchemy Select"
                    )

    assert not violations, "ORM / SQL Select leaks in module services:\n" + "\n".join(violations)
