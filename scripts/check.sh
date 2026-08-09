#!/usr/bin/env sh
set -eu

. ./.env

docker compose config --quiet
docker compose exec -T api python -c \
  "import json, urllib.request; print(json.load(urllib.request.urlopen('http://gateway/v1/health/ready', timeout=10)))"
docker compose exec -T admin node -e \
  "fetch('http://gateway').then(async r => { console.log({adminStatus:r.status}); if (!r.ok) process.exit(1) }).catch(e => { console.error(e); process.exit(1) })"
docker compose ps
