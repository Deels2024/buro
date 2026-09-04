import argparse
import json
from pathlib import Path

from app.main import app


def main() -> None:
    parser = argparse.ArgumentParser(description="Export or verify the committed OpenAPI contract")
    parser.add_argument("--check", action="store_true", help="fail when openapi.json is stale")
    parser.add_argument("--output", type=Path, help="write a generated contract to a separate artifact")
    args = parser.parse_args()

    target = args.output or Path(__file__).resolve().parents[1] / "openapi.json"
    rendered = json.dumps(app.openapi(), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not target.exists() or target.read_text(encoding="utf-8") != rendered:
            raise SystemExit("openapi.json is stale; run python scripts/export_openapi.py")
        print(f"OpenAPI contract is current: {target}")
        return

    target.write_text(rendered, encoding="utf-8")
    print(f"OpenAPI exported to {target}")


if __name__ == "__main__":
    main()
