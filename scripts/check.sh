#!/usr/bin/env sh
set -eu

. ./.env

docker compose config --quiet
docker compose exec -T api python -c \
  "import json, urllib.request; request=urllib.request.Request('http://gateway/v1/health/ready', headers={'Host':'edinburo.ru'}); print(json.load(urllib.request.urlopen(request, timeout=10)))"
docker compose exec -T web wget --header='Host: edinburo.ru' \
  -qO- http://gateway/ >/dev/null
docker compose exec -T web wget --header='Host: edinburo.ru' \
  -qO- http://gateway/robots.txt | grep -q 'Sitemap: https://edinburo.ru/sitemap.xml'
docker compose exec -T web wget --header='Host: edinburo.ru' \
  -qO- http://gateway/sitemap.xml | grep -q '<loc>https://edinburo.ru/</loc>'
for path in poteryal-veshch nashel-veshch poteryannye-veshchi naydennye-veshchi byuro-nahodok-moskva byuro-nahodok-sankt-peterburg; do
  docker compose exec -T web wget --header='Host: edinburo.ru' \
    -qO- "http://gateway/$path/" | grep -q '<link rel="canonical"'
done
docker compose exec -T admin node -e \
  "fetch('http://gateway', {headers:{Host:'admin.edinburo.ru'}}).then(async r => { console.log({adminStatus:r.status}); if (!r.ok) process.exit(1) }).catch(e => { console.error(e); process.exit(1) })"
docker compose ps
