.PHONY: up down logs status ai

up:
	./install.sh

down:
	docker compose down

logs:
	docker compose logs -f --tail=200

status:
	./scripts/check.sh

ai:
	docker compose --profile ai up -d --build openclip
