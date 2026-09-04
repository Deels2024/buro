#!/usr/bin/env sh
set -eu
export BN_RELEASE_SHA="${1:?Expected release SHA is required}"
docker compose exec -T api python -c '
import json,sys,urllib.request
expected=sys.argv[1]
request=urllib.request.Request("http://gateway/v1/health/ready",headers={"Host":"edinburo.ru"})
data=json.load(urllib.request.urlopen(request,timeout=10))
assert data["status"]=="ready" and data.get("release_sha")==expected, "Wrong active release"
assert data.get("worker")=="ok", "Worker has not activated the release"
print("Active API and worker release:",expected)
' "$BN_RELEASE_SHA"
./scripts/check.sh
