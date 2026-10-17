#!/usr/bin/env bash
# Build the image mochi's docker-compose.yml runs.
#
# Compose references this image by tag and does NOT build it. That is
# deliberate: `docker compose up` builds whenever an image is merely absent, so
# a `docker image prune -a` was previously enough to trigger a rebuild against
# a moved upstream without anyone typing the word "build". Now it fails loudly
# and you come here instead.
#
# Usage: ./build-image.sh [--verify]
#
#   --verify   after building, diff the resulting site-packages against the
#              running production container and report anything that moved

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

IMAGE=mochi/betanin
TAG=0.6.1-mochi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit first so the image matches a commit." >&2
    exit 1
fi

SHA=$(git rev-parse --short HEAD)

echo "==> Building $IMAGE:$TAG  (from $SHA)"
docker build -t "$IMAGE:$TAG" -t "$IMAGE:$SHA" .

echo
echo "Built and tagged:"
echo "    $IMAGE:$TAG"
echo "    $IMAGE:$SHA"

if [[ "${1:-}" != "--verify" ]]; then
    echo
    echo "Re-run with --verify to diff against the running container."
    exit 0
fi

echo
echo "==> Verifying against the running betanin container"
if ! docker inspect betanin >/dev/null 2>&1; then
    echo "    betanin is not running; nothing to compare against."
    exit 0
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SITE=/usr/lib/python3.14/site-packages

docker cp "betanin:$SITE" "$TMP/running" >/dev/null 2>&1
cid=$(docker create "$IMAGE:$TAG")
docker cp "$cid:$SITE" "$TMP/new" >/dev/null 2>&1
docker rm -f "$cid" >/dev/null

list() { ls "$1" | grep -E '\.dist-info$' | sed 's/\.dist-info$//' | sort; }
if diff <(list "$TMP/running") <(list "$TMP/new") > "$TMP/diff"; then
    echo "    Package set is identical to production."
else
    echo "    PACKAGES MOVED (< production, > new image):"
    sed 's/^/      /' "$TMP/diff"
    echo
    echo "    If this was not intentional, regenerate constraints.txt."
    exit 1
fi
