.PHONY: bootstrap up down migrate test lint validate seed

bootstrap:
	cp .env.example .env
	docker compose up -d --build

up:
	docker compose up -d --build

down:
	docker compose down

migrate:
	docker compose run --rm api alembic upgrade head

seed:
	docker compose run --rm api python scripts/seed.py

test:
	pytest -q

lint:
	ruff check app tests scripts

validate:
	python scripts/validate_project.py
