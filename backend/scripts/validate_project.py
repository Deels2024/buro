import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "app/main.py",
    "app/worker.py",
    "app/db/models.py",
    "app/api/routes/auth.py",
    "app/api/routes/listings.py",
    "app/api/routes/claims.py",
    "app/api/routes/chat.py",
    "app/api/routes/organizations.py",
    "app/api/routes/admin.py",
    "app/api/routes/admin_console.py",
    "app/api/routes/support.py",
    "app/api/routes/app_meta.py",
    "app/api/routes/ads.py",
    "docker-compose.yml",
    "alembic/versions/0001_initial.py",
    "alembic/versions/0002_integration_ready.py",
    "clients/admin/bureau-api.ts",
    "clients/flutter/bureau_api_client.dart",
    "openapi.json",
    "VERSION",
]
ROUTE_MARKERS = [
    "/request-code",
    "/verify-code",
    "/ai/describe",
    "/ai/search",
    "/{listing_id}/matches",
    "/{claim_id}/decision",
    "/{claim_id}/contact-consent",
    "/handover/scan",
    "/{conversation_id}/ws",
    "/{organization_id}/dashboard",
    "/moderation/listings",
    "/events",
    "/analytics/overview",
    "/tickets",
    "/bootstrap",
    "/webhooks",
]


missing = [name for name in REQUIRED if not (ROOT / name).exists()]
if missing:
    raise SystemExit(f"Missing required files: {', '.join(missing)}")

python_files = [*ROOT.glob("app/**/*.py"), *ROOT.glob("scripts/*.py"), *ROOT.glob("tests/*.py")]
route_keys: list[tuple[str, str, str, str]] = []
for file in python_files:
    tree = ast.parse(file.read_text(encoding="utf-8"), filename=str(file))
    if file.parent.name == "routes":
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for decorator in node.decorator_list:
                if (
                    isinstance(decorator, ast.Call)
                    and isinstance(decorator.func, ast.Attribute)
                    and decorator.func.attr in {"get", "post", "put", "patch", "delete", "websocket"}
                    and decorator.args
                    and isinstance(decorator.args[0], ast.Constant)
                ):
                    router_name = (
                        decorator.func.value.id
                        if isinstance(decorator.func.value, ast.Name)
                        else "router"
                    )
                    route_keys.append(
                        (file.name, router_name, decorator.func.attr, decorator.args[0].value)
                    )

route_source = "\n".join(file.read_text(encoding="utf-8") for file in ROOT.glob("app/api/routes/*.py"))
missing_routes = [marker for marker in ROUTE_MARKERS if marker not in route_source]
if missing_routes:
    raise SystemExit(f"Missing critical routes: {', '.join(missing_routes)}")

model_source = (ROOT / "app/db/models.py").read_text(encoding="utf-8")
model_count = model_source.count("__tablename__ =")
if model_count < 28:
    raise SystemExit(f"Expected at least 28 tables, found {model_count}")
if len(route_keys) < 95 or len(set(route_keys)) != len(route_keys):
    raise SystemExit(f"Expected at least 95 unique API routes, found {len(route_keys)}/{len(set(route_keys))}")

print(
    f"Validation passed: {len(python_files)} Python files, "
    f"{model_count} database tables, {len(route_keys)} API routes"
)
